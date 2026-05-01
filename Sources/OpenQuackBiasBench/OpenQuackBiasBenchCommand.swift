import ArgumentParser
import AVFoundation
import Foundation
import OpenQuackPlatform
import WhisperKit

@main
struct OpenQuackBiasBenchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "openquack-bias-bench",
        abstract: "Whisper prompt-bias A/B: same audio, with/without initial-prompt, measure WER + proper-noun retention.",
        version: OpenQuackPlatform.version
    )

    @Option(name: .customLong("model"),
            help: "WhisperKit model id (e.g. tiny, small, medium).")
    var model: String = "medium"

    @Option(name: .customLong("vocab"),
            help: "Path to vocabulary JSON {\"terms\": [...]}.")
    var vocab: String = "bench/polish_corpus/vocabulary.json"

    @Option(name: .customLong("clips"),
            help: "Glob-style space-separated WAV paths, OR a directory walked recursively. Each <clip>.wav must have a paired <clip>.txt reference. Pairs with proper-noun-bearing references are most informative.")
    var clips: String

    @Option(name: .customLong("language"),
            help: "Force language code (en, zh, …). Default: auto.")
    var language: String?

    @Option(name: .customLong("focus-terms"),
            help: "Comma-separated list of substrings to track per-clip (proper nouns we care about). Defaults to the vocabulary.")
    var focusTerms: String?

    @Option(name: .customLong("out"),
            help: "Output directory. Default: bench/out/polish/<host-tag>-bias.")
    var out: String?

    @Flag(name: .customLong("verbose"))
    var verbose: Bool = false

    func run() async throws {
        let host = HostInfo.detect()
        let outDir = URL(fileURLWithPath: out ?? "bench/out/polish/\(host.hostTag)-bias")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let vocabURL = URL(fileURLWithPath: vocab)
        let terms = try loadVocab(at: vocabURL)
        let focus = (focusTerms?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                     ?? terms).filter { !$0.isEmpty }
        stderr("◇ vocab: \(terms.count) terms")
        stderr("◇ focus: \(focus.count) proper-noun substrings tracked per clip")

        let clipURLs = try expandClips(clips)
        stderr("◇ clips: \(clipURLs.count) audio files")

        // Load WhisperKit. Cache base mirrors WhisperKitEngine for shared weights.
        let cacheDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenQuack/WhisperKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        stderr("◇ loading WhisperKit \(model)…")
        let pipe = try await WhisperKit(WhisperKitConfig(
            model: model,
            downloadBase: cacheDir,
            verbose: false,
            logLevel: .error,
            load: true
        ))
        stderr("  ✓ loaded")

        guard let tokenizer = pipe.tokenizer else {
            throw NSError(domain: "OpenQuackBiasBench", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "tokenizer unavailable"
            ])
        }
        let promptText = " " + terms.joined(separator: ", ")
        let promptTokens = tokenizer.encode(text: promptText)
        stderr("◇ bias prompt: \(promptTokens.count) tokens")

        // Run each clip twice: once unbiased, once biased. Same WhisperKit instance,
        // tokens swapped per call.
        var rows: [Row] = []
        for (i, url) in clipURLs.enumerated() {
            let refURL = url.deletingPathExtension().appendingPathExtension("txt")
            guard let refData = try? String(contentsOf: refURL, encoding: .utf8) else {
                stderr("  [\(i+1)/\(clipURLs.count)] \(url.lastPathComponent): MISSING REF, skipping")
                continue
            }
            let reference = refData.trimmingCharacters(in: .whitespacesAndNewlines)

            let unbiased = try await transcribeOnce(pipe: pipe, url: url, language: language, promptTokens: nil)
            let biased   = try await transcribeOnce(pipe: pipe, url: url, language: language, promptTokens: promptTokens)

            let row = Row(
                clip: url.lastPathComponent,
                reference: reference,
                unbiasedText: unbiased.text,
                unbiasedWall: unbiased.wall,
                unbiasedWER: WER.compute(reference: reference, hypothesis: unbiased.text),
                unbiasedFocusHits: focusHits(focus: focus, in: unbiased.text),
                biasedText: biased.text,
                biasedWall: biased.wall,
                biasedWER: WER.compute(reference: reference, hypothesis: biased.text),
                biasedFocusHits: focusHits(focus: focus, in: biased.text),
                refFocusHits: focusHits(focus: focus, in: reference)
            )
            rows.append(row)
            if verbose {
                stderr(String(format: "  [%d/%d] %@ — WER %.2f→%.2f  focus %d→%d (ref %d)",
                              i + 1, clipURLs.count, url.lastPathComponent,
                              row.unbiasedWER, row.biasedWER,
                              row.unbiasedFocusHits, row.biasedFocusHits, row.refFocusHits))
            }
        }

        try writeReport(rows: rows, host: host, model: model, focus: focus, to: outDir)
        print("\n✓ \(outDir.path)/report.md")
        print("  \(outDir.path)/report.csv")
    }

    // MARK: - helpers

    private struct Row {
        let clip: String
        let reference: String
        let unbiasedText: String
        let unbiasedWall: Double
        let unbiasedWER: Double
        let unbiasedFocusHits: Int
        let biasedText: String
        let biasedWall: Double
        let biasedWER: Double
        let biasedFocusHits: Int
        let refFocusHits: Int
    }

    private func loadVocab(at url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        struct File: Decodable { let terms: [String] }
        return try JSONDecoder().decode(File.self, from: data).terms
    }

    private func expandClips(_ spec: String) throws -> [URL] {
        let fm = FileManager.default
        let parts = spec.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        var out: [URL] = []
        for p in parts {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = fm.enumerator(at: URL(fileURLWithPath: p), includingPropertiesForKeys: nil) {
                    for case let f as URL in enumerator where f.pathExtension.lowercased() == "wav" {
                        out.append(f)
                    }
                }
            } else if fm.fileExists(atPath: p) {
                out.append(URL(fileURLWithPath: p))
            } else {
                stderr("⚠ not found: \(p)")
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    private func focusHits(focus: [String], in text: String) -> Int {
        let lower = text.lowercased()
        return focus.filter { lower.contains($0.lowercased()) }.count
    }

    private struct CallResult {
        let text: String
        let wall: Double
    }

    private func transcribeOnce(pipe: WhisperKit, url: URL, language: String?, promptTokens: [Int]?) async throws -> CallResult {
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.verbose = false
        options.withoutTimestamps = true
        if let p = promptTokens, !p.isEmpty {
            options.promptTokens = p
        }
        let t0 = Date()
        let results = try await pipe.transcribe(audioPath: url.path, decodeOptions: options)
        let wall = Date().timeIntervalSince(t0)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return CallResult(text: text, wall: wall)
    }

    private func writeReport(rows: [Row], host: HostInfo, model: String, focus: [String], to dir: URL) throws {
        var md = "# WhisperKit prompt-bias A/B — \(host.hostTag) / \(model)\n\n"
        md += "**Date:** \(Date())\n\n"
        md += "**Vocabulary fed as bias prompt:** \(focus.count) terms\n\n"

        let unWERs   = rows.map(\.unbiasedWER).sorted()
        let biWERs   = rows.map(\.biasedWER).sorted()
        let unWALLs  = rows.map(\.unbiasedWall).sorted()
        let biWALLs  = rows.map(\.biasedWall).sorted()
        let unHits   = rows.reduce(0) { $0 + $1.unbiasedFocusHits }
        let biHits   = rows.reduce(0) { $0 + $1.biasedFocusHits }
        let refHits  = rows.reduce(0) { $0 + $1.refFocusHits }

        md += "## Aggregate (n=\(rows.count))\n\n"
        md += "| Metric | Unbiased | Biased | Δ |\n"
        md += "|---|---:|---:|---:|\n"
        md += "| Mean WER | \(pct(mean(unWERs))) | \(pct(mean(biWERs))) | \(pctDelta(mean(unWERs), mean(biWERs))) |\n"
        md += "| Median WER | \(pct(median(unWERs))) | \(pct(median(biWERs))) | \(pctDelta(median(unWERs), median(biWERs))) |\n"
        md += "| Mean wall | \(secs(mean(unWALLs))) | \(secs(mean(biWALLs))) | \(secs(mean(biWALLs) - mean(unWALLs))) |\n"
        md += "| Focus-term hits / total possible | \(unHits) / \(refHits) | \(biHits) / \(refHits) | \(biHits - unHits) |\n"
        md += "\n_Higher focus-hits = more proper nouns from vocabulary appearing in output. Δ-WER negative = biasing helped._\n"

        md += "\n## Per-clip\n\n"
        md += "| Clip | Ref WER | Bi WER | ΔWER | UnFocus | BiFocus | Reference (preview) | Unbiased | Biased |\n"
        md += "|---|---:|---:|---:|---:|---:|---|---|---|\n"
        for r in rows {
            let refPrev = r.reference.prefix(40).replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
            let unPrev  = r.unbiasedText.prefix(60).replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
            let biPrev  = r.biasedText.prefix(60).replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
            md += "| \(r.clip) | \(pct(r.unbiasedWER)) | \(pct(r.biasedWER)) | \(pctDelta(r.unbiasedWER, r.biasedWER)) | \(r.unbiasedFocusHits)/\(r.refFocusHits) | \(r.biasedFocusHits)/\(r.refFocusHits) | \(refPrev) | \(unPrev) | \(biPrev) |\n"
        }

        try md.write(to: dir.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)

        var csv = "clip,unbiased_wer,biased_wer,delta_wer,unbiased_wall_s,biased_wall_s,unbiased_focus,biased_focus,ref_focus,reference,unbiased,biased\n"
        for r in rows {
            csv += [
                r.clip,
                f(r.unbiasedWER, 4), f(r.biasedWER, 4), f(r.biasedWER - r.unbiasedWER, 4),
                f(r.unbiasedWall, 3), f(r.biasedWall, 3),
                String(r.unbiasedFocusHits), String(r.biasedFocusHits), String(r.refFocusHits),
                escape(r.reference), escape(r.unbiasedText), escape(r.biasedText)
            ].joined(separator: ",") + "\n"
        }
        try csv.write(to: dir.appendingPathComponent("report.csv"), atomically: true, encoding: .utf8)
    }
}

private func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0,+) / Double(xs.count) }
private func median(_ sorted: [Double]) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let n = sorted.count
    return n % 2 == 1 ? sorted[n/2] : (sorted[n/2 - 1] + sorted[n/2]) / 2
}
private func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
private func pctDelta(_ a: Double, _ b: Double) -> String {
    let d = b - a
    let sign = d > 0 ? "+" : ""
    return "\(sign)\(String(format: "%.1f", d * 100)) pp"
}
private func secs(_ x: Double) -> String { String(format: "%.2fs", x) }
private func f(_ x: Double, _ frac: Int) -> String { String(format: "%.\(frac)f", x) }
private func escape(_ s: String) -> String {
    if s.contains(",") || s.contains("\"") || s.contains("\n") {
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return s
}

func stderr(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8) ?? Data())
}
