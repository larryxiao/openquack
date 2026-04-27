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

    /// Called on the main queue with each buffer's RMS level (0…1, gently
    /// scaled for UI). Set this before calling `start` to drive a level meter.
    public var levelHandler: ((Float) -> Void)?

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
    public func start(outputURL: URL? = nil) throws -> URL {
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

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            do {
                try file.write(from: buffer)
            } catch {
                FileHandle.standardError.write(
                    "[AudioRecorder] write error: \(error)\n".data(using: .utf8) ?? Data()
                )
            }

            // Emit a UI-friendly level if anyone is subscribed.
            if let levelHandler {
                let level = Self.uiLevel(from: buffer)
                DispatchQueue.main.async { levelHandler(level) }
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
        return url
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

    /// Compute a 0…1 UI level from a PCM buffer. RMS in float32 is typically
    /// 0…0.3 for normal voice; we apply a gentle log-ish curve so the meter
    /// feels responsive at low volumes without being pinned at high ones.
    private static func uiLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0],
              buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sumSq: Float = 0
        for i in stride(from: 0, to: count, by: 4) {  // every 4th sample is plenty for a meter
            let s = channelData[i]
            sumSq += s * s
        }
        let rms = sqrt(sumSq / Float(count / 4 + 1))
        // Boost low-volume response; clamp to 0...1.
        let boosted = min(1.0, rms * 6.0)
        return boosted
    }
}
