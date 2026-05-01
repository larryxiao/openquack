import Foundation
import OpenQuackPlatform

public struct PolishCaseResult: Sendable {
    public let caseID: String
    public let category: String
    public let language: String
    public let appContext: String?
    public let raw: String
    public let polished: String
    public let scores: PolishScores
    public let totalSeconds: Double
    public let promptEvalSeconds: Double  // ≈ TTFT for warm calls
    public let evalSeconds: Double
    public let evalTokens: Int
    public let memDelta: MemoryPressure.Delta?
    public let error: String?
}

public struct PolishModelResult: Sendable {
    public let model: String
    public let warmSeconds: Double
    public let perCase: [PolishCaseResult]
    public let peakResidentBytes: Int64       // process RSS, kept for continuity
    public let peakUsedDeltaBytes: Int64      // unified-memory pressure (the real number)
    public let peakCompressedDeltaBytes: Int64
}

public enum PolishBenchRunner {
    public static func run(
        model: String,
        cases: [PolishCase],
        client: OllamaClient,
        glossary: Glossary?,
        useSurroundingText: Bool,
        verbose: Bool
    ) async -> PolishModelResult {
        stderr("◇ \(model): warming...")
        let warmStart = Date()
        do {
            try await client.warm(model: model)
        } catch {
            stderr("  ✗ warm failed: \(error)")
        }
        let warmSeconds = Date().timeIntervalSince(warmStart)
        stderr("  ✓ warmed in \(fmt(warmSeconds, 2))s")

        let baseline = MemoryPressure.snapshot()
        let rss = RSSSampler(intervalMs: 250)
        rss.start()

        var peakUsedDelta: Int64 = 0
        var peakCompressedDelta: Int64 = 0
        var perCase: [PolishCaseResult] = []

        for (i, c) in cases.enumerated() {
            let before = MemoryPressure.snapshot()
            let t0 = Date()
            do {
                let resp = try await client.chat(
                    model: model,
                    system: PolishPrompt.system(glossary: glossary, appContext: c.appContext),
                    user: PolishPrompt.userMessage(
                        raw: c.raw,
                        appContext: c.appContext,
                        surroundingText: useSurroundingText ? c.surroundingText : nil
                    ),
                    temperature: PolishPrompt.temperature(for: c.raw),
                    numPredict: PolishPrompt.numPredict(for: c.raw)
                )
                let totalWall = Date().timeIntervalSince(t0)
                let after = MemoryPressure.snapshot()
                let delta = (before != nil && after != nil)
                    ? MemoryPressure.delta(from: before!, to: after!)
                    : nil
                if let d = delta {
                    if d.usedDeltaBytes > peakUsedDelta { peakUsedDelta = d.usedDeltaBytes }
                    if d.compressedDeltaBytes > peakCompressedDelta { peakCompressedDelta = d.compressedDeltaBytes }
                }

                let polished = resp.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let scores = PolishMetrics.score(case: c, output: polished)

                perCase.append(PolishCaseResult(
                    caseID: c.id,
                    category: c.category.rawValue,
                    language: c.language,
                    appContext: c.appContext,
                    raw: c.raw,
                    polished: polished,
                    scores: scores,
                    totalSeconds: nsToSec(resp.totalDuration) ?? totalWall,
                    promptEvalSeconds: nsToSec(resp.promptEvalDuration) ?? 0,
                    evalSeconds: nsToSec(resp.evalDuration) ?? 0,
                    evalTokens: resp.evalCount ?? 0,
                    memDelta: delta,
                    error: nil
                ))

                if verbose {
                    let preview = polished.prefix(60).replacingOccurrences(of: "\n", with: " ")
                    stderr("  [\(i+1)/\(cases.count)] \(c.id): \(fmt(totalWall, 2))s — \(preview)")
                }
            } catch {
                let totalWall = Date().timeIntervalSince(t0)
                perCase.append(PolishCaseResult(
                    caseID: c.id,
                    category: c.category.rawValue,
                    language: c.language,
                    appContext: c.appContext,
                    raw: c.raw,
                    polished: "",
                    scores: PolishScores(
                        fillerRemoval: nil, punctuationComplete: 0, lengthRatio: 0,
                        mustContainHits: 0, mustNotContainHits: 0,
                        editDistance: 0, referenceMinDistance: Int.max
                    ),
                    totalSeconds: totalWall,
                    promptEvalSeconds: 0, evalSeconds: 0, evalTokens: 0,
                    memDelta: nil,
                    error: "\(error)"
                ))
                stderr("  [\(i+1)/\(cases.count)] \(c.id): ERROR \(error)")
            }
        }

        let peakRSS = rss.stop()
        _ = baseline  // baseline retained for now in case future deltas want it

        return PolishModelResult(
            model: model,
            warmSeconds: warmSeconds,
            perCase: perCase,
            peakResidentBytes: peakRSS,
            peakUsedDeltaBytes: peakUsedDelta,
            peakCompressedDeltaBytes: peakCompressedDelta
        )
    }
}

private func nsToSec(_ ns: Int64?) -> Double? {
    guard let ns else { return nil }
    return Double(ns) / 1_000_000_000.0
}

private func fmt(_ x: Double, _ frac: Int) -> String {
    String(format: "%.\(frac)f", x)
}
