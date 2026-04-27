import Foundation

/// Lightweight text post-processing for raw Whisper output.
///
/// Whisper's output is usually OK, but on short utterances it skips
/// end-of-sentence punctuation, sometimes lowercases the first word, and
/// occasionally surfaces filler words it heard. A regex pass cleans up
/// most of this for free, no LLM required.
///
/// All rules are individually toggleable; defaults are conservative (won't
/// change a "the the cat" into "the cat" — that's the kind of false-positive
/// we'd rather not introduce by default).
public enum TextPolisher {
    public struct Settings: Sendable, Equatable {
        public var capitalizeFirst: Bool
        public var addEndPunctuation: Bool
        public var stripFillers: Bool
        public var collapseWhitespace: Bool
        public var fixSoloI: Bool

        public init(
            capitalizeFirst: Bool = true,
            addEndPunctuation: Bool = true,
            stripFillers: Bool = true,
            collapseWhitespace: Bool = true,
            fixSoloI: Bool = true
        ) {
            self.capitalizeFirst = capitalizeFirst
            self.addEndPunctuation = addEndPunctuation
            self.stripFillers = stripFillers
            self.collapseWhitespace = collapseWhitespace
            self.fixSoloI = fixSoloI
        }

        public static let standard = Settings()
        public static let off = Settings(
            capitalizeFirst: false,
            addEndPunctuation: false,
            stripFillers: false,
            collapseWhitespace: false,
            fixSoloI: false
        )
    }

    /// Apply all enabled rules. Order matters — fillers are stripped first
    /// (so the resulting whitespace can be collapsed), then casing fixes,
    /// then trim, then capitalisation, then end-punctuation.
    public static func polish(_ raw: String, settings: Settings = .standard) -> String {
        var text = raw

        if settings.stripFillers {
            text = applyStripFillers(text)
        }
        if settings.fixSoloI {
            text = applyFixSoloI(text)
        }
        if settings.collapseWhitespace {
            text = applyCollapseWhitespace(text)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.capitalizeFirst {
            text = applyCapitalizeFirst(text)
        }
        if settings.addEndPunctuation {
            text = applyEndPunctuation(text)
        }

        return text
    }

    // MARK: - rules

    private static let fillerRegex: NSRegularExpression = {
        // Standalone fillers: um, uh, er, ah, hmm (and stretched variants).
        // We deliberately do NOT strip "like / you know / I mean" — those have
        // legitimate uses and removing them changes meaning.
        try! NSRegularExpression(
            pattern: #"\b(?:um+|uh+|er+|ah+|hm+)\b[,]?\s*"#,
            options: [.caseInsensitive]
        )
    }()

    private static func applyStripFillers(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        return fillerRegex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }

    private static let soloIRegex: NSRegularExpression = {
        // standalone lowercase 'i' not part of a word, not part of a contraction.
        try! NSRegularExpression(pattern: #"(?<![a-zA-Z'])i(?![a-zA-Z])"#, options: [])
    }()

    private static func applyFixSoloI(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        return soloIRegex.stringByReplacingMatches(in: s, range: range, withTemplate: "I")
    }

    private static let multiWhitespaceRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\s{2,}"#, options: [])
    }()

    private static let spaceBeforePunctRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\s+([,.;:!?])"#, options: [])
    }()

    private static func applyCollapseWhitespace(_ s: String) -> String {
        let r1 = NSRange(s.startIndex..., in: s)
        var out = multiWhitespaceRegex.stringByReplacingMatches(in: s, range: r1, withTemplate: " ")
        let r2 = NSRange(out.startIndex..., in: out)
        out = spaceBeforePunctRegex.stringByReplacingMatches(in: out, range: r2, withTemplate: "$1")
        return out
    }

    private static func applyCapitalizeFirst(_ s: String) -> String {
        guard let first = s.first, first.isLetter, first.isLowercase else { return s }
        return first.uppercased() + s.dropFirst()
    }

    private static let sentenceEnders: Set<Character> = [
        ".", "!", "?",         // English / Latin
        "。", "！", "？",       // CJK
        "…",                   // ellipsis
    ]

    private static func applyEndPunctuation(_ s: String) -> String {
        guard let last = s.last, !sentenceEnders.contains(last) else { return s }
        // CJK heuristic — if the last character is in CJK range, append the
        // full-width stop instead of "." so it reads idiomatic.
        if isCJK(last) {
            return s + "。"
        }
        return s + "."
    }

    private static func isCJK(_ c: Character) -> Bool {
        for scalar in c.unicodeScalars {
            let v = scalar.value
            // CJK Unified Ideographs, Hiragana, Katakana, Hangul Syllables.
            if (0x4E00...0x9FFF).contains(v)
                || (0x3040...0x309F).contains(v)
                || (0x30A0...0x30FF).contains(v)
                || (0xAC00...0xD7AF).contains(v)
            {
                return true
            }
        }
        return false
    }
}
