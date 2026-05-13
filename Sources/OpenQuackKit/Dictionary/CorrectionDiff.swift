import Foundation

/// SPEC-022 §2.3 — Token-level diff of `rawTranscript` vs. `committedText`.
///
/// `committedText` is the user-edited segment (located by the caller via
/// longest-common-prefix against the field's final value — see SPEC-022 §2.2.4),
/// not the entire field. The pure function takes the segment as-is.
///
/// Algorithm: word-by-word positional alignment. SPEC explicitly allows simple
/// alignment over Myers diff at this volume — most paste edits are one or two
/// in-place substitutions, and full LCS would create spurious pairs from
/// insertions / deletions at the segment boundary.
public enum CorrectionDiff {

    /// Stop words: extremely common short tokens whose substitutions are almost
    /// always grammatical noise rather than dictionary-worthy terms. Kept tiny
    /// per SPEC §2.3.
    static let stopWords: Set<String> = [
        "the", "a", "an", "is", "was", "of", "to",
        "for", "in", "on", "and", "or", "but",
        "that", "this",
    ]

    /// Maximum case-insensitive edit distance for a pair to qualify as a
    /// correction. > 3 usually means the user replaced the word entirely
    /// (different intent, not a transcription error) — see SPEC §2.3.
    static let maxEditDistance = 3

    /// Tokenisation boundary: Unicode whitespace + Unicode punctuation. Empty
    /// tokens are dropped so trailing punctuation doesn't shift the alignment.
    private static let tokenSeparators: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.formUnion(.punctuationCharacters)
        return set
    }()

    /// Returns substitution candidates extracted from the aligned token pairs.
    /// Caller decides what to do with them (typically: feed into the store).
    public static func extractCorrections(rawTranscript: String,
                                          committedText: String,
                                          now: Date = Date()) -> [CorrectionCandidate] {
        let rawTokens = tokenize(rawTranscript)
        let userTokens = tokenize(committedText)
        let pairCount = min(rawTokens.count, userTokens.count)
        guard pairCount > 0 else { return [] }

        var out: [CorrectionCandidate] = []
        for i in 0..<pairCount {
            let wrong = rawTokens[i]
            let right = userTokens[i]
            guard accept(wrong: wrong, right: right) else { continue }
            out.append(CorrectionCandidate(wrong: wrong, right: right,
                                           count: 1, lastSeen: now))
        }
        return out
    }

    // MARK: - internals (exposed `internal` for tests)

    static func tokenize(_ s: String) -> [String] {
        s.components(separatedBy: tokenSeparators)
            .filter { !$0.isEmpty }
    }

    static func accept(wrong: String, right: String) -> Bool {
        // Identical tokens — nothing to learn.
        if wrong == right { return false }
        // Case-only differences ("i" → "I") aren't dictionary-worthy; the
        // count-threshold flow in PR-B is for proper-noun / brand-name terms.
        let wLower = wrong.lowercased()
        let rLower = right.lowercased()
        if wLower == rLower { return false }
        // Stop-word filter (SPEC §2.3).
        if stopWords.contains(wLower) { return false }
        // Edit-distance cap on lowercased forms (SPEC §2.3 — case-insensitive).
        if levenshtein(wLower, rLower) > maxEditDistance { return false }
        return true
    }

    /// Plain Levenshtein on `String.UnicodeScalarView` so multi-byte
    /// graphemes don't skew the cap.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a.unicodeScalars)
        let bChars = Array(b.unicodeScalars)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var prev = Array(0...bChars.count)
        var curr = [Int](repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            curr[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    curr[j - 1] + 1,        // insertion
                    prev[j] + 1,            // deletion
                    prev[j - 1] + cost      // substitution
                )
            }
            swap(&prev, &curr)
        }
        return prev[bChars.count]
    }
}
