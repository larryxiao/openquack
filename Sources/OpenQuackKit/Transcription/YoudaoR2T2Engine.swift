import Foundation

// SPEC-046 (ASD-STE100) — NetEase Youdao Confucius4-R2T2 and Qwen3-ASR engine.
//
// Wraps `bench/engines/youdao_r2t2_runner.py` as a persistent subprocess.
// Normalizes CJK punctuation and extracts `<asr_text>` language metadata.

public final class YoudaoR2T2Engine: TranscriptionEngine {
    public static let engineName = "youdao"
    public static let defaultModel = "netease-youdao/Confucius4-R2T2"
    public static let suggestedModels = [
        "netease-youdao/Confucius4-R2T2",
        "Qwen/Qwen3-ASR-1.7B",
        "Qwen/Qwen3-ASR-0.6B",
    ]

    private static let modelAliases: [String: String] = [
        "confucius4-r2t2": "netease-youdao/Confucius4-R2T2",
        "r2t2": "netease-youdao/Confucius4-R2T2",
        "youdao": "netease-youdao/Confucius4-R2T2",
        "default": "netease-youdao/Confucius4-R2T2",
        "qwen3-asr-1.7b": "Qwen/Qwen3-ASR-1.7B",
        "qwen3-asr": "Qwen/Qwen3-ASR-1.7B",
        "qwen3-asr-0.6b": "Qwen/Qwen3-ASR-0.6B",
    ]

    private static let languageNameToCode: [String: String] = [
        "chinese": "zh",
        "english": "en",
        "japanese": "ja",
        "korean": "ko",
        "french": "fr",
        "german": "de",
        "spanish": "es",
        "italian": "it",
        "portuguese": "pt",
        "russian": "ru",
        "arabic": "ar",
    ]

    public let modelID: String
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe

