import Foundation

// SPEC-046 (ASD-STE100) — CJK-aware chunk stitcher for streaming transcription.
//
// Joins transcribed text chunks from StreamingTranscriber. Removes duplicate
// boundary words in Latin scripts and duplicate boundary characters in CJK
// scripts. Omits ASCII spaces between adjacent CJK chunks.

public enum ChunkStitcher {
    /// Maximum number of overlapping CJK characters to deduplicate at a seam.
    public static let maxCJKOverlap = 3

    /// Stitch an ordered list of chunk transcripts into one string.
    public static func stitch(_ chunks: [String]) -> String {
        let trimmedChunks = chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = trimmedChunks.first else { return "" }

        var out = first
        for next in trimmedChunks.dropFirst() {
            out = appendChunk(next, to: out)
        }
        return out
    }

    private static func appendChunk(_ next: String, to current: String) -> String {
        guard let lastChar = current.last, let firstChar = next.first else {
            return current + next
        }

        // Check CJK boundary condition: both sides are CJK or CJK punctuation.
        if isCJKOrCJKPunctuation(lastChar) && isCJKOrCJKPunctuation(firstChar) {
            let dedupedNext = deduplicateCJKOverlap(previous: current, next: next)
            return current + dedupedNext
        }

        // Latin / whitespace-delimited boundary: deduplicate one repeated word.
        let prevLastWord = lastWord(of: current)
        let nextWords = next.split(whereSeparator: { $0.isWhitespace })
        let nextFirstWord = nextWords.first.map(String.init) ?? ""

        if !prevLastWord.isEmpty,
           !isCJK( Character(prevLastWord.prefix(1)) ),
           wordKey(prevLastWord) == wordKey(nextFirstWord),
           !wordKey(prevLastWord).isEmpty {
            let stripped = nextWords.dropFirst().joined(separator: " ")
            if stripped.isEmpty {
                return current
            }
            return current + " " + stripped
        }

        return current + " " + next
    }

    /// Remove 1 to `maxCJKOverlap` repeated CJK characters at the seam.
    private static func deduplicateCJKOverlap(previous: String, next: String) -> String {
        let prevChars = Array(previous)
        let nextChars = Array(next)
        let maxK = min(maxCJKOverlap, min(prevChars.count, nextChars.count))
        guard maxK >= 1 else { return next }

        for k in stride(from: maxK, through: 1, by: -1) {
            let suffix = prevChars.suffix(k)
            let prefix = nextChars.prefix(k)
            if suffix.elementsEqual(prefix) && suffix.allSatisfy({ isCJK($0) }) {
                return String(nextChars.dropFirst(k))
            }
        }
        return next
    }

    private static func lastWord(of s: String) -> String {
        let parts = s.split(whereSeparator: { $0.isWhitespace })
        return parts.last.map(String.init) ?? ""
    }

    private static func wordKey(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    /// Return true when the character is a CJK ideograph, kana, or hangul syllable.
    public static func isCJK(_ c: Character) -> Bool {
        for scalar in c.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v)
                || (0x3400...0x4DBF).contains(v)
                || (0x3040...0x309F).contains(v)
                || (0x30A0...0x30FF).contains(v)
                || (0xAC00...0xD7AF).contains(v)
            {
                return true
            }
        }
        return false
    }

    private static let cjkPunctuation: Set<Character> = [
        "，", "。", "！", "？", "；", "：", "、",
        "（", "）", "《", "》", "「", "」", "『", "』",
        "“", "”", "‘", "’", "—", "…",
    ]

    /// Return true when the character is CJK text or full-width CJK punctuation.
    public static func isCJKOrCJKPunctuation(_ c: Character) -> Bool {
        isCJK(c) || cjkPunctuation.contains(c)
    }
}
