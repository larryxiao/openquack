import Foundation
import AVFoundation
import WhisperKit

public final class WhisperKitEngine: TranscriptionEngine {
    public static let engineName = "whisperkit"
    public static let suggestedModels = [
        "tiny", "tiny.en",
        "base", "base.en",
        "small", "small.en",
        "medium", "medium.en",
        "large-v2", "large-v3",
        "large-v3-turbo",
        "distil-large-v3",
    ]

    public let modelID: String
    private let pipe: WhisperKit

    public init(model: String) async throws {
        self.modelID = model
        do {
            let config = WhisperKitConfig(
                model: model,
                verbose: false,
                logLevel: .error,
                load: true
            )
            self.pipe = try await WhisperKit(config)
        } catch {
            throw EngineError.loadFailed("\(error)")
        }
    }

    public func transcribe(audioFile url: URL, language: String?) async throws -> EngineTranscription {
        return try await transcribe(audioFile: url, language: language, customWords: nil)
    }

    /// Extended transcribe that accepts a comma- or newline-separated list of
    /// custom words / phrases. They're tokenised and used as Whisper's prompt
    /// tokens, biasing the decoder toward proper nouns, jargon, etc.
    public func transcribe(
        audioFile url: URL,
        language: String?,
        customWords: String?
    ) async throws -> EngineTranscription {
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.verbose = false
        options.withoutTimestamps = true

        if let words = customWords?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty {
            // Newline-separated → comma-joined per Whisper convention.
            let joined = words
                .split(whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if !joined.isEmpty, let tokenizer = pipe.tokenizer {
                // Leading space matches OpenAI Whisper's prompt convention.
                options.promptTokens = tokenizer.encode(text: " " + joined)
            }
        }

        let t0 = Date()
        let results: [TranscriptionResult]
        do {
            results = try await pipe.transcribe(audioPath: url.path, decodeOptions: options)
        } catch {
            throw EngineError.runtimeFailed("\(error)")
        }
        let wall = Date().timeIntervalSince(t0)

        let text = results.map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let firstTimings = results.first?.timings
        let audioFromTimings = firstTimings?.inputAudioSeconds ?? 0
        let audioSecs = audioFromTimings > 0 ? audioFromTimings : audioDurationFallback(url)

        let ttft: TimeInterval? = firstTimings.flatMap {
            let delta = Double($0.firstTokenTime - $0.pipelineStart)
            return delta > 0 ? delta : nil
        }

        return EngineTranscription(
            text: text,
            detectedLanguage: results.first?.language,
            audioSeconds: audioSecs,
            wallSeconds: wall,
            timeToFirstToken: ttft
        )
    }

    private func audioDurationFallback(_ url: URL) -> TimeInterval {
        do {
            let file = try AVAudioFile(forReading: url)
            let secs = Double(file.length) / file.fileFormat.sampleRate
            return secs.isFinite && secs > 0 ? secs : 0
        } catch {
            return 0
        }
    }
}
