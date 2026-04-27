import Foundation

/// Wraps `bench/engines/lightning_runner.py` as a long-running subprocess so model load
/// happens once and we measure steady-state transcribe (not process spawn).
public final class LightningEngine: TranscriptionEngine {
    public static let engineName = "lightning"
    public static let suggestedModels = [
        "tiny", "small", "base", "medium",
        "large", "large-v2", "large-v3",
        "distil-small.en", "distil-medium.en",
        "distil-large-v2", "distil-large-v3",
    ]

    public let modelID: String
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe

    public init(model: String) async throws {
        self.modelID = model

        let runnerURL = URL(fileURLWithPath: "bench/engines/lightning_runner.py", isDirectory: false)
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: runnerURL.path) else {
            throw EngineError.loadFailed("lightning_runner.py not found at \(runnerURL.path) (run from repo root)")
        }

        let venvPython = URL(fileURLWithPath: ".venv/bin/python", isDirectory: false).standardizedFileURL
        let p = Process()
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            p.executableURL = venvPython
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
            throw EngineError.loadFailed("Failed to start lightning_runner.py: \(error)")
        }

        self.process = p
        self.stdinPipe = stdin
        self.stdoutPipe = stdout

        // Drive the LOAD command and wait for LOADED.
        try await send("LOAD \(model)")
        let response = try await readLine()
        if response.hasPrefix("ERROR ") {
            throw EngineError.loadFailed(String(response.dropFirst("ERROR ".count)))
        }
        guard response.hasPrefix("LOADED ") else {
            throw EngineError.loadFailed("Expected LOADED, got: \(response)")
        }
    }

    deinit {
        // Best-effort shutdown.
        let exitCmd = "EXIT\n".data(using: .utf8) ?? Data()
        try? stdinPipe.fileHandleForWriting.write(contentsOf: exitCmd)
        try? stdinPipe.fileHandleForWriting.close()
        process.terminate()
    }

    public func transcribe(audioFile url: URL, language: String?) async throws -> EngineTranscription {
        let langArg = language.map { " \($0)" } ?? ""
        try await send("TRANSCRIBE \(url.path)\(langArg)")
        let response = try await readLine()
        if response.hasPrefix("ERROR ") {
            throw EngineError.runtimeFailed(String(response.dropFirst("ERROR ".count)))
        }
        guard let data = response.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw EngineError.runtimeFailed("Invalid JSON from lightning_runner: \(response)")
        }
        let text = (json["text"] as? String) ?? ""
        let wall = (json["wall_seconds"] as? Double) ?? 0
        let audio = (json["audio_seconds"] as? Double) ?? 0
        let detected = json["language"] as? String

        return EngineTranscription(
            text: text,
            detectedLanguage: detected ?? language,
            audioSeconds: audio,
            wallSeconds: wall,
            timeToFirstToken: nil
        )
    }

    private func send(_ command: String) async throws {
        let data = (command + "\n").data(using: .utf8) ?? Data()
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw EngineError.runtimeFailed("write to runner stdin failed: \(error)")
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
                    if chunk.first == 0x0A { break }   // newline
                    buffer.append(chunk)
                }
                let line = String(data: buffer, encoding: .utf8) ?? ""
                cont.resume(returning: line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}
