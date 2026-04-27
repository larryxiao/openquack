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
/// Captures at the input's native format (e.g. 48 kHz stereo float32) and
/// writes a 16 kHz mono Int16 PCM WAV. We do the rate-and-channel conversion
/// explicitly via `AVAudioConverter` per buffer, then write the converted
/// buffer to `AVAudioFile`. (Earlier impl relied on `AVAudioFile.write(from:)`
/// to auto-convert from the input format; on macOS 15 that produced a WAV
/// whose header said 16 kHz but whose samples were the native rate, so
/// playback was 3× slow. Explicit conversion fixes it.)
///
/// Thread-safety: `start` / `stop` / `cancel` are protected by a lock. The
/// tap callback runs on the audio thread and uses closure-captured references
/// to the converter and file; `removeTap` before nilling the references is
/// what serialises teardown.
public final class AudioRecorder {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var _outputURL: URL?
    private var _startTime: Date?
    private var _isRecording = false

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

        // Target processing format: 16 kHz mono Float32 (what we'll feed to
        // AVAudioFile). Whisper wants 16 kHz; Float32 is what AVAudioConverter
        // produces natively; AVAudioFile down-bitdepths to Int16 on disk.
        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw RecorderError.engineFailed("Failed to create processing format")
        }

        // On-disk WAV settings — 16 kHz mono Int16, broadly compatible.
        let fileSettings: [String: Any] = [
            AVFormatIDKey:             kAudioFormatLinearPCM,
            AVSampleRateKey:           processingFormat.sampleRate,
            AVNumberOfChannelsKey:     Int(processingFormat.channelCount),
            AVLinearPCMBitDepthKey:    16,
            AVLinearPCMIsFloatKey:     false,
            AVLinearPCMIsBigEndianKey: false,
        ]

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

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: processingFormat) else {
            throw RecorderError.engineFailed(
                "Failed to create converter \(inputFormat) → \(processingFormat)"
            )
        }
        // High-quality offline-style resample; for voice this is well within budget.
        converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { inputBuffer, _ in
            let ratio = processingFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(
                ceil(Double(inputBuffer.frameLength) * ratio)
            ) + 1024  // safety margin for filter latency
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: capacity
            ) else { return }

            var error: NSError?
            var consumed = false
            converter.convert(to: outputBuffer, error: &error) { _, status in
                if consumed {
                    status.pointee = .endOfStream
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return inputBuffer
            }

            if let error {
                FileHandle.standardError.write(
                    "[AudioRecorder] convert error: \(error)\n".data(using: .utf8) ?? Data()
                )
                return
            }
            if outputBuffer.frameLength == 0 {
                return  // converter held back samples (filter latency); fine.
            }

            do {
                try file.write(from: outputBuffer)
            } catch {
                FileHandle.standardError.write(
                    "[AudioRecorder] write error: \(error)\n".data(using: .utf8) ?? Data()
                )
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
}
