import Foundation

/// SPEC-022 §2.3 — One observed (wrong → right) substitution pair.
///
/// `wrong` is what Whisper emitted; `right` is what the user committed after
/// in-field editing. `count` accumulates across sessions; `lastSeen` is used
/// for cap eviction. `suppressedUntil` is set by the (PR-B) "Not now" path on
/// the nudge — persisted here so dismissal survives restarts, even though
/// PR-A doesn't yet read it.
public struct CorrectionCandidate: Sendable, Codable, Equatable {
    public var wrong: String
    public var right: String
    public var count: Int
    public var lastSeen: Date
    public var suppressedUntil: Date?

    public init(wrong: String,
                right: String,
                count: Int = 1,
                lastSeen: Date = Date(),
                suppressedUntil: Date? = nil) {
        self.wrong = wrong
        self.right = right
        self.count = count
        self.lastSeen = lastSeen
        self.suppressedUntil = suppressedUntil
    }

    /// Key for dedupe / merge — case-insensitive on both sides so "cloud code"
    /// → "Claude Code" and "Cloud Code" → "Claude code" collapse to one entry.
    /// The first-observed casing of `right` wins on merge; `count` accumulates.
    public var dedupeKey: String {
        "\(wrong.lowercased())\u{1F}\(right.lowercased())"
    }
}
