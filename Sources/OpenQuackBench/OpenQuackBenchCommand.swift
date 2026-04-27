import ArgumentParser
import Foundation
import OpenQuackKit

@main
struct OpenQuackBenchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "openquack-bench",
        abstract: "Measure WER / RTF / TTFT / RSS across STT engines and models.",
        version: OpenQuackKit.version
    )

    @Option(name: .customLong("engines"),
            help: "Comma-separated engine names. Available: whisperkit, lightning")
    var engines: String = "whisperkit"

    @Option(name: .customLong("models"),
            help: "Comma-separated model identifiers. Same list applied to each engine.")
    var models: String = "tiny"

    @Option(name: .customLong("corpus"),
            help: "Path to a directory containing <name>.wav (or .mp3/.flac/.m4a) paired with <name>.txt reference transcripts. Walked recursively.")
    var corpus: String

    @Option(name: .customLong("out"),
            help: "Output directory. Default: bench/out/<host-tag>.")
    var out: String?

    @Option(name: .customLong("language"),
            help: "Force language code (en, zh, ja, …). Default: engine auto-detect.")
    var language: String?

    @Flag(name: .customLong("verbose"),
          help: "Stream per-clip progress to stderr.")
    var verbose: Bool = false

    func run() async throws {
        let host = HostInfo.detect()
        let outDir = URL(fileURLWithPath: out ?? "bench/out/\(host.hostTag)")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let corpusURL = URL(fileURLWithPath: corpus)
        let clips = try Corpus.load(at: corpusURL)
        guard !clips.isEmpty else {
            throw ValidationError("No clips found in '\(corpus)'. Each clip needs <name>.wav + <name>.txt.")
        }

        stderr("◇ host: \(host.hostTag) — \(host.chip), \(String(format: "%.0f", host.memoryGB)) GB, \(host.macOSVersion)")
        stderr("◇ corpus: \(clips.count) clips at \(corpusURL.path)")

        let engineKinds: [EngineKind] = try engines
            .split(separator: ",")
            .map { try EngineKind.parse(String($0).trimmingCharacters(in: .whitespaces)) }
        let modelList: [String] = models
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var allResults: [BenchResult] = []
        for kind in engineKinds {
            for model in modelList {
                let r = await BenchRunner.run(
                    engineKind: kind,
                    model: model,
                    clips: clips,
                    language: language,
                    verbose: verbose
                )
                allResults.append(r)
            }
        }

        try Report.writeMarkdown(allResults, host: host, to: outDir.appendingPathComponent("report.md"))
        try Report.writeCSV(allResults, to: outDir.appendingPathComponent("report.csv"))
        try Report.writeHostJSON(host: host, to: outDir.appendingPathComponent("host.json"))

        print("\n✓ \(outDir.path)/report.md")
        print("  \(outDir.path)/report.csv")
        print("  \(outDir.path)/host.json")
    }
}
