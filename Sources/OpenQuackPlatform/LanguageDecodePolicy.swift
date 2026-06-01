import Foundation

/// Pure decision for how to drive WhisperKit's language handling on a single
/// decode, shared by the offline (`WhisperKitEngine`) and streaming
/// (`StreamingTranscriber`) paths (SPEC-021).
///
/// WhisperKit only runs language detection when **both**
/// `options.language == nil` **and** `options.detectLanguage == true`; the
/// latter defaults to `false` (it derives from `!usePrefillPrompt`, and prefill
/// is on by default). With detection off and no pinned language, the decoder
/// silently prefills the English token and *translates* non-English speech.
///
/// This helper centralises the three-way choice so it can be unit-tested
/// without loading a model — it is the regression-prone part of the fix:
///
/// - **pinned** (user picked a language in Settings): force it, never detect.
/// - **locked** (streaming: a language already detected on an earlier chunk of
///   this utterance): reuse it so the utterance can't flip language mid-stream.
/// - **neither** (auto, first decode): turn detection on.
public enum LanguageDecodePolicy {
    public struct Decision: Equatable, Sendable {
        /// Value for `DecodingOptions.language` (nil ⇒ let the decoder detect).
        public let language: String?
        /// Value for `DecodingOptions.detectLanguage`.
        public let detectLanguage: Bool

        public init(language: String?, detectLanguage: Bool) {
            self.language = language
            self.detectLanguage = detectLanguage
        }
    }

    /// - Parameters:
    ///   - pinned: a user-selected language code, or nil for auto.
    ///   - locked: a language already resolved earlier in the same streaming
    ///     session, or nil. Ignored when `pinned` is set. Pass nil on the
    ///     stateless offline path.
    public static func decide(pinned: String?, locked: String? = nil) -> Decision {
        if let pinned, !pinned.isEmpty {
            return Decision(language: pinned, detectLanguage: false)
        }
        if let locked, !locked.isEmpty {
            return Decision(language: locked, detectLanguage: false)
        }
        return Decision(language: nil, detectLanguage: true)
    }
}
