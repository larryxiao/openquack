import Foundation

/// SPEC-028 — Personal performance summary derived from `HistoryStore`
/// entries. Pure: no actor, no IO, recomputed on Settings → Stats open.
/// The longest dictation, the average realtime multiple, and the length
/// histogram are the three surfaces that make OpenQuack's long-form +
/// fast-processing USPs visible as personal numbers, not bench numbers.

/// Duration buckets the long-form claim cares about. RawValues match the
/// label text rendered in the Stats pane; the boundaries are half-open
/// `[lower, upper)` so the 30 s / 1 m / 3 m / 10 m cliffs land
/// unambiguously on the higher bucket.
public enum DurationBucket: String, CaseIterable, Sendable, Codable {
    case under30s    = "<30s"
    case to1min      = "30s–1m"
    case to3min      = "1–3m"
    case to10min     = "3–10m"
    case over10min   = "10m+"

    /// `[lower, upper)` in seconds. `upper == nil` means open-ended.
    fileprivate var range: (lower: TimeInterval, upper: TimeInterval?) {
        switch self {
        case .under30s:  return (0, 30)
        case .to1min:    return (30, 60)
        case .to3min:    return (60, 180)
        case .to10min:   return (180, 600)
        case .over10min: return (600, nil)
        }
    }

    fileprivate static func bucket(forDuration seconds: TimeInterval) -> DurationBucket {
        // Walk in declared order; first matching range wins. Negatives clamp
        // into `.under30s` so a malformed entry still buckets somewhere.
        let d = max(0, seconds)
        for b in DurationBucket.allCases {
            let (lo, hi) = b.range
            if d >= lo, hi == nil || d < hi! { return b }
        }
        return .over10min
    }
}

/// Aggregate over a history window. Values are `nil` when there is
/// nothing to summarise (empty window, no transcribed entries).
public struct PerformanceSummary: Sendable, Codable {
    /// Entry with the largest `durationSeconds`. Nil iff `entries` was
    /// empty. The longest entry can still have `processSeconds == nil`
    /// (mid-transcription / recovery-flow); the UI must guard the tail.
    public let longestEntry: HistoryEntry?
    /// Mean of `realtimeMultiple` across entries that have a non-nil
    /// RTM. Nil when zero entries qualify (every entry untranscribed,
    /// or empty input).
    public let averageRealtimeMultiple: Double?
    /// Counts per bucket; every `DurationBucket` case is present with at
    /// least a 0 value so the UI can iterate `DurationBucket.allCases`
    /// without optional dancing.
    public let bucketCounts: [DurationBucket: Int]

    public init(longestEntry: HistoryEntry?,
                averageRealtimeMultiple: Double?,
                bucketCounts: [DurationBucket: Int]) {
        self.longestEntry = longestEntry
        self.averageRealtimeMultiple = averageRealtimeMultiple
        self.bucketCounts = bucketCounts
    }
}

/// Pure summariser. Bucketing edges are documented on `DurationBucket`.
/// Average RTM skips entries with nil RTM (no `transcribedAt` yet,
/// or zero/negative process time) — only meaningful samples contribute.
public enum PerformanceSummariser {
    public static func summarise(_ entries: [HistoryEntry]) -> PerformanceSummary {
        // Bucket counts — initialise every case to 0 so callers don't
        // have to handle missing keys.
        var counts: [DurationBucket: Int] = [:]
        for b in DurationBucket.allCases { counts[b] = 0 }

        var longest: HistoryEntry?
        var rtmSum: Double = 0
        var rtmCount: Int = 0

        for entry in entries {
            counts[DurationBucket.bucket(forDuration: entry.durationSeconds), default: 0] += 1

            if let current = longest {
                if entry.durationSeconds > current.durationSeconds {
                    longest = entry
                }
            } else {
                longest = entry
            }

            if let rtm = entry.realtimeMultiple {
                rtmSum += rtm
                rtmCount += 1
            }
        }

        let avgRTM: Double? = rtmCount > 0 ? rtmSum / Double(rtmCount) : nil
        return PerformanceSummary(longestEntry: longest,
                                  averageRealtimeMultiple: avgRTM,
                                  bucketCounts: counts)
    }
}
