import ArgumentParser
import AVFoundation
import Foundation
import OpenQuackPlatform
import OpenQuackStreaming
import WhisperKit

@main
struct OpenQuackStreamBenchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "openquack-stream-bench",
        abstract: "SPEC-012: long-audio post-stop wait — offline vs streaming.",
        version: OpenQuackPlatform.version
    )

    @Option(name: .customLong("model"),
            help: "WhisperKit model id (e.g. tiny, small, medium).")
    var model: String = "medium"

    @Option(name: .customLong("clips"),
            help: "Directory walked recursively for *.wav (with paired *.txt). Default: bench/corpus/long.")
    var clips: String = "bench/corpus/long"

    @Option(name: .customLong("mode"),
            help: "offline | streaming | both. Default both runs both per clip for direct A/B.")
    var mode: String = "both"

    @Option(name: .customLong("language"),
            help: "Force language code (en, zh, …), or 'auto' for engine auto-detect. Default: en for the long corpus.")
    var language: String? = "en"

    /// `--language auto` (or empty) → nil, so the engine's auto-detect path
    /// (SPEC-021 detect-then-lock) is exercised. Any other value is forced.
    private var resolvedLanguage: String? {
        guard let language else { return nil }
        let l = language.trimmingCharacters(in: .whitespaces).lowercased()
        return (l == "auto" || l.isEmpty) ? nil : language
    }

    @Option(name: .customLong("chunking"),
            help: "Offline only: vad | none. Default vad. (Streaming always silence-cuts.)")
    var chunking: String = "vad"

    @Option(name: .customLong("target-chunk"),
            help: "Streaming target chunk seconds. Default 20 (matches SPEC-012).")
    var targetChunk: Double = 20

    @Option(name: .customLong("max-chunk"),
            help: "Streaming max chunk seconds. Default 28.")
    var maxChunk: Double = 28

    @Flag(name: .customLong("smoke"),
          help: "Streaming mode without real-time pacing — fastest correctness check; not a latency measurement.")
    var smoke: Bool = false

    @Option(name: .customLong("out"),
            help: "Output directory. Default: bench/out/stream/<host-tag>.")
    var out: String?

    @Flag(name: .customLong("verbose"))
    var verbose: Bool = false

    func run() async throws {
        let host = HostInfo.detect()
        let outDir = URL(fileURLWithPath: out ?? "bench/out/stream/\(host.hostTag)")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let runOffline: Bool
        let runStreaming: Bool
        switch mode.lowercased() {
        case "offline":   (runOffline, runStreaming) = (true, false)
        case "streaming": (runOffline, runStreaming) = (false, true)
        case "both":      (runOffline, runStreaming) = (true, true)
        default: throw ValidationError("--mode must be offline | streaming | both")
        }
        guard let chunkStrategy = parseChunking(chunking) else {
            throw ValidationError("--chunking must be vad or none")
        }

        let clipURLs = try walkWAVs(at: clips)
        guard !clipURLs.isEmpty else {
            throw ValidationError("no *.wav under \(clips)")
        }
        stderr("◇ clips: \(clipURLs.count) under \(clips)")
        stderr("◇ modes: \(runOffline ? "offline " : "")\(runStreaming ? (smoke ? "streaming(smoke)" : "streaming") : "")")

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

        // Warm-up: a single short call so the first measured clip isn't
        // paying first-call cost (graph compile, weight prefetch).
        if let first = clipURLs.first {
            stderr("◇ warm-up on \(first.lastPathComponent)…")
            _ = try? await transcribeOffline(pipe: pipe, url: first,
                                              language: resolvedLanguage,
                                              chunkStrategy: chunkStrategy)
            stderr("  ✓ warm")
        }

        var rows: [Row] = []
        for (i, url) in clipURLs.enumerated() {
            let refURL = url.deletingPathExtension().appendingPathExtension("txt")
            let reference = (try? String(contentsOf: refURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let audioSecs = audioDuration(url) ?? 0

            var off: ModeResult?
            var stm: ModeResult?

            if runOffline {
                let r = try await transcribeOffline(pipe: pipe, url: url,
                                                     language: resolvedLanguage,
                                                     chunkStrategy: chunkStrategy)
                off = ModeResult(text: r.text, postStopWait: r.wall, totalWall: r.wall, chunkCount: nil, ttft: r.ttft)
            }

            if runStreaming {
                let r = try await transcribeStreaming(pipe: pipe, url: url,
                                                       language: resolvedLanguage,
                                                       paced: !smoke)
                stm = ModeResult(text: r.text, postStopWait: r.postStopWait, totalWall: r.totalWall, chunkCount: r.chunkCount, ttft: nil)
            }

            let row = Row(
                clip: url.lastPathComponent,
                bucket: bucketFor(seconds: audioSecs),
                audioSeconds: audioSecs,
                reference: reference,
                offline: off,
                streaming: stm
            )
            rows.append(row)

            if verbose {
                let offDesc = off.map { String(format: "off wall %.2fs wer %.1f%%", $0.postStopWait, werOf(reference: reference, hyp: $0.text) * 100) } ?? "-"
                let stmDesc = stm.map { String(format: "stm post-stop %.2fs wer %.1f%% chunks %d", $0.postStopWait, werOf(reference: reference, hyp: $0.text) * 100, $0.chunkCount ?? -1) } ?? "-"
                stderr("  [\(i+1)/\(clipURLs.count)] \(url.lastPathComponent)  audio \(String(format: "%.1f", audioSecs))s  \(offDesc)  \(stmDesc)")
            }
        }

        try writeReport(rows: rows, host: host, model: model,
                        runOffline: runOffline, runStreaming: runStreaming, smoke: smoke,
                        targetChunk: targetChunk, maxChunk: maxChunk, to: outDir)
        print("\n✓ \(outDir.path)/report.md")
        print("  \(outDir.path)/report.csv")
        printSanity(rows: rows, runOffline: runOffline, runStreaming: runStreaming)
    }

    // MARK: - offline

    private struct OfflineCall {
        let text: String
        let wall: Double
        let ttft: Double?
    }

    private func transcribeOffline(pipe: WhisperKit, url: URL, language: String?, chunkStrategy: ChunkingStrategy?) async throws -> OfflineCall {
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
        return OfflineCall(text: text, wall: wall, ttft: ttft)
    }

    // MARK: - streaming

    private struct StreamCall {
        let text: String
        let postStopWait: Double
        let totalWall: Double
        let chunkCount: Int
    }

    /// Real-time-paced streaming run. Loads the WAV as 16 kHz mono float
    /// samples, feeds it to a `StreamingTranscriber` in 100 ms ticks pinned
    /// to absolute target wall times (no per-tick `sleep(100ms)` drift), then
    /// calls `finish()` and measures *only* that span as the post-stop wait.
    private func transcribeStreaming(pipe: WhisperKit, url: URL, language: String?, paced: Bool) async throws -> StreamCall {
        let buffer = try AudioProcessor.loadAudio(
            fromPath: url.path,
            channelMode: .sumChannels(nil),
            startTime: nil,
            endTime: nil,
            maxReadFrameSize: nil
        )
        let samples = AudioProcessor.convertBufferToArray(buffer: buffer)
        let sampleRate = 16000
        let tickSamples = sampleRate / 10        // 100 ms
        let tickSeconds: Double = 0.1

        let cfg = StreamingTranscriber.Config(
            streamingThreshold: 0,                // bench drives every clip; gate is the caller's job
            targetChunkSeconds: targetChunk,
            maxChunkSeconds: maxChunk
        )
        let streamer = StreamingTranscriber(pipe: pipe, config: cfg)
        await streamer.begin(language: resolvedLanguage, customWords: nil)

        let pacingStart = Date()
        var idx = 0
        while idx < samples.count {
            let end = min(idx + tickSamples, samples.count)
            let slice = Array(samples[idx..<end])
            await streamer.appendFrames(slice, sampleRate: Double(sampleRate))
            idx = end

            if paced {
                let target = Double(idx) / Double(sampleRate)
                let actual = Date().timeIntervalSince(pacingStart)
                let delay = target - actual
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            _ = tickSeconds  // referenced for clarity; precision target is per-tick
        }

        let stopT = Date()
        let result = try await streamer.finish()
        let postStop = Date().timeIntervalSince(stopT)
        let totalWall = Date().timeIntervalSince(pacingStart)
        return StreamCall(
            text: result.text,
            postStopWait: postStop,
            totalWall: totalWall,
            chunkCount: result.chunkCount
        )
    }

    // MARK: - reporting

    private struct ModeResult {
        let text: String
        let postStopWait: Double
        let totalWall: Double
        let chunkCount: Int?
        let ttft: Double?
    }

    private struct Row {
        let clip: String
        let bucket: String
        let audioSeconds: Double
        let reference: String
        let offline: ModeResult?
        let streaming: ModeResult?
    }

    private func writeReport(rows: [Row], host: HostInfo, model: String,
                              runOffline: Bool, runStreaming: Bool, smoke: Bool,
                              targetChunk: Double, maxChunk: Double, to dir: URL) throws {
        var md = "# Long-audio post-stop wait — \(host.hostTag) / \(model)\n\n"
        md += "**Date:** \(Date())\n"
        md += "**Modes:** \(runOffline ? "offline " : "")\(runStreaming ? (smoke ? "streaming(smoke, no pacing)" : "streaming") : "")\n"
        if runStreaming {
            md += "**Streaming:** target \(targetChunk)s · max \(maxChunk)s\n"
        }
        md += "**Clips:** \(rows.count)\n\n"
        md += "Streaming targets per SPEC-012:\n"
        md += "30s ≤ 1.5s · 60s ≤ 1.5s · 120s ≤ 2.0s · 300s ≤ 2.5s post-stop wait,\n"
        md += "WER delta vs offline within ±0.3pp.\n\n"

        let buckets = Set(rows.map(\.bucket)).sorted(by: bucketOrder)
        md += "## By length bucket\n\n"
        var header = "| Bucket | n | mean audio |"
        var sep    = "|---|---:|---:|"
        if runOffline   { header += " off wall | off RTF | off WER |"; sep += "---:|---:|---:|" }
        if runStreaming {
            header += " stm post-stop | stm chunks | stm WER |"
            sep    += "---:|---:|---:|"
            if runOffline { header += " ΔWER (stm-off) | speedup |"; sep += "---:|---:|" }
        }
        md += header + "\n" + sep + "\n"
        for b in buckets {
            let bs = rows.filter { $0.bucket == b }
            let aud = bs.map(\.audioSeconds).avg
            md += "| \(b) | \(bs.count) | \(secs(aud)) |"
            if runOffline {
                let wall = bs.compactMap(\.offline).map(\.postStopWait).avg
                let rtf  = bs.compactMap { $0.offline.map { $0.postStopWait / max($0.postStopWait > 0 ? $0.postStopWait : 1, 1) } } .avg
                _ = rtf
                let rtfReal = bs.compactMap { row -> Double? in
                    guard let off = row.offline else { return nil }
                    return row.audioSeconds > 0 ? off.postStopWait / row.audioSeconds : nil
                }.avg
                let wer = bs.compactMap { row -> Double? in
                    guard let off = row.offline else { return nil }
                    return werOf(reference: row.reference, hyp: off.text)
                }.avg
                md += " \(secs(wall)) | \(f(rtfReal, 2)) | \(pct(wer)) |"
            }
            if runStreaming {
                let post = bs.compactMap(\.streaming).map(\.postStopWait).avg
                let chunks = bs.compactMap { $0.streaming?.chunkCount }.map(Double.init).avg
                let wer = bs.compactMap { row -> Double? in
                    guard let stm = row.streaming else { return nil }
                    return werOf(reference: row.reference, hyp: stm.text)
                }.avg
                md += " \(secs(post)) | \(f(chunks, 1)) | \(pct(wer)) |"
                if runOffline {
                    let offWER = bs.compactMap { row -> Double? in
                        guard let off = row.offline else { return nil }
                        return werOf(reference: row.reference, hyp: off.text)
                    }.avg
                    let dWER = wer - offWER
                    let off = bs.compactMap(\.offline).map(\.postStopWait).avg
                    let speed = post > 0 ? off / post : 0
                    md += " \(ppDelta(dWER)) | \(f(speed, 1))× |"
                }
            }
            md += "\n"
        }
        md += "\n_Speedup_ = offline post-stop / streaming post-stop. ΔWER positive = streaming worse.\n"

        md += "\n## Per-clip\n\n"
        var hdr2 = "| Clip | bucket | audio (s) |"
        var sep2 = "|---|---|---:|"
        if runOffline   { hdr2 += " off wall | off WER |"; sep2 += "---:|---:|" }
        if runStreaming { hdr2 += " stm post-stop | stm chunks | stm WER | stm total |"; sep2 += "---:|---:|---:|---:|" }
        md += hdr2 + "\n" + sep2 + "\n"
        for r in rows.sorted(by: { ($0.bucket, $0.clip) < ($1.bucket, $1.clip) }) {
            md += "| \(r.clip) | \(r.bucket) | \(f(r.audioSeconds, 1)) |"
            if runOffline, let off = r.offline {
                let wer = werOf(reference: r.reference, hyp: off.text)
                md += " \(f(off.postStopWait, 2)) | \(pct(wer)) |"
            } else if runOffline {
                md += " — | — |"
            }
            if runStreaming, let stm = r.streaming {
                let wer = werOf(reference: r.reference, hyp: stm.text)
                md += " \(f(stm.postStopWait, 2)) | \(stm.chunkCount.map(String.init) ?? "—") | \(pct(wer)) | \(f(stm.totalWall, 1)) |"
            } else if runStreaming {
                md += " — | — | — | — |"
            }
            md += "\n"
        }

        try md.write(to: dir.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)

        var csv = "clip,bucket,audio_s,ref_words"
        if runOffline   { csv += ",off_wall_s,off_wer,off_text" }
        if runStreaming { csv += ",stm_post_stop_s,stm_total_s,stm_chunks,stm_wer,stm_text" }
        csv += ",reference\n"
        for r in rows {
            csv += [r.clip, r.bucket, f(r.audioSeconds, 3), String(wordCount(r.reference))]
                .joined(separator: ",")
            if runOffline {
                let off = r.offline
                csv += "," + (off.map { f($0.postStopWait, 3) } ?? "")
                csv += "," + (off.map { f(werOf(reference: r.reference, hyp: $0.text), 4) } ?? "")
                csv += "," + (off.map { escape($0.text) } ?? "")
            }
            if runStreaming {
                let stm = r.streaming
                csv += "," + (stm.map { f($0.postStopWait, 3) } ?? "")
                csv += "," + (stm.map { f($0.totalWall, 3) } ?? "")
                csv += "," + (stm.flatMap { $0.chunkCount.map(String.init) } ?? "")
                csv += "," + (stm.map { f(werOf(reference: r.reference, hyp: $0.text), 4) } ?? "")
                csv += "," + (stm.map { escape($0.text) } ?? "")
            }
            csv += "," + escape(r.reference) + "\n"
        }
        try csv.write(to: dir.appendingPathComponent("report.csv"), atomically: true, encoding: .utf8)
    }

    private func printSanity(rows: [Row], runOffline: Bool, runStreaming: Bool) {
        if runOffline {
            let bad = rows.compactMap { row -> String? in
                guard let off = row.offline else { return nil }
                let ratio = Double(wordCount(off.text)) / max(Double(wordCount(row.reference)), 1)
                return ratio < 0.7 ? row.clip : nil
            }
            if !bad.isEmpty {
                stderr("\n⚠ offline truncation suspected on: \(bad.joined(separator: ", "))")
            }
        }
        if runStreaming {
            let bad = rows.compactMap { row -> String? in
                guard let stm = row.streaming else { return nil }
                let ratio = Double(wordCount(stm.text)) / max(Double(wordCount(row.reference)), 1)
                return ratio < 0.7 ? row.clip : nil
            }
            if !bad.isEmpty {
                stderr("\n⚠ streaming output truncation on: \(bad.joined(separator: ", "))")
            }
        }
        if runOffline && runStreaming {
            let highWERdelta = rows.compactMap { row -> (String, Double)? in
                guard let off = row.offline, let stm = row.streaming else { return nil }
                let d = werOf(reference: row.reference, hyp: stm.text) - werOf(reference: row.reference, hyp: off.text)
                return abs(d) > 0.003 ? (row.clip, d) : nil
            }
            if highWERdelta.isEmpty {
                stderr("\n✓ streaming WER within ±0.3pp of offline on every clip")
            } else {
                stderr("\n⚠ streaming WER delta > 0.3pp on:")
                for (c, d) in highWERdelta {
                    stderr(String(format: "    %@: %@%.2f pp", c, d > 0 ? "+" : "", d * 100))
                }
            }
        }
        if runStreaming {
            // SPEC-012 post-stop-wait gates per length bucket.
            let gates: [String: Double] = [
                "030s": 1.5, "060s": 1.5, "120s": 2.0, "300s": 2.5,
            ]
            var failed: [(String, Double, Double)] = []
            for row in rows {
                guard let stm = row.streaming, let gate = gates[row.bucket] else { continue }
                if stm.postStopWait > gate {
                    failed.append((row.clip, stm.postStopWait, gate))
                }
            }
            if failed.isEmpty {
                stderr("\n✓ post-stop wait within SPEC-012 gates on every clip")
            } else {
                stderr("\n⚠ post-stop wait over SPEC-012 gate on:")
                for (c, w, g) in failed {
                    stderr(String(format: "    %@: %.2fs (gate %.1fs)", c, w, g))
                }
            }
        }
    }

    // MARK: - helpers

    private func parseChunking(_ s: String) -> ChunkingStrategy?? {
        switch s.lowercased() {
        case "vad": return .some(.vad)
        case "none": return .some(nil)
        default: return nil
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

private func werOf(reference: String, hyp: String) -> Double {
    WER.compute(reference: reference, hypothesis: hyp)
}

private func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
private func secs(_ x: Double) -> String { String(format: "%.2fs", x) }
private func ppDelta(_ d: Double) -> String {
    let sign = d > 0 ? "+" : (d < 0 ? "" : "±")
    return "\(sign)\(String(format: "%.2f", d * 100)) pp"
}
private func f(_ x: Double, _ frac: Int) -> String { String(format: "%.\(frac)f", x) }
private func escape(_ s: String) -> String {
    if s.contains(",") || s.contains("\"") || s.contains("\n") {
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return s
}

private func wordCount(_ s: String) -> Int {
    s.split(whereSeparator: { $0.isWhitespace }).count
}

private func stderr(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8) ?? Data())
}
