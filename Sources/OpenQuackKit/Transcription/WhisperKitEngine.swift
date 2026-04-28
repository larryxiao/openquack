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

    /// If `~/Documents/huggingface/models/` exists, move its contents into
    /// `<newBase>/models/` so HubApi finds the cached weights instead of
    /// re-downloading. Also folds an orphan `<newBase>/huggingface/` tree
    /// (left over from an earlier, buggy version of this migration) into
    /// the canonical `<newBase>/models/` location. Idempotent.
    private static func migrateLegacyDocumentsCache(into newBase: URL) {
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let legacyModels = docs.appendingPathComponent("huggingface", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
            if fm.fileExists(atPath: legacyModels.path) {
                let targetModels = newBase.appendingPathComponent("models", isDirectory: true)
                try? fm.createDirectory(at: targetModels, withIntermediateDirectories: true)
                mergeContents(of: legacyModels, into: targetModels)

                // Best-effort: prune the now-empty legacy parent.
                let legacyParent = docs.appendingPathComponent("huggingface", isDirectory: true)
                if let entries = try? fm.contentsOfDirectory(atPath: legacyParent.path), entries.isEmpty {
                    try? fm.removeItem(at: legacyParent)
                }
            }
        }

        // Always run, regardless of whether the Documents-folder migration
        // had anything to do — caches that already migrated may still have
        // an orphan `<newBase>/huggingface/` tree from the old code path.
        cleanupOrphanLegacyTree(in: newBase)
    }

    /// An earlier migration mistakenly placed weights at
    /// `<newBase>/huggingface/models/...`, where HubApi never looks. If we
    /// find that orphan tree, fold its contents into the canonical
    /// `<newBase>/models/` location and delete the orphan.
    private static func cleanupOrphanLegacyTree(in newBase: URL) {
        let fm = FileManager.default
        let orphanParent = newBase.appendingPathComponent("huggingface", isDirectory: true)
        let orphan = orphanParent.appendingPathComponent("models", isDirectory: true)
        let canonical = newBase.appendingPathComponent("models", isDirectory: true)

        if fm.fileExists(atPath: orphan.path) {
            try? fm.createDirectory(at: canonical, withIntermediateDirectories: true)
            mergeContents(of: orphan, into: canonical)
            // Drop the now-empty `models/` subdir.
            if let entries = try? fm.contentsOfDirectory(atPath: orphan.path), entries.isEmpty {
                try? fm.removeItem(at: orphan)
            }
        }
        // And the parent if everything underneath is gone.
        if let entries = try? fm.contentsOfDirectory(atPath: orphanParent.path), entries.isEmpty {
            try? fm.removeItem(at: orphanParent)
        }
    }

    /// Move every entry in `src` into `dst`. If a destination entry already
    /// exists, the source copy is deleted (treated as a duplicate). Used to
    /// reconcile the legacy/orphan model trees with the canonical one.
    private static func mergeContents(of src: URL, into dst: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: src.path) else { return }
        for entry in entries {
            let srcURL = src.appendingPathComponent(entry)
            let dstURL = dst.appendingPathComponent(entry)
            if fm.fileExists(atPath: dstURL.path) {
                // Recurse into directories so a partial overlap doesn't drop
                // weights the destination is missing.
                var isDir: ObjCBool = false
                fm.fileExists(atPath: srcURL.path, isDirectory: &isDir)
                if isDir.boolValue {
                    mergeContents(of: srcURL, into: dstURL)
                    if let leftover = try? fm.contentsOfDirectory(atPath: srcURL.path), leftover.isEmpty {
                        try? fm.removeItem(at: srcURL)
                    }
                } else {
                    try? fm.removeItem(at: srcURL)
                }
            } else {
                try? fm.moveItem(at: srcURL, to: dstURL)
            }
        }
    }

    /// Delete every cached WhisperKit model variant except `keeping`. Returns
    /// the number of bytes freed. Safe to call while the kept model is
    /// actively in use — we only touch sibling directories.
    @discardableResult
    public static func cleanupOtherModels(keeping: String, downloadBase: URL? = nil) -> Int64 {
        let fm = FileManager.default
        let cacheDir = downloadBase ?? defaultDownloadBase()

        // Reconcile the legacy orphan tree first so a single pass over the
        // canonical path is enough.
        cleanupOrphanLegacyTree(in: cacheDir)

        var freed: Int64 = 0

        // CoreML weights — argmaxinc/whisperkit-coreml/openai_whisper-<size>.
        let weightsRoot = cacheDir
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
        let weightsKeep = "openai_whisper-\(keeping)"
        if let entries = try? fm.contentsOfDirectory(atPath: weightsRoot.path) {
            for entry in entries where entry != weightsKeep && !entry.hasPrefix(".") {
                let url = weightsRoot.appendingPathComponent(entry)
                freed += directorySize(at: url)
                try? fm.removeItem(at: url)
            }
        }

        // Tokenizer/config — openai/whisper-<size> (a few MB each).
        let tokenizerRoot = cacheDir
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("openai", isDirectory: true)
        let tokenizerKeep = "whisper-\(keeping)"
        if let entries = try? fm.contentsOfDirectory(atPath: tokenizerRoot.path) {
            for entry in entries where entry != tokenizerKeep && !entry.hasPrefix(".") {
                let url = tokenizerRoot.appendingPathComponent(entry)
                freed += directorySize(at: url)
                try? fm.removeItem(at: url)
            }
        }
        return freed
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
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
