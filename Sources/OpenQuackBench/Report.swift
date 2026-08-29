import Foundation
import OpenQuackKit

public enum Report {
    public static func writeMarkdown(_ results: [BenchResult], host: HostInfo, to url: URL) throws {
        var md = "# OpenQuack bench — \(host.hostTag)\n\n"
        md += "**Host:** \(host.chip)"
        if let g = host.gpuCoreCount { md += ", \(g)-core GPU" }
        md += ", \(String(format: "%.0f", host.memoryGB)) GB unified, \(host.macOSVersion)\n\n"

        md += "## Aggregate (per engine × model)\n\n"
        md += "| Engine | Model | WER | CER | RTF | Wall (avg) | Cold start | Peak RSS | Clips | Failures |\n"
        md += "|---|---|---:|---:|---:|---:|---:|---:|---:|---|\n"
        let sorted = results.sorted {
            ($0.engineName, $0.modelID) < ($1.engineName, $1.modelID)
        }
        for r in sorted {
            if let err = r.error, r.perClip.isEmpty {
                md += "| \(r.engineName) | `\(r.modelID)` | _failed: \(err)_ | | | | | | 0 | — |\n"
                continue
            }
            let fc = r.failureCounts
            let failStr = failureSummary(fc, total: r.perClip.count)
            md += "| \(r.engineName) | `\(r.modelID)` | "
            md += "\(pct(r.meanWER)) | \(pct(r.meanCER)) | "
            md += "\(num(r.meanRTF, 2))× | "
            md += "\(num(r.meanWallSeconds, 2)) s | "
            md += "\(num(r.coldStartSeconds, 2)) s | "
            md += "\(rss(r.peakRSSBytes)) | "
            md += "\(r.perClip.count) | \(failStr) |\n"
        }
        md += "\n_RTF < 1× = faster than real-time. WER/CER lower is better. RSS = peak resident memory._\n"
        md += "_Failures: PH=placeholder hallucination, ST=silent translation, G=garbled (WER>200%)._\n"

        // Per-clip detail (handy when something looks weird)
        md += "\n## Per-clip detail\n\n"
        for r in sorted {
            md += "\n### \(r.engineName) / `\(r.modelID)`\n\n"
            if r.perClip.isEmpty {
                md += "_no clips transcribed_\n"
                continue
            }
            md += "| Clip | Audio | Wall | RTF | WER | CER | Lang | Mode | Preview |\n"
            md += "|---|---:|---:|---:|---:|---:|---|---|---|\n"
            for c in r.perClip {
                let r_ = c.audioSeconds > 0 ? c.wallSeconds / c.audioSeconds : 0
                let preview = c.textPreview.replacingOccurrences(of: "|", with: "\\|")
                let modeCell = c.failureMode == .ok ? "✓" : "**\(c.failureMode.rawValue)**"
                md += "| \(c.clipID) | \(num(c.audioSeconds, 2)) s | \(num(c.wallSeconds, 2)) s | "
                md += "\(num(r_, 2))× | \(pct(c.wer)) | \(pct(c.cer)) | "
                md += "\(c.detectedLanguage ?? "-") | \(modeCell) | \(preview) |\n"
            }
        }
        try md.data(using: .utf8)?.write(to: url)
    }

    public static func writeCSV(_ results: [BenchResult], to url: URL) throws {
        var csv = "engine,model,clip_id,audio_seconds,wall_seconds,rtf,wer,cer,ttft_seconds,detected_language,failure_mode,output_script_match,halluc_rate_raw,text_preview\n"
        for r in results {
            for c in r.perClip {
                let rtfVal = c.audioSeconds > 0 ? c.wallSeconds / c.audioSeconds : 0
                let ttftStr = c.ttft.map { String(format: "%.4f", $0) } ?? ""
                let preview = csvQuote(c.textPreview)
                csv += "\(r.engineName),\(r.modelID),\(c.clipID),"
                csv += "\(c.audioSeconds),\(c.wallSeconds),\(rtfVal),"
                csv += "\(c.wer),\(c.cer),\(ttftStr),"
                csv += "\(c.detectedLanguage ?? ""),"
                csv += "\(c.failureMode.rawValue),\(c.outputScriptMatch),\(String(format: "%.4f", c.hallucRateRaw)),"
                csv += "\(preview)\n"
            }
        }
        try csv.data(using: .utf8)?.write(to: url)
    }

    public static func writeHostJSON(host: HostInfo, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(host)
        try data.write(to: url)
    }

    // ── formatting helpers ────────────────────────────────────────────────

    private static func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
    private static func num(_ x: Double, _ f: Int) -> String { String(format: "%.\(f)f", x) }
    private static func rss(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        return mb < 1024 ? String(format: "%.0f MB", mb) : String(format: "%.2f GB", mb / 1024)
    }
    private static func csvQuote(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func failureSummary(
        _ fc: (ok: Int, placeholder: Int, silentTranslation: Int, garbled: Int),
        total: Int
    ) -> String {
        guard fc.placeholder > 0 || fc.silentTranslation > 0 || fc.garbled > 0 else {
            return "all ok"
        }
        var parts: [String] = []
        if fc.placeholder > 0       { parts.append("PH:\(fc.placeholder)") }
        if fc.silentTranslation > 0 { parts.append("ST:\(fc.silentTranslation)") }
        if fc.garbled > 0           { parts.append("G:\(fc.garbled)") }
        return parts.joined(separator: " ")
    }
}
