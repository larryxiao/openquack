import ArgumentParser
import AVFoundation
import Foundation
import OpenQuackPlatform
import WhisperKit

@main
struct OpenQuackStreamBenchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "openquack-stream-bench",
        abstract: "SPEC-012: long-audio post-stop wait. Offline baseline today; --mode streaming once StreamingTranscriber lands.",
        version: OpenQuackPlatform.version
    )

    @Option(name: .customLong("model"),
            help: "WhisperKit model id (e.g. tiny, small, medium).")
    var model: String = "medium"

    @Option(name: .customLong("clips"),
            help: "Directory walked recursively for *.wav (with paired *.txt). Default: bench/corpus/long.")
    var clips: String = "bench/corpus/long"

    @Option(name: .customLong("mode"),
            help: "offline | streaming. Streaming requires StreamingTranscriber (not yet wired).")
    var mode: String = "offline"

    @Option(name: .customLong("language"),
            help: "Force language code (en, zh, …). Default: en for the long corpus.")
    var language: String? = "en"

    @Option(name: .customLong("chunking"),
            help: "vad | none. Default vad (matches what SPEC-012 calls the 'offline' path).")
    var chunking: String = "vad"

    @Option(name: .customLong("out"),
            help: "Output directory. Default: bench/out/stream/<host-tag>.")
    var out: String?

    @Flag(name: .customLong("verbose"))
    var verbose: Bool = false

    func run() async throws {
        let host = HostInfo.detect()
        let outDir = URL(fileURLWithPath: out ?? "bench/out/stream/\(host.hostTag)")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        guard mode == "offline" else {
            throw ValidationError("--mode \(mode) not implemented yet — offline only for SPEC-012 phase 1")
        }
        guard let chunkStrategy = parseChunking(chunking) else {
            throw ValidationError("--chunking must be vad or none")
        }

        let clipURLs = try walkWAVs(at: clips)
        guard !clipURLs.isEmpty else {
            throw ValidationError("no *.wav under \(clips)")
        }
        stderr("◇ clips: \(clipURLs.count) under \(clips)")

        // Mirror WhisperKitEngine's cache layout so the medium weights can be reused.
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

        // Warm-up: a single short call so the first measured clip isn't paying
        // first-call cost (graph compile, weight prefetch).
        if let first = clipURLs.first {
            stderr("◇ warm-up on \(first.lastPathComponent)…")
            _ = try? await transcribeOffline(pipe: pipe, url: first,
                                              language: language,
                                              chunkStrategy: chunkStrategy)
            stderr("  ✓ warm")
        }

        var rows: [Row] = []
        for (i, url) in clipURLs.enumerated() {
            let refURL = url.deletingPathExtension().appendingPathExtension("txt")
            let reference = (try? String(contentsOf: refURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let audioSecs = audioDuration(url) ?? 0

            let r = try await transcribeOffline(pipe: pipe, url: url,
                                                 language: language,
                                                 chunkStrategy: chunkStrategy)

            let row = Row(
                clip: url.lastPathComponent,
                bucket: bucketFor(seconds: audioSecs),
                audioSeconds: audioSecs,
                wallSeconds: r.wall,
                rtf: audioSecs > 0 ? r.wall / audioSecs : 0,
                ttft: r.ttft,
                reference: reference,
                hypothesis: r.text,
                wer: WER.compute(reference: reference, hypothesis: r.text),
                refWords: wordCount(reference),
                hypWords: wordCount(r.text)
            )
            rows.append(row)
            if verbose {
                stderr(String(format: "  [%d/%d] %@  audio %.1fs  wall %.2fs  rtf %.2f  wer %.1f%%  ratio %.2f",
                              i + 1, clipURLs.count, url.lastPathComponent,
                              row.audioSeconds, row.wallSeconds, row.rtf,
                              row.wer * 100,
                              Double(row.hypWords) / max(Double(row.refWords), 1)))
            }
        }

        try writeReport(rows: rows, host: host, model: model, mode: mode, chunking: chunking, to: outDir)
        print("\n✓ \(outDir.path)/report.md")
        print("  \(outDir.path)/report.csv")

        printSanity(rows: rows)
    }

    // MARK: - core call

    private struct Call {
        let text: String
        let wall: Double
        let ttft: Double?
    }

    private func transcribeOffline(pipe: WhisperKit, url: URL, language: String?, chunkStrategy: ChunkingStrategy?) async throws -> Call {
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.verbose = false
        options.withoutTimestamps = true
        if let s = chunkStrategy {
            options.chunkingStrategy = s
        }
        let t0 = Date()
        let results = try await pipe.transcribe(audioPath: url.path, decodeOptions: options)
        let wall = Date().timeIntervalSince(t0)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let ttft: Double? = {
            guard let t = results.first?.timings else { return nil }
            let d = Double(t.firstTokenTime - t.pipelineStart)
            return d > 0 ? d : nil
        }()
        return Call(text: text, wall: wall, ttft: ttft)
    }

    // MARK: - reporting

    private struct Row {
        let clip: String
        let bucket: String
        let audioSeconds: Double
        let wallSeconds: Double
        let rtf: Double
        let ttft: Double?
        let reference: String
        let hypothesis: String
        let wer: Double
        let refWords: Int
        let hypWords: Int
    }

    private func writeReport(rows: [Row], host: HostInfo, model: String, mode: String, chunking: String, to dir: URL) throws {
        var md = "# Long-audio post-stop wait — \(host.hostTag) / \(model)\n\n"
        md += "**Date:** \(Date())\n"
        md += "**Mode:** \(mode)  •  **Chunking:** \(chunking)  •  **Clips:** \(rows.count)\n\n"
        md += "Post-stop wait under SPEC-012 = whole `wall` cell. Streaming targets:\n"
        md += "30s ≤ 1.5s · 60s ≤ 1.5s · 120s ≤ 2.0s · 300s ≤ 2.5s.\n\n"

        // By bucket
        let buckets = Set(rows.map(\.bucket)).sorted(by: bucketOrder)
        md += "## By length bucket\n\n"
        md += "| Bucket | n | mean audio | mean wall | mean RTF | mean WER | hyp/ref words |\n"
        md += "|---|---:|---:|---:|---:|---:|---:|\n"
        for b in buckets {
            let bs = rows.filter { $0.bucket == b }
            let aud = bs.map(\.audioSeconds).avg
            let wall = bs.map(\.wallSeconds).avg
            let rtf = bs.map(\.rtf).avg
            let wer = bs.map(\.wer).avg
            let ratio = bs.map { Double($0.hypWords) / max(Double($0.refWords), 1) }.avg
            md += "| \(b) | \(bs.count) | \(secs(aud)) | \(secs(wall)) | \(f(rtf, 2)) | \(pct(wer)) | \(f(ratio, 2)) |\n"
        }
        md += "\n_hyp/ref words ratio_ catches silent truncation (e.g. `chunkingStrategy=none` on > 30 s audio cuts the tail; ratio drops well below 1.0).\n"

        md += "\n## Per-clip\n\n"
        md += "| Clip | bucket | audio (s) | wall (s) | RTF | TTFT | WER | refW | hypW | ratio |\n"
        md += "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|\n"
        for r in rows.sorted(by: { ($0.bucket, $0.clip) < ($1.bucket, $1.clip) }) {
            let ttft = r.ttft.map { secs($0) } ?? "—"
            let ratio = Double(r.hypWords) / max(Double(r.refWords), 1)
            md += "| \(r.clip) | \(r.bucket) | \(f(r.audioSeconds, 1)) | \(f(r.wallSeconds, 2)) | \(f(r.rtf, 2)) | \(ttft) | \(pct(r.wer)) | \(r.refWords) | \(r.hypWords) | \(f(ratio, 2)) |\n"
        }

        try md.write(to: dir.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)

        var csv = "clip,bucket,audio_s,wall_s,rtf,ttft_s,wer,ref_words,hyp_words,ratio,reference,hypothesis\n"
        for r in rows {
            let ratio = Double(r.hypWords) / max(Double(r.refWords), 1)
            csv += [
                r.clip, r.bucket,
                f(r.audioSeconds, 3), f(r.wallSeconds, 3), f(r.rtf, 4),
                r.ttft.map { f($0, 3) } ?? "",
                f(r.wer, 4),
                String(r.refWords), String(r.hypWords), f(ratio, 4),
                escape(r.reference), escape(r.hypothesis)
            ].joined(separator: ",") + "\n"
        }
        try csv.write(to: dir.appendingPathComponent("report.csv"), atomically: true, encoding: .utf8)
    }

    private func printSanity(rows: [Row]) {
        // Sanity check: a wildly low hyp/ref ratio means silent truncation.
        // Threshold 0.7 is loose — real Whisper output of TTS is usually 0.95+.
        let bad = rows.filter { Double($0.hypWords) / max(Double($0.refWords), 1) < 0.7 }
        if bad.isEmpty {
            stderr("\n✓ sanity: every clip's transcript covers ≥ 70% of reference word count")
        } else {
            stderr("\n⚠ sanity: \(bad.count) clip(s) likely truncated:")
            for r in bad {
                let ratio = Double(r.hypWords) / max(Double(r.refWords), 1)
                stderr(String(format: "    %@  audio %.1fs  refW %d  hypW %d  ratio %.2f",
                              r.clip, r.audioSeconds, r.refWords, r.hypWords, ratio))
            }
            stderr("  Likely cause: chunkingStrategy=none on > 30 s audio. Try --chunking vad.")
        }
    }

    // MARK: - helpers

    private func parseChunking(_ s: String) -> ChunkingStrategy?? {
        switch s.lowercased() {
        case "vad": return .some(.vad)
        case "none": return .some(nil)        // explicitly no chunking
        default: return nil                   // invalid
        }
    }

    private func walkWAVs(at path: String) throws -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            throw ValidationError("not found: \(path)")
        }
        var out: [URL] = []
        if isDir.boolValue {
            if let walker = fm.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil) {
                for case let f as URL in walker where f.pathExtension.lowercased() == "wav" {
                    out.append(f)
                }
            }
        } else if path.lowercased().hasSuffix(".wav") {
            out.append(URL(fileURLWithPath: path))
        }
        return out.sorted { $0.path < $1.path }
    }

    private func audioDuration(_ url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let secs = Double(file.length) / file.fileFormat.sampleRate
        return secs.isFinite && secs > 0 ? secs : nil
    }

    private func bucketFor(seconds: Double) -> String {
        switch seconds {
        case ..<45:   return "030s"
        case ..<90:   return "060s"
        case ..<210:  return "120s"
        default:      return "300s"
        }
    }

    private func bucketOrder(_ a: String, _ b: String) -> Bool {
        let order = ["030s": 0, "060s": 1, "120s": 2, "300s": 3]
        return (order[a] ?? 99) < (order[b] ?? 99)
    }

    private func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace }).count
    }
}

private extension Array where Element == Double {
    var avg: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
}

private func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
private func secs(_ x: Double) -> String { String(format: "%.2fs", x) }
private func f(_ x: Double, _ frac: Int) -> String { String(format: "%.\(frac)f", x) }
private func escape(_ s: String) -> String {
    if s.contains(",") || s.contains("\"") || s.contains("\n") {
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return s
}

private func stderr(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8) ?? Data())
}
