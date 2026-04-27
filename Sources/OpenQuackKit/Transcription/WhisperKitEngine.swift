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

    /// Foundation Progress object the pipe maintains across a transcribe call.
    /// KVO-observable on `\.fractionCompleted` — useful for a live progress bar.
    /// Reset by WhisperKit at the start of each transcribe.
    public var progress: Progress { pipe.progress }

    public init(model: String, downloadBase: URL? = nil) async throws {
        self.modelID = model

        // Default model cache: ~/Library/Application Support/OpenQuack/WhisperKit/.
        // Avoids the "OpenQuack wants to access files in your Documents folder"
        // TCC prompt that HubApi triggers when its downloadBase is nil — its
        // built-in default is `~/Documents/huggingface/`.
        let cacheDir = downloadBase ?? Self.defaultDownloadBase()
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // One-shot migration: if the user already has WhisperKit weights in
        // ~/Documents/huggingface/ from before this fix, move them so we
        // don't re-download. Best-effort — if Documents access has been
        // revoked, the move silently fails and WhisperKit re-downloads
        // into the new location.
        Self.migrateLegacyDocumentsCache(into: cacheDir)

        do {
            let config = WhisperKitConfig(
                model: model,
                downloadBase: cacheDir,
                verbose: false,
                logLevel: .error,
                load: true
            )
            self.pipe = try await WhisperKit(config)
        } catch {
            throw EngineError.loadFailed("\(error)")
        }
    }

    /// `~/Library/Application Support/OpenQuack/WhisperKit/`. App-private; no
    /// TCC prompt. Used by the app, the CLI, and the bench so they all share
    /// a single model cache.
    public static func defaultDownloadBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenQuack", isDirectory: true)
            .appendingPathComponent("WhisperKit", isDirectory: true)
    }

    /// Download the model weights into the cache without loading them. Useful
    /// for an onboarding flow that wants to show a real progress bar before
    /// the (fast, post-download) load step. Idempotent — if the weights are
    /// already cached, returns quickly with `onProgress(1.0)`.
    public static func ensureDownloaded(
        model: String,
        downloadBase: URL? = nil,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        let cacheDir = downloadBase ?? defaultDownloadBase()
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        migrateLegacyDocumentsCache(into: cacheDir)

        do {
            _ = try await WhisperKit.download(
                variant: model,
                downloadBase: cacheDir,
                progressCallback: { progress in
                    onProgress(progress.fractionCompleted)
                }
            )
            // Force the final tick so the UI lands at 100%.
            onProgress(1.0)
        } catch {
            throw EngineError.loadFailed("download failed: \(error)")
        }
    }

    /// If `~/Documents/huggingface/` exists and the new cache doesn't already
    /// have a `huggingface/` subtree, move it. Idempotent and safe to call on
    /// every launch.
    private static func migrateLegacyDocumentsCache(into newBase: URL) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let legacy = docs.appendingPathComponent("huggingface", isDirectory: true)
        let target = newBase.appendingPathComponent("huggingface", isDirectory: true)

        // Need legacy to exist and target to NOT exist (otherwise we'd merge
        // and risk corrupting in-progress downloads).
        guard fm.fileExists(atPath: legacy.path) else { return }
        if fm.fileExists(atPath: target.path) {
            // Already migrated (or fresh install with new code). Don't touch.
            return
        }

        do {
            try fm.moveItem(at: legacy, to: target)
        } catch {
            // Permissions revoked, or other transient error — fine. We'll
            // re-download into the new location.
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
