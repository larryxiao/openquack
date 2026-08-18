import AVFoundation
import Foundation

/// SPEC-044 — re-encode a recording to 16 kHz mono 16-bit WAV for upload.
/// The recorder writes at the device's native rate (often 48 kHz stereo);
/// Whisper-family endpoints resample to 16 kHz mono anyway, so shipping
/// anything more is pure upload weight (~6× on 48 kHz stereo).
public enum AudioResampler {

    /// Converts `url` to a fresh 16 kHz mono 16-bit WAV in the temporary
    /// directory. Caller owns (and should delete) the returned file.
    public static func wav16kMono(from url: URL) throws -> (url: URL, seconds: TimeInterval) {
        let input = try AVAudioFile(forReading: url)
        let seconds = Double(input.length) / input.fileFormat.sampleRate
        let inFormat = input.processingFormat

        guard let outFormat = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let converter = AVAudioConverter(from: inFormat, to: outFormat)
        else {
            throw EngineError.runtimeFailed("Couldn't set up 16 kHz mono conversion")
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openquack-upload-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey:             kAudioFormatLinearPCM,
            AVSampleRateKey:           16_000,
            AVNumberOfChannelsKey:     1,
            AVLinearPCMBitDepthKey:    16,
            AVLinearPCMIsFloatKey:     false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let output = try AVAudioFile(forWriting: outURL, settings: settings)

        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: 8192),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: 8192)
        else {
            throw EngineError.runtimeFailed("Couldn't allocate conversion buffers")
        }

        var reachedEnd = false
        while true {
            var conversionError: NSError?
            let status = converter.convert(to: outBuf, error: &conversionError) { _, outStatus in
                if reachedEnd {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                inBuf.frameLength = 0
                do {
                    try input.read(into: inBuf)
                } catch {
                    inBuf.frameLength = 0
                }
                if inBuf.frameLength == 0 {
                    reachedEnd = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return inBuf
            }
            if let conversionError {
                try? FileManager.default.removeItem(at: outURL)
                throw EngineError.runtimeFailed("Audio conversion failed: \(conversionError.localizedDescription)")
            }
            if outBuf.frameLength > 0 {
                try output.write(from: outBuf)
                outBuf.frameLength = 0
            }
            if status != .haveData { break }
        }

        return (outURL, seconds)
    }
}
