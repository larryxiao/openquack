import Foundation
import AVFoundation
import OQObjCSupport
import OpenQuackPlatform

public enum RecorderError: Error, CustomStringConvertible {
    case permissionDenied
    case engineFailed(String)
    case fileWriteFailed(String)

    public var description: String {
        switch self {
        case .permissionDenied:        return "Microphone permission denied"
        case .engineFailed(let s):     return "Audio engine failed: \(s)"
        case .fileWriteFailed(let s):  return "Recording write failed: \(s)"
        }
    }
}

/// SPEC-001 — Microphone capture.
///
/// Captures at the input device's native format and writes a WAV at the same
/// native rate. **No resampling at capture time.** Down-sampling to 16 kHz
/// happens later — WhisperKit's AudioProcessor handles it internally when
/// reading the file, and the bench's WAV reader can do the same.
///
/// Why no live resample: the obvious paths all have failure modes.
///   • `AVAudioFile.write(from:)` does *not* sample-rate-convert — passing a
///     48 kHz buffer to a 16 kHz-declared file silently writes the source
///     samples and emits a WAV that plays 3× slow.
///   • `AVAudioConverter` *does* convert, but the streaming pattern with
///     `.endOfStream` after each buffer flushes the SRC filter and silently
///     drops every input buffer after the first one.
///   • `AVAudioMixerNode` works but adds a node + connection juggling.
/// Native-rate capture sidesteps all of this and is lossless.
///
/// Thread-safety: `start` / `stop` / `cancel` are protected by a lock; the
/// tap closure runs on the audio thread and writes via a closure-captured
/// file reference. `removeTap` before nilling our reference is what
/// serialises teardown.
/// Holds the WAV writer for the audio-thread tap. Set once on the start thread
/// before `engine.start()` (so there's no concurrent mutation), then read by
/// the tap without locking.
private final class CaptureFileSink {
    var file: AVAudioFile?
}

public final class AudioRecorder {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var _outputURL: URL?
    private var _startTime: Date?
    private var _isRecording = false
    private var _activeInputDeviceUID: String?

    /// Dedicated lock for `_peakRMS` only. The audio-thread tap touches *this*
    /// lock, never the lifecycle `lock` — so `stop()`, which holds `lock` while
    /// calling `removeTap` (which drains in-flight tap callbacks), can never
    /// deadlock against a tap callback waiting on a lock `stop()` owns.
    private let peakLock = NSLock()
    private var _peakRMS: Float = 0

    /// Peak raw-RMS (float32, ~0…1) seen across the current or most recent
    /// recording. Reset on `start()`, retained after `stop()` so callers can
    /// inspect it. Conversational speech peaks well above
    /// `silenceRMSThreshold`; a dead/muted mic or a virtual input device that
    /// emits silence stays near zero — letting callers warn the user instead
    /// of feeding silence to Whisper (which hallucinates "You." / "Thank you.").
    public var peakRMS: Float {
        peakLock.lock(); defer { peakLock.unlock() }
        return _peakRMS
    }

    /// UID of the input device the most recent `start()` actually captured
    /// from — which may be the system default (`nil`) if the chosen device
    /// failed and we fell back. Callers should name *this* device in any
    /// "no sound from …" messaging, not the user's saved preference.
    public var activeInputDeviceUID: String? {
        lock.lock(); defer { lock.unlock() }
        return _activeInputDeviceUID
    }

    /// Captures whose peak RMS stays under this are treated as "no usable
    /// audio". Conversational speech sits at RMS ~0.02–0.1; ambient room
    /// noise and silent virtual devices are well below this floor.
    public static let silenceRMSThreshold: Float = 0.005

    /// SPEC-036 — total audio frames the tap actually delivered this session,
    /// and the input rate they were captured at. Compared against wall-clock
    /// `elapsedSeconds` to detect a tap that stopped mid-recording (the freeze
    /// signature). Lives in its own reference so the audio-thread tap can bump
    /// it without capturing `self`.
    private let frameCounter = FrameCounter()
    private var _capturedSampleRate: Double = 16000

    /// SPEC-036 — observer for `AVAudioEngineConfigurationChange` (device/route
    /// change). Removed before our own `engine.stop()` so teardown doesn't
    /// re-enter it.
    private var configObserver: NSObjectProtocol?

    /// Called on the main queue with each buffer's RMS level (0…1, gently
    /// scaled for UI). Set this before calling `start` to drive a level meter.
    public var levelHandler: ((Float) -> Void)?

