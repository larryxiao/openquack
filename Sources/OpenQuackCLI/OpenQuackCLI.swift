import ArgumentParser
import Foundation
import OpenQuackKit

@main
struct OpenQuackCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "openquack-cli",
        abstract: "Transcribe audio with WhisperKit (default) or Lightning.",
        version: OpenQuackKit.version,
        subcommands: [Transcribe.self, Models.self, Info.self],
        defaultSubcommand: Transcribe.self
    )
}

// MARK: - transcribe

struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe a single audio file."
    )

    @Argument(help: "Audio file path (.wav / .mp3 / .flac / .m4a).")
    var file: String

    @Option(name: [.customShort("e"), .long],
            help: "Engine: whisperkit (default) or lightning.")
    var engine: String = "whisperkit"

    @Option(name: [.customShort("m"), .long],
            help: "Model identifier (engine-specific). E.g. tiny, small, distil-large-v3.")
    var model: String = "small"

    @Option(name: .long,
            help: "Force language code (en, zh, ja, …). Default: auto-detect.")
    var language: String?

    @Flag(help: "Emit JSON instead of plain text.")
    var json: Bool = false

    @Flag(name: [.customShort("v"), .long],
          help: "Verbose progress (model load, timings) on stderr.")
    var verbose: Bool = false

    func run() async throws {
        let url = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("File not found: \(file)")
        }

        let kind = try EngineKind.parse(engine)

        if verbose {
            err("◇ \(kind.rawValue) / \(model): loading...")
        }
        let (eng, coldStart) = try await kind.makeEngine(model: model)
        if verbose {
            err("  ✓ loaded in \(fmt(coldStart, 2)) s")
        }

        let result = try await eng.transcribe(audioFile: url, language: language)
        let rtf = result.audioSeconds > 0 ? result.wallSeconds / result.audioSeconds : 0

        if json {
            var payload: [String: Any] = [
                "text": result.text,
                "audio_seconds": result.audioSeconds,
                "wall_seconds": result.wallSeconds,
                "rtf": rtf,
                "engine": kind.rawValue,
                "model": model,
                "cold_start_seconds": coldStart,
            ]
            if let lang = result.detectedLanguage {
                payload["language"] = lang
            }
            if let ttft = result.timeToFirstToken {
                payload["ttft_seconds"] = ttft
            }
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        } else {
            print(result.text)
            if verbose {
                err("  audio=\(fmt(result.audioSeconds, 2))s wall=\(fmt(result.wallSeconds, 2))s rtf=\(fmt(rtf, 2))× \(result.detectedLanguage.map { "lang=\($0)" } ?? "")")
            }
        }
    }
}

// MARK: - models

struct Models: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "List the suggested model identifiers per engine."
    )

    func run() throws {
        for kind in EngineKind.allCases {
            print("[\(kind.rawValue)]")
            for m in kind.suggestedModels {
                print("  \(m)")
            }
            print("")
        }
    }
}

// MARK: - info

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Print host info (chip, GPU, memory, macOS) used as the bench host tag."
    )

    func run() throws {
        let h = HostInfo.detect()
        print("chip:           \(h.chip)")
        print("cores:          \(h.coreCount)")
        if let g = h.gpuCoreCount { print("gpu cores:      \(g)") }
        print("memory:         \(String(format: "%.1f", h.memoryGB)) GB")
        print("macOS:          \(h.macOSVersion)")
        print("host tag:       \(h.hostTag)")
    }
}

// MARK: - helpers

private func err(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8) ?? Data())
}
private func fmt(_ x: Double, _ frac: Int) -> String {
    String(format: "%.\(frac)f", x)
}
