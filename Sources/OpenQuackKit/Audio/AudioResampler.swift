import AVFoundation
import Foundation

/// SPEC-044 — re-encode a recording to 16 kHz mono 16-bit WAV for upload.
/// The recorder writes at the device's native rate (often 48 kHz stereo);
/// Whisper-family endpoints resample to 16 kHz mono anyway, so shipping
/// anything more is pure upload weight (~6× on 48 kHz stereo).
public enum AudioResampler {

    /// A file ready to be posted, with the multipart metadata that describes it.
    public struct Upload: Sendable {
        public let url: URL
        public let seconds: TimeInterval
        public let filename: String
        public let mimeType: String
    }

    /// WAV bytes above which the upload is re-encoded to AAC. Gateways commonly
    /// cap request bodies at 1 MB; at 32 KB/s a WAV crosses that around 30 s,
    /// so long recordings are compressed (~8× smaller) while short ones keep
    /// the format every endpoint accepts.
    public static let compressAboveBytes = 700_000

    /// The upload for a recording: 16 kHz mono WAV, re-encoded to AAC/m4a when
    /// the WAV would be large. Caller owns (and should delete) the returned file.
    public static func upload(from url: URL, compressAbove threshold: Int = compressAboveBytes) async throws -> Upload {
        let wav = try wav16kMono(from: url)
        let wavUpload = Upload(url: wav.url, seconds: wav.seconds, filename: "audio.wav", mimeType: "audio/wav")
        let size = (try? FileManager.default.attributesOfItem(atPath: wav.url.path)[.size] as? Int) ?? 0
        guard size > threshold else { return wavUpload }
        // Compression is an optimisation, never a failure mode: an encoder
        // problem falls back to the WAV the endpoint may still accept.
        guard let m4a = try? await aacM4A(from: wav.url) else { return wavUpload }
        try? FileManager.default.removeItem(at: wav.url)
        return Upload(url: m4a, seconds: wav.seconds, filename: "audio.m4a", mimeType: "audio/m4a")
    }

    /// Re-encodes a PCM file to 32 kbps mono AAC in an m4a container — one of
    /// the formats the OpenAI transcription API accepts, and ~8× smaller than
    /// the equivalent 16 kHz WAV with no measurable transcription difference.
    /// Written through AVAssetWriter: `AVAudioFile` cannot write compressed
    /// formats (every AAC setting combination fails with a nil error).
    public static func aacM4A(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw EngineError.runtimeFailed("Recording has no audio track to encode")
        }
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey:               kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey:      16,
            AVLinearPCMIsFloatKey:       false,
            AVLinearPCMIsBigEndianKey:   false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(readerOutput)

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openquack-upload-\(UUID().uuidString).m4a")
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .m4a)
        let sampleRate = try await track.load(.naturalTimeScale)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey:         kAudioFormatMPEG4AAC,
            AVSampleRateKey:       Double(sampleRate),
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey:   32_000,
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        guard writer.startWriting(), reader.startReading() else {
            try? FileManager.default.removeItem(at: outURL)
            throw EngineError.runtimeFailed("Couldn't start audio encode")
        }
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { continuation in
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "org.openquack.aac-encode")) {
                while input.isReadyForMoreMediaData {
                    guard let sample = readerOutput.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        writer.finishWriting { continuation.resume() }
                        return
                    }
                    if !input.append(sample) {
                        reader.cancelReading()
                        input.markAsFinished()
                        writer.finishWriting { continuation.resume() }
                        return
                    }
                }
            }
        }

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outURL)
            throw EngineError.runtimeFailed(
                "Audio encode failed: \(writer.error?.localizedDescription ?? "unknown")"
            )
        }
        return outURL
    }

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