    /// SPEC-012: emitted on the audio thread for every captured tap buffer
    /// (~10–20 ms at typical input rates). Set before `start()`. Called
    /// with raw float32 samples in the input device's native rate; consumers
    /// must resample if they need 16 kHz. Opt-in — existing dictation-only
    /// callers leave it nil and pay nothing.
    public var framesHandler: (([Float], Double) -> Void)?

    /// SPEC-036 — invoked on the main queue when `AVAudioEngine` reconfigures
    /// mid-capture (the usual cause of a frozen recording). The app uses it to
    /// auto-stop-and-transcribe instead of leaving the UI frozen. Set before
    /// `start()`.
    public var interruptionHandler: (() -> Void)?

    public init() {}

    /// Thread-safe frame tally bumped from the audio thread.
    private final class FrameCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var frames: Int64 = 0
        func add(_ n: Int) { lock.lock(); frames += Int64(n); lock.unlock() }
        func reset() { lock.lock(); frames = 0; lock.unlock() }
        var value: Int64 { lock.lock(); defer { lock.unlock() }; return frames }
    }

    /// SPEC-036 — seconds of audio the tap actually delivered this session.
    /// Survives `stop()` (reset only on the next `start()`) so the post-stop
    /// transcription path can compare it against wall-clock duration.
    public var capturedSeconds: TimeInterval {
        guard _capturedSampleRate > 0 else { return 0 }
        return Double(frameCounter.value) / _capturedSampleRate
    }

    public var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRecording
    }

    public var outputURL: URL? {
        lock.lock(); defer { lock.unlock() }
        return _outputURL
    }

    public var elapsedSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        guard let start = _startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// Returns true if microphone access is granted (or just got granted by the user).
    public static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    /// Start capture. If `outputURL` is omitted, writes to a fresh temp file.
    /// Pass an explicit URL (e.g. `~/Library/Application Support/.../last-recording.wav`)
    /// to keep the WAV around for inspection between runs.
    ///
    /// `inputDeviceUID` routes capture to a specific input device (resolved via
    /// `AudioInputDevices`); pass nil/empty for the system default. If the UID
    /// no longer resolves to a present device, we silently fall back to the
    /// system default rather than failing the recording.
    public func start(outputURL: URL? = nil, inputDeviceUID: String? = nil) throws -> URL {
        lock.lock(); defer { lock.unlock() }

        if _isRecording, let url = _outputURL {
            return url
        }

        let url: URL
        if let supplied = outputURL {
            url = supplied
            // Remove any prior recording at this path so we start fresh.
            try? FileManager.default.removeItem(at: supplied)
            try FileManager.default.createDirectory(
                at: supplied.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } else {
            url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("openquack-\(UUID().uuidString).wav")
        }

        // Graceful degradation: try the chosen device, then the system default.
        // A device whose formats all fail to install a tap degrades to the next
        // candidate instead of aborting the process.
        let deviceAttempts: [String?]
        if let uid = inputDeviceUID, !uid.isEmpty {
            deviceAttempts = [uid, nil]
        } else {
            deviceAttempts = [nil]
        }

        var lastError: Error?
        for deviceUID in deviceAttempts {
            do {
                let engine = try startEngineLocked(url: url, inputDeviceUID: deviceUID)
                self.engine = engine
                self._outputURL = url
                self._startTime = Date()
                self._isRecording = true
                // Record which device actually won (nil = system default), so
                // silent-capture messaging names the real device, not the saved
                // preference we may have just fallen back from.
                self._activeInputDeviceUID = (deviceUID?.isEmpty == false) ? deviceUID : nil
                return url
            } catch {
                lastError = error
                FileHandle.standardError.write(
                    "[AudioRecorder] device \(deviceUID ?? "<default>") failed: \(error)\n"
                        .data(using: .utf8) ?? Data())
            }
        }
        throw lastError ?? RecorderError.engineFailed("no usable input device")
    }

    /// Build + start a capture engine for one device. Caller holds `lock`.
    /// Routes to `inputDeviceUID` (nil = system default), then installs the tap
    /// trying a chain of candidate formats — each guarded by `OQTryCatch` so a
    /// format/hardware mismatch surfaces as a Swift error instead of an
    /// uncatchable Objective-C exception (SIGABRT). The WAV file is created
    /// lazily from the first buffer's real format, so it always matches whatever
    /// format actually wins — no rate/channel mismatch, no wrong-speed audio.
    private func startEngineLocked(url: URL, inputDeviceUID: String?) throws -> AVAudioEngine {
        outputFile = nil
        peakLock.lock(); _peakRMS = 0; peakLock.unlock()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        if let uid = inputDeviceUID, !uid.isEmpty,
           !AudioInputDevices.route(inputNode, toUID: uid) {
            throw RecorderError.engineFailed("could not select input device \(uid)")
        }
        // Prepare so the node reconciles to the (possibly just-switched) device
        // before we read its formats.
        engine.prepare()

        let levelHandler = self.levelHandler
        let framesHandler = self.framesHandler
        // The WAV is created on this (start) thread once the winning tap format
        // is known, and published into `sink` BEFORE engine.start(). The tap
        // then reads an immutable, ready file with no lock and never touches the
        // lifecycle `lock` — so stop()'s removeTap (which drains in-flight
        // callbacks while holding `lock`) cannot deadlock against it.
        let sink = CaptureFileSink()

        // SPEC-036 — fresh frame tally for this session; the captured rate is
        // set once the winning format is known (after the install loop below).
        frameCounter.reset()
        let frameCounter = self.frameCounter

        let tapBlock: AVAudioNodeTapBlock = { [weak self] buffer, _ in
            // SPEC-036 — count delivered frames before anything that can fail.
            frameCounter.add(Int(buffer.frameLength))
            guard let self else { return }
            if let file = sink.file {
                do { try file.write(from: buffer) }
                catch {
                    Diagnostics.shared.log(.recording, .error, "tap write failed: \(error)")
                }
            }
            let rms = Self.rawRMS(from: buffer)
            self.peakLock.lock(); self._peakRMS = max(self._peakRMS, rms); self.peakLock.unlock()

            if let levelHandler {
                DispatchQueue.main.async { levelHandler(Self.uiLevel(fromRMS: rms)) }
            }
            if let framesHandler,
               let channelData = buffer.floatChannelData?[0],
               buffer.frameLength > 0 {
                let count = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: count))
                framesHandler(samples, buffer.format.sampleRate)
            }
        }

        // Candidate tap formats, most-likely-correct first. installTap asserts
        // the passed format's sampleRate/channelCount against the hardware
        // format, so the hardware input format is the safest explicit choice;
        // `nil` lets the node pick its own; outputFormat is a last resort.
        let hwFormat = inputNode.inputFormat(forBus: 0)
        let outFormat = inputNode.outputFormat(forBus: 0)
        var candidates: [AVAudioFormat?] = []
        if hwFormat.sampleRate > 0, hwFormat.channelCount > 0 { candidates.append(hwFormat) }
        candidates.append(nil)
        if outFormat.sampleRate > 0, outFormat.channelCount > 0,
           outFormat.sampleRate != hwFormat.sampleRate {
            candidates.append(outFormat)
        }

        var winningFormat: AVAudioFormat?
        for fmt in candidates {
            let err = OQTryCatch {
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: fmt, block: tapBlock)
            }
            if err == nil {
                // A nil candidate makes the tap deliver the node's own format.
                winningFormat = fmt ?? inputNode.outputFormat(forBus: 0)
                break
            }
            // The failed attempt installed nothing, but be defensive before retry.
            _ = OQTryCatch { inputNode.removeTap(onBus: 0) }
        }
        guard let format = winningFormat else {
            throw RecorderError.engineFailed("could not install an audio tap on this input device")
        }
        // SPEC-036 — capturedSeconds divides the frame tally by this rate.
        _capturedSampleRate = format.sampleRate

        // Create the WAV eagerly from the winning format and publish it before
        // engine.start(). Surfacing a creation failure here (rather than a
        // silent nil inside the tap) means a broken sink fails the recording
        // loudly instead of "succeeding" into an empty/missing file.
        guard let file = Self.makeWAVFile(at: url, matching: format) else {
            _ = OQTryCatch { inputNode.removeTap(onBus: 0) }
            throw RecorderError.fileWriteFailed("could not create WAV at \(url.lastPathComponent)")
        }
        sink.file = file
        self.outputFile = file

        do {
            try engine.start()
        } catch {
            _ = OQTryCatch { inputNode.removeTap(onBus: 0) }
            Diagnostics.shared.log(.recording, .error, "engine start failed: \(error)")
            throw RecorderError.engineFailed("\(error)")
        }

        // SPEC-036 — notice device/route changes that silently stop the tap
        // (Bluetooth connect/disconnect, device switch, sample-rate change,
        // sleep/wake): without this the tap stops, the meter freezes, and only a
        // partial transcript comes back. Bound to this engine instance so we
        // don't catch unrelated graphs. Only treated as an interruption when the
        // engine actually stopped — benign reconfigs (output-device change,
        // codec renegotiation) must not cut a long dictation short.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange(engineRunning: engine.isRunning)
        }
        Diagnostics.shared.log(.recording, .info, String(format: "start: input %.0f Hz, %d ch", format.sampleRate, Int(format.channelCount)))
        return engine
    }

    /// SPEC-036/042 — the configuration-change → interruption decision, extracted
    /// from the observer so the fail-safe gate is unit-testable without
    /// `AVAudioEngine`. A config change is treated as an interruption ONLY when the
    /// engine actually stopped; a benign reconfig (output-device change, codec
    /// renegotiation) leaves capture running and must not cut a dictation short.
    /// Runs on the main queue (the observer's queue).
    func handleConfigurationChange(engineRunning: Bool) {
        let stopped = !engineRunning
        Diagnostics.shared.log(
            .recording, stopped ? .warn : .info,
            "AVAudioEngineConfigurationChange mid-capture (engine \(stopped ? "STOPPED" : "still running"))"
        )
        guard stopped else { return }
        interruptionHandler?()
    }

    // MARK: - SPEC-042 test seam

    /// Begin a hardware-free capture session for validation: reset the frame
    /// tally and pin the captured rate so `capturedSeconds` is meaningful without
    /// `AVAudioEngine`. Lets CI reproduce the freeze scenario (audio flows, then
    /// the tap dies on a config change) end-to-end. Not used by the live path.
    func beginCaptureForTesting(sampleRate: Double) {
        frameCounter.reset()
        _capturedSampleRate = sampleRate
    }

    /// Deliver a buffer's worth of samples through the capture data path the
    /// streaming consumer sees — the frame tally + `framesHandler` — mirroring the
    /// real tap, minus the WAV write + level meter (covered separately).
    func deliverFramesForTesting(_ samples: [Float], sampleRate: Double) {
        frameCounter.add(samples.count)
        framesHandler?(samples, sampleRate)
    }

    /// Create the Int16 WAV writer matching a captured buffer's format, so the
    /// file's rate/channels always equal what the tap actually delivers.
    private static func makeWAVFile(at url: URL, matching format: AVAudioFormat) -> AVAudioFile? {
        let settings: [String: Any] = [
            AVFormatIDKey:             kAudioFormatLinearPCM,
            AVSampleRateKey:           format.sampleRate,
            AVNumberOfChannelsKey:     Int(format.channelCount),
            AVLinearPCMBitDepthKey:    16,
            AVLinearPCMIsFloatKey:     false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        return try? AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
    }

    /// Stop capture; returns the URL of the finalised WAV (caller owns cleanup).
    public func stop() -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard _isRecording else { return nil }

        // SPEC-036 — drop the config-change observer first: `engine.stop()`
        // itself posts a configuration change, which would otherwise re-enter
        // the interruption handler during our own teardown.
        removeConfigObserverLocked()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        outputFile = nil           // closes the file (AVAudioFile flushes on dealloc)
        _startTime = nil
        _isRecording = false

        Diagnostics.shared.log(.recording, .info, String(format: "stop: captured %.1fs", capturedSeconds))

        let url = _outputURL
        _outputURL = nil
        return url
    }

    /// Tear down the config-change observer. Caller holds `lock`.
    private func removeConfigObserverLocked() {
        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
            configObserver = nil
        }
    }

    /// Stop and discard the WAV.
    public func cancel() {
        guard let url = stop() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Raw RMS of a PCM buffer in float32 amplitude (0…~1). Subsamples every
    /// 4th frame — plenty for both the meter and the silence detector.
    static func rawRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0],
              buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sumSq: Float = 0
        for i in stride(from: 0, to: count, by: 4) {
            let s = channelData[i]
            sumSq += s * s
        }
        return sqrt(sumSq / Float(count / 4 + 1))
    }

    /// Map a raw RMS to a 0…1 UI level. Loudness is roughly logarithmic so
    /// raw amplitude × constant feels dead — sqrt + a healthy multiplier makes
    /// a normal speaking voice swing across most of the meter. ×3 spreads
    /// conversational voice (RMS ~0.02–0.1) across roughly 0.4–0.95.
    static func uiLevel(fromRMS rms: Float) -> Float {
        let scaled = sqrt(rms) * 3.0
        return max(0, min(1.0, scaled))
    }
}
