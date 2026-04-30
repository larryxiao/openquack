# SPEC-013 — Usage stats pane

**Status:** draft (M3)
**Owner:** `OpenQuackKit/Stats/`
**Last updated:** 2026-04-30

## Goal

Show the user how much OpenQuack has done for them: words dictated, audio
processed, time saved versus typing. The product moment is opening Settings
and seeing **"47,328 words dictated this month — about 5 hours faster than
typing,"** with a quiet line beneath: *these numbers never leave your Mac*.
Pride and motivation, on the user's terms, no telemetry attached.

## Non-goals

- Cloud sync of stats across devices.
- Leaderboards, social sharing, gamification.
- Per-app or per-agent breakdowns — defer to a later spec; M3 ships
  aggregate totals only.
- Charts and history graphs — call-out under Open Questions; M3 ships a
  numeric pane.

## Public surface

```swift
public actor UsageStats {
    public init(store: UserDefaults = .standard)

    /// Whether new dictations contribute to the counters. Display gating
    /// lives in the app layer; this flag controls *recording* the data.
    public var trackingEnabled: Bool { get async }
    public func setTrackingEnabled(_ enabled: Bool) async

    /// Record one successful dictation. No-op when tracking is disabled.
    /// Word count uses the script-aware heuristic (see Behaviour).
    public func record(transcript: String, audioSeconds: TimeInterval) async

    /// Current totals — cheap to call; reads cached fields.
    public func snapshot() async -> UsageStatsSnapshot

    /// Wipe all counters. Irreversible. Confirm at the UI layer.
    public func reset() async

    /// Serialise current state for the "Export…" button.
    public func exportJSON() async throws -> Data
}

public struct UsageStatsSnapshot: Sendable, Codable {
    public let wordsDictated: Int
    public let audioSeconds: TimeInterval
    public let dictationCount: Int
    public let firstRecordedAt: Date?

    /// time_saved = words / typing_wpm × 60 − audio_seconds, floored at 0.
    public func timeSaved(typingWordsPerMinute: Int) -> TimeInterval {
        let typingSeconds = Double(wordsDictated) / Double(typingWordsPerMinute) * 60
        return max(0, typingSeconds - audioSeconds)
    }
}
```

## Behaviour

- `record(transcript:audioSeconds:)` is called from `AppDelegate` immediately
  after a successful paste, on the polished transcript (so re-runs of polish
  don't double-count).
- **Word count is script-aware**, mirroring SPEC-007's CJK heuristic:
  whitespace-split (drop empties) for Latin / Cyrillic / Arabic input;
  character count for CJK ranges (`U+4E00–U+9FFF`, `U+3040–U+30FF`,
  `U+AC00–U+D7AF`). Mixed strings: sum both methods on disjoint runs. Wraps
  the same helper SPEC-007 already lands; do not duplicate.
- Tracking is **on by default**. The privacy contract (VISION.md) forbids
  audio and transcripts leaving the machine; aggregate counters are derived
  numbers that never leave the machine either, so default-on tracking does
  not violate it. Users who want zero local writes flip a single toggle.
- Display is **off by default** — the Stats pane is hidden until the user
  opts in. Rationale: the menu-bar app should be quiet on first launch; the
  pane is a reward for users who go looking. Tracking-without-display means
  the moment they enable display, the numbers are already meaningful.

## Persistence

UserDefaults under `com.openquack.stats.*` keys: `wordsDictated`,
`audioSeconds`, `dictationCount`, `firstRecordedAt`, `trackingEnabled`.
Atomic writes; one round-trip per `record` call. No SQLite, no JSONL —
the working set is four scalars and the data plane stays trivial.

If a future spec adds per-day buckets for charts, escalate to a JSONL
append-log under `~/Library/Application Support/OpenQuack/stats.jsonl`.
Out of scope for M3.

## Settings UX

New **Settings → Stats** pane.

- A single toggle at the top: **"Show usage statistics."** Off by default.
  When off, the rest of the pane reads "Stats are tracked locally but
  hidden. Toggle to reveal." When on, the body reveals.
- Numbers shown:
  - **Words dictated** — lifetime total, monospace, comma-grouped.
  - **Audio processed** — `Hh Mm` format.
  - **Dictations** — lifetime count.
  - **Time saved vs. typing** — derived live from the current WPM setting.
  - **Since** — `firstRecordedAt`, formatted as "since 27 Apr 2026."
- A small **typing speed** stepper: default 50 WPM (≈ the average for desktop
  typists in Dhakal et al. 2018, *Observations on Typing from 136 Million
  Keystrokes*, CHI '18). Range 20–150. Configurable so power typists aren't
  lied to and slow typists aren't underwhelmed.
- A secondary toggle: **"Track usage statistics"** (default ON). Turning off
  freezes counters at their current values; turning back on resumes.
- Footer row: **"Export…"** writes the snapshot JSON via `NSSavePanel`;
  **"Reset…"** opens an `NSAlert` confirming "Reset all usage statistics?
  This can't be undone."

## Privacy

OpenQuack's privacy contract (VISION.md §Privacy contract) forbids audio
and transcripts leaving the machine, and bans default-on telemetry.
Stats-tracking complies:

- Counters are scalars (word count, seconds, dictation count). No transcript
  text is written.
- All data lives in UserDefaults on the user's Mac. No network IO, ever.
  No analytics endpoint exists in the build.
- The single toggle to disable tracking is one click away. The Reset button
  is irreversible and explicit.
- The Stats pane is hidden by default — the user opts *in* to seeing it,
  not out of it.

## Open questions

- **Charts.** A 30-day bar chart of words/day would be motivating but needs
  a per-day store. Add only if a follow-up spec justifies the persistence
  upgrade; the M3 numeric pane is enough to validate the feature.
- **Polished vs raw word count.** We count the polished transcript today.
  When SPEC-007's LLM polish trims fillers, the count is lower than what
  the user actually said. Alternative: count the raw transcript pre-polish.
  Lean polished — it's the text the user sent. Revisit if users push back.
- **Time-saved framing.** "5 hours faster than typing" assumes the user
  *would* have typed; for voice-native flows (agent dispatch, SPEC-006),
  the comparison is less meaningful. The number stays honest because it's
  derived from real audio seconds, but the framing copy may need to evolve
  once agents land.

## References

- VISION.md §Privacy contract — binding constraints reflected above.
- SPEC-007 — script-aware word/character counting heuristic to reuse.
- Dhakal, Feit, Kristensson & Oulasvirta. *Observations on Typing from 136
  Million Keystrokes.* CHI '18. Source for the 50 WPM default.
