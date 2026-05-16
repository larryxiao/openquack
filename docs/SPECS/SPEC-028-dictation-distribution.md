# SPEC-028 — Dictation distribution + personal performance stats

**Status:** draft (Adoption focus)
**Owner:** `Sources/OpenQuackKit/Stats/` + Settings → Stats pane
**Last updated:** 2026-05-16

---

## Why this is in the adoption-pivot band

OpenQuack's two load-bearing USPs are **long-form dictation support** and
**fast post-stop processing** (5-min clip → 2.8 s after stop = ~12× streaming win).
Today the Stats pane shows aggregate words / audio / dictation count, but never
surfaces the numbers that *prove* the USPs to the user. A user who's just
dictated a 6-minute note has no way to see "that was 6 min 12 sec, processed
in 3.4 s — 110× realtime." The headline number is the artifact: it's
shareable on social, screenshot-able for a Show HN follow-up, and emotionally
satisfying.

This SPEC extends SPEC-013 (Usage stats) with three new surfaces:

1. **Longest dictation** — single biggest session, plus its processing time
   and realtime multiple.
2. **Average processing speed** — mean realtime multiple across the visible
   history.
3. **Length distribution** — histogram of session durations across the
   buckets the long-form claim cares about.

## Non-goals

- New persistence schema. `HistoryStore` already records `recordedAt`,
  `transcribedAt`, and `durationSeconds`; per-dictation process time is
  derivable, no migration needed.
- A leaderboard, public sharing button, or any network IO. Same privacy
  contract as SPEC-013.
- A chart library. SwiftUI shapes + the existing Theme are enough; no new
  dependency.
- Per-app or per-language slicing — sit out for a follow-up if the basic
  histogram lands first.

## Data model

### Per-entry derivation (no schema change)

For each `HistoryEntry`:

```swift
extension HistoryEntry {
    /// Wall-clock seconds from end-of-recording to end-of-transcription.
    /// Returns nil for entries still mid-transcription or pre-streaming.
    public var processSeconds: TimeInterval? {
        guard let transcribedAt else { return nil }
        let recordingEndedAt = recordedAt.addingTimeInterval(durationSeconds)
        let elapsed = transcribedAt.timeIntervalSince(recordingEndedAt)
        return elapsed > 0 ? elapsed : nil
    }

    /// `durationSeconds / processSeconds`. e.g. 300 s of audio processed in
    /// 3 s → 100. Nil when processSeconds is nil.
    public var realtimeMultiple: Double? {
        guard let processSeconds, processSeconds > 0 else { return nil }
        return durationSeconds / processSeconds
    }
}
```

### Aggregates over a history window

A new pure type in `Sources/OpenQuackKit/Stats/`:

```swift
public struct PerformanceSummary: Sendable, Codable {
    public let longestEntry: HistoryEntry?
    public let averageRealtimeMultiple: Double?  // mean across entries with non-nil RTM
    public let bucketCounts: [DurationBucket: Int]
}

public enum DurationBucket: String, CaseIterable, Sendable, Codable {
    case under30s    = "<30s"
    case to1min      = "30s–1m"
    case to3min      = "1–3m"
    case to10min     = "3–10m"
    case over10min   = "10m+"
}

public enum PerformanceSummariser {
    public static func summarise(_ entries: [HistoryEntry]) -> PerformanceSummary
}
```

The summariser is pure — no actor, no IO. Bucketing edges chosen to make
the 3-min and 10-min cliffs visible (those are the marketing-relevant
boundaries for the long-form claim).

## Settings → Stats pane additions

Append two rows + one block inside the existing `showUsageStats == true`
section, between **Audio processed** and **Time saved vs. typing**:

```
Longest dictation        6 min 12 s  ·  processed in 3.4 s  ·  110× realtime
Processing speed         avg 47× realtime
```

Then below the existing stats block, render a small SwiftUI bar chart:

```
Sessions by length
■■■■■■■■  <30s        (38)
■■■■      30s–1m      (19)
■■■       1–3m        (14)
■■        3–10m       (8)
■         10m+        (3)
```

Implementation: a `VStack` of `HStack`s, each with a `Capsule().frame(width:)`
sized proportional to `count / maxCount`. Theme tokens already exist
(`Theme.amber`, etc.); no new ones needed. Width caps at the pane's content
width so the longest bar fills the row.

All three additions live behind the same `showUsageStats` toggle that
already gates the rest of the pane.

## Out of scope

- Persisting `PerformanceSummary` — recompute on Settings open. The history
  window caps at SPEC-014's retention policy (50 entries by default), so a
  full sweep is microseconds.
- Animated chart transitions.
- Exporting the distribution as a separate JSON — the existing
  `UsageStats.exportJSON()` is the path; distribution belongs in a future
  export-v2 if asked for.
- Time-series chart (sessions per day). The distribution histogram is the
  scoped artifact here; per-day comes later if a user requests it.

## Test plan

- **Unit:** `PerformanceSummariserTests` — empty input, single entry,
  entries with nil `transcribedAt` skipped from RTM mean, bucket edges
  (29.999, 30.0, 30.001 across each boundary), longest selection.
- **Unit:** `HistoryEntry+ProcessSecondsTests` — nil when `transcribedAt`
  nil, nil when `transcribedAt < recordedAt + durationSeconds` (shouldn't
  happen but bounded), expected positive case.
- **Manual:** open Settings → Stats with at least three real dictations
  (mix of short + one long) → verify Longest row, Processing speed, and
  histogram render with sensible numbers.
- `swift build && swift test` green via the DEVELOPER_DIR override.

## PR shape

| PR  | Title                                                              | SPEC cite | Effort |
|-----|--------------------------------------------------------------------|-----------|--------|
| PR-A| `feat(SPEC-028): performance summariser + Settings → Stats additions` | SPEC-028 | S |

Single atomic PR — the pure summariser, the `HistoryEntry` derivations,
and the Settings additions all hang together; splitting would create a
half-shipped feature with a dangling helper.
