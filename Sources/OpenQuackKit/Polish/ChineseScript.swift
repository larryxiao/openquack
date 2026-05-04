import Foundation

/// Whisper's `zh` model emits a mix of Traditional and Simplified hanzi —
/// often skewing Traditional, even when the speaker is from the mainland.
/// This converter applies a character-level Hant↔Hans pass via ICU
/// (`StringTransform("Hant-Hans")`) so the script the user sees matches the
/// script they expect.
///
/// Caveat: ICU is character-level. `軟體` becomes `软体` rather than the
/// idiomatic mainland `软件`. Word-level conversion (OpenCC) is a future
/// upgrade; this fixes the script-mismatch case without adding a C++ dep.
public enum ChineseScript: String, Sendable, CaseIterable {
    case auto         // leave Whisper output untouched
    case simplified   // force zh-Hans
    case traditional  // force zh-Hant
}

public enum ChineseScriptConverter {
    /// Returns text converted to the target script. `auto` is a no-op and
    /// non-Chinese text is returned unchanged. Idempotent: applying the
    /// same target twice yields the same result.
    public static func convert(_ text: String, to target: ChineseScript) -> String {
        let transform: StringTransform
        switch target {
        case .auto:        return text
        case .simplified:  transform = StringTransform(rawValue: "Hant-Hans")
        case .traditional: transform = StringTransform(rawValue: "Hans-Hant")
        }
        return (text as NSString).applyingTransform(transform, reverse: false) ?? text
    }
}
