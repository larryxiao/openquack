import Foundation

/// Auto micro-metrics scored per (case, polished output). Ranges 0..1 unless
/// noted; nil when the metric isn't applicable for the case.
public struct PolishScores: Sendable {
    public let fillerRemoval:       Double?  // 1.0 = all fillers gone, 0.0 = none removed; nil if raw had no fillers
    public let punctuationComplete: Double   // 0..1: end-of-text terminal punct present (binary at v1)
    public let lengthRatio:         Double   // outputWords / inputWords (≤ 1 ideal; > 1.2 = bloat)
    public let mustContainHits:     Double   // fraction of must_contain substrings present
    public let mustNotContainHits:  Double   // fraction of must_not_contain substrings ABSENT (1.0 = none present, good)
    public let editDistance:        Int      // raw vs polished (Levenshtein on chars). For idempotency cases, lower is better.
    public let referenceMinDistance: Int     // min char-level Levenshtein to any reference
}

public enum PolishMetrics {
    /// English-language fillers we consider "removable". Conservative — does
    /// not include "like" / "you know" / "I mean" by default since those have
    /// legitimate meaning. The corpus's `must_not_contain` field is the
    /// authoritative per-case spec.
    static let englishFillers: [String] = [
        "um", "umm", "ummm", "uh", "uhh", "uhhh", "er", "erm", "ah",
        "hmm", "hmmm", "uhhuh", "uh-huh"
    ]

    /// Multilingual filler set used when `language` ≠ "en".
    static let multilingualFillers: [String: [String]] = [
        "zh": ["嗯", "那个", "就是", "然后", "对", "呃"],
        "ja": ["えーと", "あのー", "あの", "えー", "うーん"],
        "es": ["este", "eh", "pues", "o sea"],
        "fr": ["euh", "ben", "quoi", "en fait"],
        "de": ["äh", "ähm", "halt", "also"],
    ]

    public static func score(case c: PolishCase, output: String) -> PolishScores {
        let fillerScore = fillerRemovalScore(raw: c.raw, polished: output, language: c.language)
        let punct = punctuationScore(output, language: c.language)
        let lr = lengthRatio(raw: c.raw, polished: output)
        let mcHits = substringFraction(output, c.mustContain, present: true)
        let mnHits = substringFraction(output, c.mustNotContain, present: false)
        let ed = levenshtein(c.raw, output)
        let refMin = c.references
            .map { levenshtein($0, output) }
            .min() ?? Int.max

        return PolishScores(
            fillerRemoval: fillerScore,
            punctuationComplete: punct,
            lengthRatio: lr,
            mustContainHits: mcHits,
            mustNotContainHits: mnHits,
            editDistance: ed,
            referenceMinDistance: refMin
        )
    }

    // MARK: - sub-scores

    static func fillerRemovalScore(raw: String, polished: String, language: String) -> Double? {
        let fillers = (language == "en" ? englishFillers : multilingualFillers[language]) ?? englishFillers
        let rawCount    = countOccurrencesCaseInsensitive(of: fillers, in: raw)
        let polishCount = countOccurrencesCaseInsensitive(of: fillers, in: polished)
        guard rawCount > 0 else { return nil }
        let removed = max(0, rawCount - polishCount)
        return Double(removed) / Double(rawCount)
    }

    static func punctuationScore(_ s: String, language: String) -> Double {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return 0 }
        let enders: Set<Character> = [".", "!", "?", "。", "！", "？", "…", "•", "-", ":"]
        return enders.contains(last) ? 1 : 0
    }

    static func lengthRatio(raw: String, polished: String) -> Double {
        let r = max(1, PolishPrompts.estimateWords(raw))
        let p = PolishPrompts.estimateWords(polished)
        return Double(p) / Double(r)
    }

    static func substringFraction(_ haystack: String, _ needles: [String], present: Bool) -> Double {
        guard !needles.isEmpty else { return 1.0 }
        let lower = haystack.lowercased()
        let hits = needles.filter { lower.contains($0.lowercased()) }.count
        let matches = present ? hits : (needles.count - hits)
        return Double(matches) / Double(needles.count)
    }

    static func countOccurrencesCaseInsensitive(of needles: [String], in haystack: String) -> Int {
        // Word-boundary match for ASCII fillers; substring match for non-ASCII (CJK / accented).
        var count = 0
        let lower = haystack.lowercased()
        for n in needles {
            if n.allSatisfy({ $0.isASCII }) {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: n.lowercased()))\\b"
                if let rx = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(lower.startIndex..., in: lower)
                    count += rx.numberOfMatches(in: lower, range: range)
                }
            } else {
                var search = lower[...]
                while let r = search.range(of: n.lowercased()) {
                    count += 1
                    search = search[r.upperBound...]
                }
            }
        }
        return count
    }

    /// Char-level Levenshtein. Iterative two-row DP. Cheap enough for the
    /// corpus sizes we run (≤ a few hundred chars).
    public static func levenshtein(_ a: String, _ b: String) -> Int {
        let ac = Array(a)
        let bc = Array(b)
        if ac.isEmpty { return bc.count }
        if bc.isEmpty { return ac.count }
        var prev = Array(0...bc.count)
        var curr = Array(repeating: 0, count: bc.count + 1)
        for i in 1...ac.count {
            curr[0] = i
            for j in 1...bc.count {
                let cost = ac[i - 1] == bc[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }
        return prev[bc.count]
    }
}
