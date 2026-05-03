import ArgumentParser
import Foundation
import OpenQuackPlatform

@main
struct OpenQuackPolishBenchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "openquack-polish-bench",
        abstract: "Bench local LLMs (via Ollama) for SPEC-007 polish + SPEC-008 in-context rewrite.",
        version: OpenQuackPlatform.version
    )

    @Option(name: .customLong("models"),
            help: "Comma-separated Ollama model tags. Default: the SPEC-007 candidate sweep.")
    var models: String = "gemma3:270m,qwen2.5:0.5b-instruct,gemma3:1b,llama3.2:1b,gemma3:4b-it-qat"

    @Option(name: .customLong("prompts"),
            help: "Comma-separated prompt version ids. Each (model × prompt) pair runs as its own row. Known: v1, v2.")
    var prompts: String = "v1,v2"

    @Option(name: .customLong("corpus"),
            help: "Path to polish corpus JSONL.")
    var corpus: String = "bench/polish_corpus/cases.jsonl"

    @Option(name: .customLong("ollama-url"),
            help: "Ollama base URL.")
    var ollamaURL: String = "http://localhost:11434"

    @Option(name: .customLong("out"),
            help: "Output directory. Default: bench/out/polish/<host-tag>.")
    var out: String?

    @Option(name: .customLong("only-category"),
            help: "Filter cases to one category: transcription_errors | rephrase_organize | in_context.")
    var onlyCategory: String?

    @Option(name: .customLong("only-language"),
            help: "Filter cases to one language code, e.g. en.")
    var onlyLanguage: String?

    @Option(name: .customLong("only-id"),
            help: "Run only the case with this id (smoke testing).")
    var onlyID: String?

    @Option(name: .customLong("vocab"),
            help: "Path to a vocabulary JSON {\"terms\": [...]}. When set, the terms fill the VOCABULARY slot of the system prompt.")
    var vocab: String?

    @Flag(name: .customLong("use-surrounding-text"),
          help: "Inject the case's surrounding_text field into the user message. Off by default so unaugmented baseline is the default.")
    var useSurroundingText: Bool = false

    @Flag(name: .customLong("verbose"),
          help: "Stream per-case progress to stderr.")
    var verbose: Bool = false

    @Flag(name: .customLong("unload-after"),
          help: "Send keep_alive=0 to each model after its run, so peak-pressure readings are clean between models.")
    var unloadAfter: Bool = false

    func run() async throws {
        let host = HostInfo.detect()
        let outDir = URL(fileURLWithPath: out ?? "bench/out/polish/\(host.hostTag)")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let corpusURL = URL(fileURLWithPath: corpus)
        var cases = try PolishCorpus.load(at: corpusURL)
        if let cat = onlyCategory {
            cases = cases.filter { $0.category.rawValue == cat }
        }
        if let lang = onlyLanguage {
            cases = cases.filter { $0.language == lang }
        }
        if let id = onlyID {
            cases = cases.filter { $0.id == id }
        }
        guard !cases.isEmpty else {
            throw ValidationError("No cases match filters in '\(corpus)'.")
        }

        let modelTags = models
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !modelTags.isEmpty else { throw ValidationError("--models is empty.") }

        let promptIDs = prompts
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let promptVersions = try PolishPrompts.resolve(promptIDs)

        guard let url = URL(string: ollamaURL) else { throw ValidationError("invalid --ollama-url") }
        let client = OllamaClient(baseURL: url)
        let installed = (try? await client.listModels()) ?? []
        let missing = modelTags.filter { tag in
            !installed.contains(where: { $0 == tag || $0.hasPrefix(tag + ":") || $0.split(separator: ":").first.map(String.init) == tag })
        }
        if !missing.isEmpty {
            stderr("⚠ models not in `ollama list`: \(missing.joined(separator: ", "))")
            stderr("  Pull them with: ollama pull <tag>")
        }

        stderr("◇ host: \(host.hostTag) — \(host.chip), \(String(format: "%.0f", host.memoryGB)) GB")
        stderr("◇ corpus: \(cases.count) cases at \(corpusURL.path)")
        stderr("◇ models: \(modelTags.joined(separator: ", "))")
        stderr("◇ prompts: \(promptVersions.map(\.id).joined(separator: ", "))")

        let vocabulary: [String] = try vocab.map { try VocabularyFile.load(at: URL(fileURLWithPath: $0)) } ?? []
        if !vocabulary.isEmpty {
            stderr("◇ vocabulary: \(vocabulary.count) terms loaded from \(vocab!)")
        }
        if useSurroundingText {
            stderr("◇ surrounding_text injection: ON")
        }

        var results: [PolishModelResult] = []
        for tag in modelTags {
            for prompt in promptVersions {
                let r = await PolishBenchRunner.run(
                    model: tag,
                    prompt: prompt,
                    cases: cases,
                    client: client,
                    vocabulary: vocabulary,
                    useSurroundingText: useSurroundingText,
                    verbose: verbose
                )
                results.append(r)
            }
            if unloadAfter {
                try? await client.unload(model: tag)
            }
        }

        try PolishReport.writeMarkdown(results, host: host, to: outDir.appendingPathComponent("report.md"))
        try PolishReport.writeCSV(results, to: outDir.appendingPathComponent("report.csv"))
        try PolishReport.writeJSONL(results, to: outDir.appendingPathComponent("results.jsonl"))

        print("\n✓ \(outDir.path)/report.md")
        print("  \(outDir.path)/report.csv")
        print("  \(outDir.path)/results.jsonl")
        print("\nNext: run `python bench/judge.py \(outDir.path)/results.jsonl` to add Haiku/Sonnet judge scores.")
    }
}

func stderr(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8) ?? Data())
}
