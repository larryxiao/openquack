import Foundation

/// Default Whisper-bias entries for the user's custom dictionary.
///
/// New installs get this filled into `UserDefaults["customWords"]`
/// via the `@AppStorage` default in Settings — visible in the
/// Custom dictionary editor on first launch, easy to edit / extend.
/// Existing users (whose UserDefaults key is already set) can pull
/// it down via the "Restore suggested words" button in Settings.
///
/// Curated for OpenQuack's target user group: macOS users with
/// developer / AI-tooling context. The list focuses on proper
/// nouns and tokens Whisper routinely mangles (e.g. *Claude* →
/// "cloud", *OpenQuack* → various contortions) rather than dumping
/// a generic English word list — Whisper bias has diminishing
/// returns past ~10-20 entries.
///
/// Additions belong here only if they meet *both*:
///   - The target user group says the word often
///   - Whisper measurably mishears it (single tokens like
///     "compile" don't need biasing)
public enum CustomDictionaryDefaults {
    /// The seed entries, one per line, in the order they appear in
    /// the editor. Order doesn't affect Whisper bias weighting (the
    /// prompt is a bag of strings), but it affects how the list
    /// reads to the user when they first open Settings.
    public static let seedEntries: [String] = [
        "Claude",
        "Claude Code",
        "Anthropic",
        "OpenQuack",
        "WhisperKit",
        "macOS",
        "AppleScript",
        "Xcode",
    ]

    /// Newline-joined form for direct insertion into the
    /// `customWords` UserDefaults key / `@AppStorage` default.
    public static var seedList: String {
        seedEntries.joined(separator: "\n")
    }
}
