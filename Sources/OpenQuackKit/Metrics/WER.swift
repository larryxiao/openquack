import Foundation

public enum WER {
    /// Word Error Rate: Levenshtein distance over whitespace-separated tokens of the
    /// normalised reference and hypothesis. Result is in [0, ∞), commonly reported as
    /// fraction (0.05 = 5%).
    public static func compute(reference: String, hypothesis: String) -> Double {
        let ref = normalize(reference).split(whereSeparator: \.isWhitespace).map(String.init)
        let hyp = normalize(hypothesis).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0.0 : 1.0 }
        return Double(levenshtein(ref, hyp)) / Double(ref.count)
    }

    /// Character Error Rate: Levenshtein over normalised characters. Better than WER
    /// for CJK / agglutinative languages where word boundaries are fuzzy.
    public static func cer(reference: String, hypothesis: String) -> Double {
        let ref = Array(normalize(reference))
        let hyp = Array(normalize(hypothesis))
        guard !ref.isEmpty else { return hyp.isEmpty ? 0.0 : 1.0 }
        return Double(levenshtein(ref, hyp)) / Double(ref.count)
    }

    /// Lower-cases, replaces non-alphanumeric (except apostrophe inside words)
    /// with a single space, collapses runs of whitespace.
    public static func normalize(_ s: String) -> String {
        var out = String()
        out.reserveCapacity(s.count)
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "'" {
                out.append(ch)
            } else {
                out.append(" ")
            }
        }
        return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func levenshtein<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = Swift.min(curr[j - 1] + 1, Swift.min(prev[j] + 1, prev[j - 1] + cost))
            }
            (prev, curr) = (curr, prev)
        }
        return prev[n]
    }
}
