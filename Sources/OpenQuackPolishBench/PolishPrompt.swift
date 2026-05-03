import Foundation

/// A versioned polish prompt. We own the prompt; vocabulary, surrounding-text
/// and app-context are slots inside it. Each version is a complete recipe
/// (system template, user template, decoding hyperparameters) so the bench
/// can A/B them as a single unit.
public struct PolishPromptVersion: Sendable {
    public let id: String
    public let summary: String
    public let composeSystem: @Sendable (_ vocabulary: [String], _ appContext: String?) -> String
    public let composeUser:   @Sendable (_ raw: String, _ appContext: String?, _ surroundingText: String?) -> String
    public let temperature:   @Sendable (_ raw: String) -> Double
    public let numPredict:    @Sendable (_ raw: String) -> Int
}

public enum PolishPrompts {
    public static let registry: [String: PolishPromptVersion] = [
        "v1": v1,
        "v2": v2,
    ]

    public static func resolve(_ ids: [String]) throws -> [PolishPromptVersion] {
        try ids.map { id in
            guard let p = registry[id] else {
                let known = registry.keys.sorted().joined(separator: ", ")
                throw NSError(domain: "PolishPrompts", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "unknown prompt id '\(id)'. Known: \(known)"
                ])
            }
            return p
        }
    }

    // MARK: - v1 (ported verbatim from v0.1's thinker.py for regression baseline)

    public static let v1 = PolishPromptVersion(
        id: "v1",
        summary: "v0.1 baseline (verbatim port of thinker.py system prompt)",
        composeSystem: { vocabulary, appContext in
            var s = """
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
            if !vocabulary.isEmpty {
                s += "\n\nKnown vocabulary — preserve these spellings exactly when the input is a likely mishearing of one of them. Do not insert a glossary term unless it fits the context:\n"
                s += vocabulary.map { "- \($0)" }.joined(separator: "\n")
            }
            s += contextNudge(appContext)
            return s
        },
        composeUser: { raw, appContext, surroundingText in
            var msg = ""
            if let ctx = appContext, !ctx.isEmpty, ctx != "other" {
                msg += "[Context: writing in \(ctx)]\n"
            }
            if let st = surroundingText, !st.isEmpty {
                msg += "Surrounding text already in the field:\n\(st)\n\n"
            }
            msg += "Transcript:\n\(raw)"
            return msg
        },
        temperature: defaultTemperature,
        numPredict: defaultNumPredict
    )

    // MARK: - v2 (engineered around bench findings — substitution examples,
    // bullet restraint, idempotency. Few-shot examples deliberately use
    // OUTSIDE-corpus terms so we measure generalisation, not memorisation.)

    public static let v2 = PolishPromptVersion(
        id: "v2",
        summary: "Substitution-aware: explicit rules + few-shot examples (non-overlapping with corpus) + idempotency + bullet restraint",
        composeSystem: { vocabulary, appContext in
            var s = """
            You polish raw voice transcripts (from Whisper) into clean, ready-to-paste text.

            OUTPUT RULES — follow exactly:
            1. Reply in the SAME language as the input.
            2. Output ONLY the polished text. No preamble, no commentary, no quotation marks around the output, no markdown code fences, no "Here is the polished text:" labels.
            3. If the input is already clean and well-punctuated, return it unchanged. Do not invent edits.

            CLEANUP:
            - Remove filler words and verbal tics ("um", "uh", "like", "you know", "I mean", "basically", "literally") and equivalents in other languages (Chinese 嗯/那个; Japanese えーと/あのー; Spanish este/eh; French euh/ben; German äh/halt).
            - Remove false starts, self-corrections, stuttered repetitions.
            - Add correct sentence punctuation (English: . , ! ? — CJK: 。，！？).
            - Use bullets (• or -) ONLY when the input clearly enumerates two or more distinct items. Never bullet a single sentence. Never bullet word-by-word.

            SUBSTITUTION (proper nouns and technical terms):
            Whisper often mishears domain terms. If the input contains a phrase that sounds like an entry in the VOCABULARY list below, replace it with the listed spelling. The phonetic gap can be large — trust the list when context fits.

            Examples of the pattern (these examples are illustrations only — do not apply them unless the term appears in the actual VOCABULARY list):
            - input "tin sir flow runs on jee pee you" with vocabulary "TensorFlow, GPU" → "TensorFlow runs on GPU."
            - input "doctor strange is a marvel film" with empty vocabulary → "Doctor Strange is a Marvel film." (no substitution; only spelling/casing)
            - input "let's use kuber neighties" with vocabulary "Kubernetes" → "Let's use Kubernetes."

            Do NOT invent substitutions for terms that aren't in the VOCABULARY list. Preserve unfamiliar words as written.

            CONTEXT:
            - If a "Surrounding text" block is provided, use it to choose between vocabulary candidates that could fit the input.
            - If an "[App: chat|email|code|docs|terminal]" tag is provided, match the register: chat = short, casual; email = formal sentences; code = preserve identifiers, comment-style if input is comment-shaped; docs = paragraph prose; terminal = single-line if input is a command.
            """
            if !vocabulary.isEmpty {
                s += "\n\nVOCABULARY (preserve spelling exactly; substitute when input is a likely mishearing):\n"
                s += vocabulary.map { "- \($0)" }.joined(separator: "\n")
            } else {
                s += "\n\nVOCABULARY: (none — only fix spelling/casing of terms you already recognise; do not invent substitutions)"
            }
            s += contextNudge(appContext)
            return s
        },
        composeUser: { raw, appContext, surroundingText in
            var msg = ""
            if let ctx = appContext, !ctx.isEmpty, ctx != "other" {
                msg += "[App: \(ctx)]\n"
            }
            if let st = surroundingText, !st.isEmpty {
                msg += "Surrounding text already in the field:\n\(st)\n\n"
            }
            msg += "Transcript:\n\(raw)"
            return msg
        },
        temperature: defaultTemperature,
        numPredict: defaultNumPredict
    )

    // MARK: - shared helpers

    @Sendable static func contextNudge(_ context: String?) -> String {
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

    @Sendable static func defaultTemperature(_ raw: String) -> Double {
        estimateWords(raw) < 50 ? 0.3 : 0.5
    }

    @Sendable static func defaultNumPredict(_ raw: String) -> Int {
        min(max(estimateWords(raw) * 2, 80), 1024)
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
