import Foundation
import AVFoundation

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
public final class AudioRecorder {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var _outputURL: URL?
    private var _startTime: Date?
    private var _isRecording = false
    private var _peakRMS: Float = 0

    /// Peak raw-RMS (float32, ~0…1) seen across the current or most recent
    /// recording. Reset on `start()`, retained after `stop()` so callers can
    /// inspect it. Conversational speech peaks well above
    /// `silenceRMSThreshold`; a dead/muted mic or a virtual input device that
    /// emits silence stays near zero — letting callers warn the user instead
    /// of feeding silence to Whisper (which hallucinates "You." / "Thank you.").
    public var peakRMS: Float {
        lock.lock(); defer { lock.unlock() }
        return _peakRMS
    }

    /// Captures whose peak RMS stays under this are treated as "no usable
    /// audio". Conversational speech sits at RMS ~0.02–0.1; ambient room
    /// noise and silent virtual devices are well below this floor.
    public static let silenceRMSThreshold: Float = 0.005

    /// Called on the main queue with each buffer's RMS level (0…1, gently
    /// scaled for UI). Set this before calling `start` to drive a level meter.
    public var levelHandler: ((Float) -> Void)?

    /// SPEC-012: emitted on the audio thread for every captured tap buffer
    /// (~10–20 ms at typical input rates). Set before `start()`. Called
    /// with raw float32 samples in the input device's native rate; consumers
    /// must resample if they need 16 kHz. Opt-in — existing dictation-only
    /// callers leave it nil and pay nothing.
    public var framesHandler: (([Float], Double) -> Void)?

    public init() {}

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

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        // Route to the chosen device BEFORE reading the format — the input
        // node's format follows whatever device is current. Must touch the
        // node's audio unit first so it instantiates.
        if let uid = inputDeviceUID, !uid.isEmpty,
           let deviceID = AudioInputDevices.deviceID(forUID: uid),
           let unit = inputNode.audioUnit {
            var dev = deviceID
            let status = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &dev,
                UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr {
                FileHandle.standardError.write(
                    "[AudioRecorder] could not select input device \(uid): \(status)\n"
                        .data(using: .utf8) ?? Data())
            }
        }
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // WAV at the input device's native sample rate and channel count.
        // Stored as Int16 PCM (compact, broadly compatible). WhisperKit
        // resamples internally on read; the bench reads through the same path.
        let fileSettings: [String: Any] = [
            AVFormatIDKey:             kAudioFormatLinearPCM,
            AVSampleRateKey:           inputFormat.sampleRate,
            AVNumberOfChannelsKey:     Int(inputFormat.channelCount),
            AVLinearPCMBitDepthKey:    16,
            AVLinearPCMIsFloatKey:     false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        // Match the file's processing format to the tap format (Float32
        // non-interleaved at the input's native rate). `write(from:)` only has
        // a bit-depth conversion to do (Float32 → Int16) — same rate, same
        // channels — which it handles cleanly.
        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: url,
                settings: fileSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw RecorderError.fileWriteFailed("\(error)")
        }

        let levelHandler = self.levelHandler
        let framesHandler = self.framesHandler
        let inputSampleRate = inputFormat.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            do {
                try file.write(from: buffer)
            } catch {
                FileHandle.standardError.write(
                    "[AudioRecorder] write error: \(error)\n".data(using: .utf8) ?? Data()
                )
            }

            // One RMS pass per buffer, reused for both the silence detector and
            // the UI meter.
            let rms = Self.rawRMS(from: buffer)
            self?.recordPeak(rms)

            // Emit a UI-friendly level if anyone is subscribed.
            if let levelHandler {
                let level = Self.uiLevel(fromRMS: rms)
                DispatchQueue.main.async { levelHandler(level) }
            }

            // SPEC-012 streaming: emit raw float samples on the audio thread.
            // Consumer (StreamingTranscriber) is an actor; it'll re-enter on
            // its own queue, so this stays cheap on the capture thread.
            if let framesHandler,
               let channelData = buffer.floatChannelData?[0],
               buffer.frameLength > 0 {
                let count = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: count))
                framesHandler(samples, inputSampleRate)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RecorderError.engineFailed("\(error)")
        }

        self.engine = engine
        self.outputFile = file
        self._outputURL = url
        self._startTime = Date()
        self._isRecording = true
        self._peakRMS = 0
        return url
    }

    /// Audio-thread hook: fold this buffer's RMS into the running peak. Held
    /// under the same lock as start/stop; the critical section is a single
    /// `max`, so contention with the (infrequent) lifecycle calls is negligible.
    private func recordPeak(_ rms: Float) {
        lock.lock(); _peakRMS = max(_peakRMS, rms); lock.unlock()
    }

    /// Stop capture; returns the URL of the finalised WAV (caller owns cleanup).
    public func stop() -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard _isRecording else { return nil }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        outputFile = nil           // closes the file (AVAudioFile flushes on dealloc)
        _startTime = nil
        _isRecording = false

        let url = _outputURL
        _outputURL = nil
        return url
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
