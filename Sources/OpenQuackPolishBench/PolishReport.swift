import Foundation
import OpenQuackPlatform

public enum PolishReport {
    public static func writeJSONL(_ results: [PolishModelResult], to url: URL) throws {
        var out = ""
        let enc = JSONEncoder()
        enc.outputFormatting = []
        for r in results {
            for c in r.perCase {
                let row = OutputRow(
                    model: r.model,
                    case_id: c.caseID,
                    category: c.category,
                    language: c.language,
                    app_context: c.appContext,
                    raw: c.raw,
                    polished: c.polished,
                    total_s: c.totalSeconds,
                    prompt_eval_s: c.promptEvalSeconds,
                    eval_s: c.evalSeconds,
                    eval_tokens: c.evalTokens,
                    filler_removal: c.scores.fillerRemoval,
                    punctuation: c.scores.punctuationComplete,
                    length_ratio: c.scores.lengthRatio,
                    must_contain: c.scores.mustContainHits,
                    must_not_contain: c.scores.mustNotContainHits,
                    edit_distance: c.scores.editDistance,
                    ref_min_distance: c.scores.referenceMinDistance,
                    used_delta_mb: c.memDelta.map { Double($0.usedDeltaBytes) / 1_048_576.0 },
                    compressed_delta_mb: c.memDelta.map { Double($0.compressedDeltaBytes) / 1_048_576.0 },
                    pageins_delta: c.memDelta.map { Int($0.pageinsDelta) } ?? 0,
                    pageouts_delta: c.memDelta.map { Int($0.pageoutsDelta) } ?? 0,
                    error: c.error
                )
                let data = try enc.encode(row)
                out.append(String(data: data, encoding: .utf8)!)
                out.append("\n")
            }
        }
        try out.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func writeCSV(_ results: [PolishModelResult], to url: URL) throws {
        var lines = ["model,case_id,category,language,app_context,total_s,prompt_eval_s,eval_s,eval_tokens,filler_removal,punctuation,length_ratio,must_contain,must_not_contain,edit_distance,ref_min_distance,used_delta_mb,compressed_delta_mb,pageins_delta,error"]
        for r in results {
            for c in r.perCase {
                let row = [
                    r.model, c.caseID, c.category, c.language, c.appContext ?? "",
                    f(c.totalSeconds, 3), f(c.promptEvalSeconds, 3), f(c.evalSeconds, 3),
                    String(c.evalTokens),
                    optf(c.scores.fillerRemoval, 3),
                    f(c.scores.punctuationComplete, 1),
                    f(c.scores.lengthRatio, 2),
                    f(c.scores.mustContainHits, 2),
                    f(c.scores.mustNotContainHits, 2),
                    String(c.scores.editDistance),
                    c.scores.referenceMinDistance == Int.max ? "" : String(c.scores.referenceMinDistance),
                    optf(c.memDelta.map { Double($0.usedDeltaBytes) / 1_048_576.0 }, 1),
                    optf(c.memDelta.map { Double($0.compressedDeltaBytes) / 1_048_576.0 }, 1),
                    c.memDelta.map { String($0.pageinsDelta) } ?? "",
                    csvEscape(c.error ?? "")
                ].map(csvEscape).joined(separator: ",")
                lines.append(row)
            }
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    public static func writeMarkdown(_ results: [PolishModelResult], host: HostInfo, to url: URL) throws {
        var s = "# OpenQuack polish bench — \(host.hostTag)\n\n"
        s += "**Host:** \(host.chip), \(String(format: "%.0f", host.memoryGB)) GB, \(host.macOSVersion)\n\n"
        s += "**Date:** \(Date())\n\n"
        s += "_Auto micro-metrics only — judge scores are added by `bench/judge.py`._\n\n"

        s += "## Aggregate (per model)\n\n"
        s += "| Model | Warm | Mean wall | P95 wall | Tokens/s | ΔUsed peak | ΔCompressed peak | Peak RSS | Cases |\n"
        s += "|---|---:|---:|---:|---:|---:|---:|---:|---:|\n"
        for r in results {
            let walls = r.perCase.compactMap { $0.error == nil ? $0.totalSeconds : nil }
            let mean = walls.isEmpty ? 0 : walls.reduce(0,+) / Double(walls.count)
            let p95  = percentile(walls.sorted(), 0.95)
            let tps  = tokensPerSec(r.perCase)
            s += "| `\(r.model)` | \(fmt(r.warmSeconds, 1))s | \(fmt(mean, 2))s | \(fmt(p95, 2))s | \(fmt(tps, 0)) | \(mb(r.peakUsedDeltaBytes)) | \(mb(r.peakCompressedDeltaBytes)) | \(mb(r.peakResidentBytes)) | \(walls.count)/\(r.perCase.count) |\n"
        }

        s += "\n## Per-category quality (means; nil cases omitted)\n\n"
        for cat in PolishCase.Category.allCases {
            s += "\n### \(cat.rawValue)\n\n"
            s += "| Model | Filler↑ | Punct↑ | LenRatio | MustContain↑ | MustNotContain↑ | RefMinDist↓ |\n"
            s += "|---|---:|---:|---:|---:|---:|---:|\n"
            for r in results {
                let cs = r.perCase.filter { $0.category == cat.rawValue && $0.error == nil }
                if cs.isEmpty { continue }
                let filler = meanIgnoreNil(cs.map { $0.scores.fillerRemoval })
                let punct  = mean(cs.map { $0.scores.punctuationComplete })
                let lr     = mean(cs.map { $0.scores.lengthRatio })
                let mc     = mean(cs.map { $0.scores.mustContainHits })
                let mnc    = mean(cs.map { $0.scores.mustNotContainHits })
                let rmd    = mean(cs.map { Double($0.scores.referenceMinDistance) })
                s += "| `\(r.model)` | \(optfmt(filler, 2)) | \(fmt(punct, 2)) | \(fmt(lr, 2)) | \(fmt(mc, 2)) | \(fmt(mnc, 2)) | \(fmt(rmd, 1)) |\n"
            }
        }

        s += "\n## Per-case detail\n\n"
        for r in results {
            s += "\n### `\(r.model)`\n\n"
            s += "| Case | Wall | Length | Filler | MustHit | MustMiss | Polished |\n"
            s += "|---|---:|---:|---:|---:|---:|---|\n"
            for c in r.perCase {
                let preview = c.polished
                    .prefix(60)
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "|", with: "\\|")
                s += "| \(c.caseID) | \(fmt(c.totalSeconds, 2))s | \(fmt(c.scores.lengthRatio, 2)) | \(optfmt(c.scores.fillerRemoval, 2)) | \(fmt(c.scores.mustContainHits, 2)) | \(fmt(c.scores.mustNotContainHits, 2)) | \(preview) |\n"
            }
        }
        try s.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - helpers

    private struct OutputRow: Encodable {
        let model: String
        let case_id: String
        let category: String
        let language: String
        let app_context: String?
        let raw: String
        let polished: String
        let total_s: Double
        let prompt_eval_s: Double
        let eval_s: Double
        let eval_tokens: Int
        let filler_removal: Double?
        let punctuation: Double
        let length_ratio: Double
        let must_contain: Double
        let must_not_contain: Double
        let edit_distance: Int
        let ref_min_distance: Int
        let used_delta_mb: Double?
        let compressed_delta_mb: Double?
        let pageins_delta: Int
        let pageouts_delta: Int
        let error: String?
    }
}

private func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let idx = Int(Double(sorted.count - 1) * p)
    return sorted[idx]
}

private func tokensPerSec(_ cases: [PolishCaseResult]) -> Double {
    let totalTokens = cases.reduce(0) { $0 + $1.evalTokens }
    let totalEval   = cases.reduce(0.0) { $0 + $1.evalSeconds }
    return totalEval > 0 ? Double(totalTokens) / totalEval : 0
}

private func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0,+) / Double(xs.count) }

private func meanIgnoreNil(_ xs: [Double?]) -> Double? {
    let ys = xs.compactMap { $0 }
    return ys.isEmpty ? nil : ys.reduce(0,+) / Double(ys.count)
}

private func mb(_ bytes: Int64) -> String {
    String(format: "%.0f MB", Double(bytes) / 1_048_576.0)
}

private func fmt(_ x: Double, _ frac: Int) -> String { String(format: "%.\(frac)f", x) }

private func optfmt(_ x: Double?, _ frac: Int) -> String {
    guard let x else { return "—" }
    return fmt(x, frac)
}

private func f(_ x: Double, _ frac: Int) -> String { String(format: "%.\(frac)f", x) }
private func optf(_ x: Double?, _ frac: Int) -> String {
    guard let x else { return "" }
    return f(x, frac)
}

private func csvEscape(_ s: String) -> String {
    if s.contains(",") || s.contains("\"") || s.contains("\n") {
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return s
}
