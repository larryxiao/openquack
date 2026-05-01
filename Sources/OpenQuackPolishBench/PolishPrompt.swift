import Foundation

public enum PolishPrompt {
    /// Ported verbatim from SPEC-007 §Prompt template. Every extra token here
    /// adds latency — keep it tight. Multilingual: input language drives output
    /// language.
    public static let system: String = """
    You reorganise raw voice transcriptions into clean, structured text.

    You MUST:
    - Respond in the SAME language as the input.
    - Add correct punctuation (。，for Chinese; periods, commas for English; etc.).
    - Remove filler words, verbal tics, false starts, and repetitions.
    - Remove garbled or nonsensical text (transcription errors / artefacts).
    - Organise multiple ideas into bullet points (use • or -).
    - Keep it concise — shorter than the input.
    - Preserve all technical terms, proper nouns, and names exactly as spoken.
    - Output ONLY the reorganised text — no commentary, labels, or markdown fences.
    """

    /// SPEC-008 per-category nudges, appended to `system` when the case has
    /// app context. Empty for unknown / nil contexts.
    public static func contextNudge(_ context: String?) -> String {
        switch context {
        case "chat":
            return "\n\nThis text is going into a chat app — keep it short and casual; avoid bullets unless there are clearly several distinct items."
        case "email":
            return "\n\nThis text is going into an email — write formal sentences, no bullets unless requested, end with proper punctuation."
        case "code":
            return "\n\nThis text is going into a code editor — preserve identifiers exactly. If the input is a code-comment-shaped thought, format it as one short comment line."
        case "docs":
            return "\n\nThis text is going into a document — paragraph form, prefer prose over bullets."
        case "terminal":
            return "\n\nThis text is going into a terminal — if the input is a command, output a single shell-shaped line; do not invent flags."
        case "browser", "other", nil:
            return ""
        default:
            return ""
        }
    }

    /// Wrap raw text with optional `[Context: <kind>]` line. Mirrors v0.1's
    /// thinker.py shape; the bench injects `appContext` from the case.
    public static func userMessage(raw: String, appContext: String?) -> String {
        guard let ctx = appContext, !ctx.isEmpty, ctx != "other" else { return raw }
        return "[Context: writing in \(ctx)]\n\(raw)"
    }

    /// Token budget for `num_predict`. Mirrors v0.1's
    /// `min(max(wordCount * 2, 80), 1024)`. CJK characters each count as a word.
    public static func numPredict(for raw: String) -> Int {
        min(max(estimateWords(raw) * 2, 80), 1024)
    }

    /// Temperature: 0.3 for short, 0.5 for long, mirroring v0.1.
    public static func temperature(for raw: String) -> Double {
        estimateWords(raw) < 50 ? 0.3 : 0.5
    }

    public static func estimateWords(_ text: String) -> Int {
        let spaceWords = text.split(whereSeparator: \.isWhitespace).count
        var cjk = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v)
                || (0x3040...0x309F).contains(v)
                || (0x30A0...0x30FF).contains(v)
                || (0xAC00...0xD7AF).contains(v)
            {
                cjk += 1
            }
        }
        return spaceWords + cjk
    }
}