    /// Resolve a short alias to a canonical HuggingFace model identifier.
    public static func resolveModelID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultModel }
        return modelAliases[trimmed.lowercased()] ?? trimmed
    }

    /// Extract the ISO-639-1 language code and normalized text from R2T2 output.
    public static func parseLanguageOutput(
        _ raw: String,
        fallbackLanguage: String? = nil
    ) -> (language: String?, text: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (fallbackLanguage, "") }

        let tag = "<asr_text>"
        if let range = trimmed.range(of: tag) {
            let metaPart = String(trimmed[..<range.lowerBound])
            let textPart = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            var detected: String? = nil
            let prefix = "language "
            for line in metaPart.components(separatedBy: .newlines) {
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.lowercased().hasPrefix(prefix) {
                    let val = String(clean.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !val.isEmpty, val.lowercased() != "none" {
                        detected = languageNameToCode[val.lowercased()] ?? val.lowercased()
                        break
                    }
                }
            }
            return (detected ?? fallbackLanguage, TextPolisher.normalizeCJKPunctuation(in: textPart))
        }
        return (fallbackLanguage, TextPolisher.normalizeCJKPunctuation(in: trimmed))
    }

    /// Format a tab-delimited TRANSCRIBE command for the Python runner.
    public static func formatTranscribeCommand(
        audioPath: String,
        language: String? = nil,
        customWords: String? = nil
    ) -> String {
        let cleanLang = language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ") ?? ""
        let cleanContext = customWords?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
            .replacingOccurrences(of: "\t", with: " ") ?? ""

        let langField = cleanLang.isEmpty ? "-" : cleanLang
        let contextField = cleanContext.isEmpty ? "-" : cleanContext
        return "TRANSCRIBE\t\(audioPath)\t\(langField)\t\(contextField)"
    }

    /// Parse one stdout line from `youdao_r2t2_runner.py` into `EngineTranscription`.
    public static func parseRunnerResponse(
        _ response: String,
        fallbackLanguage: String? = nil
    ) throws -> EngineTranscription {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ERROR ") {
            throw EngineError.runtimeFailed(String(trimmed.dropFirst("ERROR ".count)))
        }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw EngineError.runtimeFailed("Invalid JSON from youdao_r2t2_runner: \(trimmed)")
        }

        let rawText = (json["text"] as? String) ?? ""
        let wall = (json["wall_seconds"] as? Double) ?? 0
        let audio = (json["audio_seconds"] as? Double) ?? 0
        let rawLang = (json["language"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLang: String?
        if let rl = rawLang, !rl.isEmpty {
            normalizedLang = languageNameToCode[rl.lowercased()] ?? rl.lowercased()
        } else {
            normalizedLang = nil
        }

        let parsed = parseLanguageOutput(rawText, fallbackLanguage: normalizedLang ?? fallbackLanguage)
        return EngineTranscription(
            text: parsed.text,
            detectedLanguage: parsed.language,
            audioSeconds: audio,
            wallSeconds: wall,
            timeToFirstToken: nil
        )
    }

    /// Locate `youdao_r2t2_runner.py` across working directory and source tree.
    public static func locateRunnerURL(explicitPath: String? = nil) -> URL? {
        let fm = FileManager.default
        if let explicit = explicitPath, !explicit.isEmpty, fm.fileExists(atPath: explicit) {
            return URL(fileURLWithPath: explicit).standardizedFileURL
        }
        if let envPath = ProcessInfo.processInfo.environment["OPENQUACK_YOUDAO_RUNNER"],
           !envPath.isEmpty, fm.fileExists(atPath: envPath) {
            return URL(fileURLWithPath: envPath).standardizedFileURL
        }
        let cwdCandidate = URL(fileURLWithPath: "bench/engines/youdao_r2t2_runner.py").standardizedFileURL
        if fm.fileExists(atPath: cwdCandidate.path) {
            return cwdCandidate
        }
        // Fallback: resolve relative to this Swift source file during `swift test` or local builds.
        let sourceDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Transcription
            .deletingLastPathComponent() // OpenQuackKit
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // repo root
        let repoCandidate = sourceDir.appendingPathComponent("bench/engines/youdao_r2t2_runner.py")
        if fm.fileExists(atPath: repoCandidate.path) {
            return repoCandidate.standardizedFileURL
        }
        return nil
    }

    public init(model: String = YoudaoR2T2Engine.defaultModel, runnerPath: String? = nil) async throws {
        let resolvedModel = Self.resolveModelID(model)
        self.modelID = resolvedModel

        guard let runnerURL = Self.locateRunnerURL(explicitPath: runnerPath) else {
            throw EngineError.loadFailed(
                "youdao_r2t2_runner.py not found (run from repo root or set OPENQUACK_YOUDAO_RUNNER)"
            )
        }

        let p = Process()
        let fm = FileManager.default
        let envPython = ProcessInfo.processInfo.environment["OPENQUACK_YOUDAO_PYTHON"]
        let venvCandidates = [
            envPython,
            URL(fileURLWithPath: ".venv-youdao/bin/python").standardizedFileURL.path,
            URL(fileURLWithPath: ".venv/bin/python").standardizedFileURL.path,
        ].compactMap { $0 }

        if let pythonBin = venvCandidates.first(where: { !$0.isEmpty && fm.isExecutableFile(atPath: $0) }) {
            p.executableURL = URL(fileURLWithPath: pythonBin)
            p.arguments = [runnerURL.path]
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["python3", runnerURL.path]
        }

        let stdin = Pipe()
        let stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = FileHandle.standardError

        do {
            try p.run()
        } catch {
            throw EngineError.loadFailed("Failed to start youdao_r2t2_runner.py: \(error)")
        }

        self.process = p
        self.stdinPipe = stdin
        self.stdoutPipe = stdout

        try await send("LOAD \(resolvedModel)")
        let response = try await readLine()
        if response.hasPrefix("ERROR ") {
            throw EngineError.loadFailed(String(response.dropFirst("ERROR ".count)))
        }
        guard response.hasPrefix("LOADED ") else {
            throw EngineError.loadFailed("Expected LOADED from youdao_r2t2_runner, got: \(response)")
        }
    }

    deinit {
        let exitCmd = "EXIT\n".data(using: .utf8) ?? Data()
        try? stdinPipe.fileHandleForWriting.write(contentsOf: exitCmd)
        try? stdinPipe.fileHandleForWriting.close()
        process.terminate()
    }

    public func transcribe(audioFile url: URL, language: String?) async throws -> EngineTranscription {
        try await transcribe(audioFile: url, language: language, customWords: nil)
    }

    public func transcribe(
        audioFile url: URL,
        language: String?,
        customWords: String?
    ) async throws -> EngineTranscription {
        let cmd = Self.formatTranscribeCommand(
            audioPath: url.path,
            language: language,
            customWords: customWords
        )
        try await send(cmd)
        let response = try await readLine()
        return try Self.parseRunnerResponse(response, fallbackLanguage: language)
    }

    private func send(_ command: String) async throws {
        let data = (command + "\n").data(using: .utf8) ?? Data()
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw EngineError.runtimeFailed("write to youdao_r2t2_runner stdin failed: \(error)")
        }
    }

    private func readLine() async throws -> String {
        let handle = stdoutPipe.fileHandleForReading
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()
                while true {
                    let chunk: Data
                    do {
                        chunk = try handle.read(upToCount: 1) ?? Data()
                    } catch {
                        cont.resume(throwing: EngineError.runtimeFailed("read failed: \(error)"))
                        return
                    }
                    if chunk.isEmpty { break }
                    if chunk.first == 0x0A { break }
                    buffer.append(chunk)
                }
                let line = String(data: buffer, encoding: .utf8) ?? ""
                cont.resume(returning: line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}
