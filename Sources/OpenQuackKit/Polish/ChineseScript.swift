import Foundation

/// Whisper's `zh` model emits a mix of Traditional and Simplified hanzi —
/// often skewing Traditional, even when the speaker is from the mainland, and
/// the script can flip between streaming chunks of one utterance. This type
/// picks the script to normalise toward (Traditional / Simplified) from the
/// user's macOS language preferences; `ChineseScriptConverter` applies a
/// character-level Hant↔Hans pass via ICU (`StringTransform`).
///
/// Caveat: ICU is character-level. `軟體` becomes `软体` rather than the
/// idiomatic mainland `软件`. Word-level conversion (OpenCC) is a future
/// upgrade; this fixes the script-mismatch case without adding a C++ dep.
public enum ChineseScript: String, Sendable, CaseIterable {
    case simplified   // zh-Hans
    case traditional  // zh-Hant

    /// Script implied by the user's macOS language preferences. Reads
    /// `Locale.preferredLanguages` at the call site; the mapping itself lives
    /// in `resolve(preferredLanguages:)` so it can be unit-tested.
    public static var systemDefault: ChineseScript {
        resolve(preferredLanguages: Locale.preferredLanguages)
    }

    /// Pure mapping from an ordered BCP-47 preferred-language list to a
    /// concrete script. Scans for the first Chinese entry (the picker only
    /// matters for Chinese speakers, so an English-primary user who also lists
    /// Traditional Chinese should still get Traditional). Defaults to
    /// Simplified when the list names no Chinese locale.
    ///
    /// The region table is authoritative: `Locale.Language(identifier:).script`
    /// is not reliably populated on region-only forms (`zh-HK`, `zh-TW`)
    /// without likely-subtag maximisation, so correctness never depends on it —
    /// an explicit script subtag is honoured when present, otherwise we fall
    /// back to the region.
    public static func resolve(preferredLanguages: [String]) -> ChineseScript {
        for identifier in preferredLanguages {
            let language = Locale.Language(identifier: identifier)
            guard language.languageCode?.identifier == "zh" else { continue }

            if let script = language.script?.identifier {
                return script == "Hant" ? .traditional : .simplified
            }
            if let region = language.region?.identifier,
               ["TW", "HK", "MO"].contains(region) {
                return .traditional
            }
            return .simplified
        }
        return .simplified
    }
}

public enum ChineseScriptConverter {
    /// Languages whose script is Han but *not* Chinese: Japanese kanji and
    /// Korean hanja share code points with hanzi, so the ICU Hant↔Hans
    /// transform would silently corrupt them. Output resolved to one of these
    /// is left byte-for-byte unchanged; everything else is converted.
    private static let hanButNotChinese: Set<String> = ["ja", "ko"]

    /// Normalise transcription output to the system's Chinese script. The ICU
    /// transform is a no-op on every non-Han character (Latin, digits,
    /// punctuation — see `testNonChineseUnchanged`), so we can safely convert
    /// *any* output that isn't Japanese/Korean: a mixed-language utterance
    /// transcribed as `en` (e.g. "Hello 軟體") still gets its embedded Chinese
    /// normalised, while pure English passes through untouched. Only `ja`/`ko`
    /// are excluded, to protect their kanji/hanja. `nil` (detection unknown)
    /// converts — there's nothing to corrupt unless the text is actually
    /// Japanese/Korean, which would have been detected as such.
    ///
    /// We deliberately do *not* alter the decode path to force Chinese on a
    /// mixed utterance; we only reshape the characters Whisper already emitted.
    /// Pure: the target script is derived from the supplied preferred-languages
    /// list.
    public static func normalize(
        _ text: String,
        language: String?,
        preferredLanguages: [String]
    ) -> String {
        if let language, hanButNotChinese.contains(language) { return text }
        return convert(text, to: ChineseScript.resolve(preferredLanguages: preferredLanguages))
    }

    /// Converts text to the target script via ICU. Non-Chinese characters and
    /// already-target characters pass through unchanged; idempotent.
    public static func convert(_ text: String, to target: ChineseScript) -> String {
        let transform: StringTransform
        switch target {
        case .simplified:  transform = StringTransform(rawValue: "Hant-Hans")
        case .traditional: transform = StringTransform(rawValue: "Hans-Hant")
        }
        return (text as NSString).applyingTransform(transform, reverse: false) ?? text
    }
}
