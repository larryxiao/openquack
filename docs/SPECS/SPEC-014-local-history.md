# SPEC-014 — Local audio + transcript history

**Status:** draft (M3)
**Owner:** `OpenQuackKit/History/`
**Last updated:** 2026-04-30

## Goal

You vaguely remember dictating something useful yesterday. Open
**Settings → History**, scan the list, click the row, and the transcript
is back on the clipboard — no re-dictation, no remembering exact phrasing.
**Recall is the headline** because every user gets it by default.

For users who opt in to audio storage, history also unlocks
**crash-recovery**: app dies mid-transcribe on a 90-second memo, and on
next launch a popover offers *"We found a recording from 2 minutes ago
that didn't finish. Recover?"* One click and the transcript is at the
cursor.

This spec defines a local-only on-disk store of recent dictations:
transcripts always (small, useful), audio behind an opt-in toggle
(bigger, more sensitive). Retention is bounded by count, age, and total
size. A "Delete all" button clears everything immediately.

## Non-goals

- Cloud sync of any kind. History is per-machine, full stop.
- Searchable full-text index — list-by-recency only for v1; search is a
  follow-up if users ask.
- Conversation history for agent sessions — that's SPEC-006's surface,
  separate store, separate retention rules.
- Partial transcripts streamed mid-recording — see SPEC-012.
- Editable transcripts. The list shows what was produced; edits live in
  the destination app.

## Defaults — defended

The central design call: SPEC-001 deliberately keeps audio in memory.
Persisting it shifts the privacy posture. We split the toggle:

- **Transcripts: ON by default.** Already-on-the-machine text — the
  clipboard saw it, the destination app saw it. Storing under
  `~/Library/Application Support/OpenQuack/History/` adds no new leak
  surface and unlocks recall. ~1 KB per entry.
- **Audio: OFF by default.** Voice carries biometrics and ambient
  capture (whoever else is in the room, what's on the TV). Persisting
  audio is a posture shift most users will not expect from "a
  dictation tool that doesn't upload audio." Crash-recovery only works
  with audio on, so we surface the toggle in onboarding's advanced
  step — never flip it silently.

Consequence: transcript recall is the universal benefit;
crash-recovery is opt-in. Revisit if user signal disagrees.

## Public surface

```swift
public actor HistoryStore {
    public init(rootURL: URL = .applicationSupport
        .appendingPathComponent("OpenQuack/History"),
                policy: RetentionPolicy = .default)

    /// Persist a completed dictation. Audio is included only if `saveAudio`
    /// is true; pass the raw [Float] from AudioRecorder. Throws on disk
    /// errors — the caller falls back to in-memory-only behaviour.
    public func save(audio: [Float]?,
                     transcript: String,
                     language: String?,
                     modelID: String,
                     durationSeconds: TimeInterval) async throws -> HistoryEntry

    /// Mark an entry as transcribed. Used by the crash-recovery flow when
    /// audio was saved before transcription completed.
    public func markTranscribed(_ id: UUID, transcript: String) async throws

    /// Entries with audio but no `transcribedAt` — candidates for recovery.
    public func recoverable() async -> [HistoryEntry]

    /// Recent entries, newest first.
    public func list(limit: Int = 50) async -> [HistoryEntry]

    public func delete(_ id: UUID) async throws
    public func purgeAll() async throws

    /// Apply the retention policy. Called on save and on app launch.
    public func enforceRetention() async
}

public struct HistoryEntry: Sendable, Identifiable, Codable {
    public let id: UUID
    public let recordedAt: Date
    public let transcribedAt: Date?
    public let durationSeconds: TimeInterval
    public let transcript: String?
    public let language: String?
    public let modelID: String?
    /// Nil when audio history is off or the recording is transcript-only.
    public let audioURL: URL?
}

public struct RetentionPolicy: Sendable {
    public var maxEntries: Int           // default 50
    public var maxAge: TimeInterval      // default 14 days
    public var maxBytesOnDisk: Int64     // default 500 MB
    public static let `default`: RetentionPolicy
}
```

## Storage layout

One recording = one directory under `~/Library/Application
Support/OpenQuack/History/`:

```
History/
  <UUID>/
    meta.json     ~1 KB — recordedAt, transcribedAt, language, modelID,
                          durationSeconds, audioFormat
    transcript.txt — UTF-8, present iff transcribed
    audio.opus    — present iff audio history is on
```

- **Audio format: Opus at 24 kbps mono** via `AVAssetWriter`. ~180 KB/min
  vs. SPEC-001's raw 1.4 MB/min — 8× smaller, transparent at speech
  bitrates. Whisper re-decodes from the file at recovery time; we
  measure no detectable WER delta vs. raw WAV in bench.
- **transcript.txt is plaintext**, not JSON, so users can `cat`, grep,
  or `mdfind` their own dictations from the terminal. Privacy posture:
  the user owns the data, including its readability.
- **meta.json is the canonical record.** A directory missing
  transcript.txt but containing audio.opus is the recovery signal.

## Behaviour

Pipeline integration in `AppDelegate.stopAndTranscribe`:

```swift
let id = UUID()
if settings.saveAudio {
    try? await history.save(audio: pcm, transcript: "", language: nil,
                            modelID: modelID, durationSeconds: dur)
    // recordedAt set; transcribedAt nil → recoverable if we crash here.
}
let raw = try await transcriber.transcribe(...)
let polished = polish(raw)
if settings.saveTranscripts {
    if settings.saveAudio {
        try? await history.markTranscribed(id, transcript: polished)
    } else {
        try? await history.save(audio: nil, transcript: polished, ...)
    }
}
PasteService.paste(polished)
```

Failures in `history.save` MUST NOT block the paste path — a disk-full
or permission error degrades to in-memory-only for that turn, with a
single banner notification (not per-turn).

`enforceRetention` runs:
- After every `save` (cheap — directory list + a few stats).
- On `applicationDidFinishLaunching`.
- Eviction order when a cap is hit: oldest first by `recordedAt`.

## Crash recovery

On `applicationDidFinishLaunching`, after the status item installs:

1. `history.recoverable()` — entries with `audioURL != nil` and
   `transcribedAt == nil`.
2. If non-empty, show a non-modal popover anchored to the menu-bar icon:
   > **We found a recording from 2 minutes ago that didn't finish.**
   > [Recover] [Discard] [Show in Finder]
3. **Recover** → run the normal transcription pipeline against
   `audioURL`, then deliver via paste-at-cursor (or open the
   conversation panel if the active agent is non-passthrough). The
   overlay shows the same `.transcribing` state as a fresh dictation;
   the user sees a familiar flow, not a recovery-specific UI.
4. **Discard** → `history.delete(id)` immediately.
5. **Show in Finder** → reveal the directory; useful for power users
   debugging a recurring failure.

If multiple recoverable entries exist (e.g., laptop slept overnight
mid-transcribe twice), show the count: *"3 recordings to recover."* The
popover lists them; recover/discard each individually or "Discard all."

Edge cases:
- App crashed during recording (no audio.opus written yet) — recovery
  only works if audio was streamed to disk per SPEC-012's chunked
  pipeline. Without SPEC-012, recovery is bounded to "post-stop,
  pre-paste" failures, which is still the majority of pain.
- Audio file present but corrupt — show the entry with a warning, offer
  Discard only.

## Privacy contract

Extending [VISION.md's privacy contract](../VISION.md#privacy-contract):

1. **Nothing in History/ ever leaves the machine.** No sync, no
   upload, no analytics on transcript content or counts.
2. **Audio is opt-in, sticky, never silently re-enabled.** Toggle in
   Settings → History plus a one-time onboarding step.
3. **At-rest protection.** macOS's volume-level encryption (FileVault,
   on by default since macOS 10.10) is the binding mechanism: when the
   user logs out the History/ directory becomes unreadable along with
   the rest of `~/Library`. The iOS-style file-protection attribute
   (`URLResourceKey.fileProtectionKey = .complete`) is **a silent
   no-op on macOS**; it's recorded in the implementation under an
   `#if os(iOS)` guard so the intent transfers if we ever ship on
   iPadOS, but it doesn't bind today. App-level encryption (Keychain +
   AES) is overkill for a single-user device app and we skip it.
4. **Delete is irreversible** — both per-entry and "Delete all." No
   soft-delete, no undo. Confirm dialog with explicit copy:
   "Permanently delete N recordings (X MB). This cannot be undone."
5. **Recovered audio is not re-saved as a new entry** — recovery
   transcribes in place.

## Settings UX

New tab: **Settings → History**.

- **Save transcripts** toggle (default ON). Disabling clears nothing
  but stops new writes.
- **Save audio (enables crash recovery)** toggle (default OFF). Turning
  ON shows a one-time inline note: "Audio is stored locally, encrypted
  at rest, and capped at 500 MB. Voice recordings are sensitive — keep
  this off if you share this Mac."
- **Retention** group:
  - Max entries: stepper, 10–500, default 50.
  - Max age: 1–90 days, default 14.
  - Max disk: 100 MB – 5 GB, default 500 MB.
- **Recent entries** list: scrollable, shows time-ago, duration, and
  the first ~80 chars of transcript. Row actions: Re-paste (copy to
  clipboard + simulated ⌘V via PasteService), Re-transcribe (only if
  audio present), Reveal in Finder, Delete.
- **Delete all history** — red button, bottom of pane, confirm dialog
  per the privacy contract.

## Quality gates

- **Disk under default policy:** ≤ 500 MB total at the cap; verified by
  saving 50 × 5-minute Opus recordings (~45 MB) and confirming
  enforcement evicts at the configured threshold.
- **Save latency:** ≤ 100 ms wall-clock for transcript-only saves; ≤
  500 ms for audio+transcript on M-series 16 GB. Save runs after
  paste, so it's off the user's hot path; budget exists for safety.
- **Recovery success rate:** 100 % of recoverable entries successfully
  re-transcribe on a corpus of synthetic crashes (kill -9 between save
  and markTranscribed). Add to `openquack-bench` as a smoke.
- **No memory growth:** 100 save/list/delete cycles add ≤ 5 MB RSS to
  baseline.
- **Privacy posture stable:** integration test asserts that with both
  toggles at default, no `audio.opus` file exists in History/ after a
  dictation cycle.

## Open questions

- **Search.** v1 is list-by-recency. Spotlight integration via
  `CSSearchableItem` (transcripts only, opt-in) or in-app fuzzy search
  is a follow-up if users ask.
- **Cross-device.** Power users will want History/ on Dropbox/iCloud
  Drive. Lean: allow `rootURL` override in Settings → Advanced; the
  user owns that privacy implication.
- **Conversation-panel integration.** SPEC-006 will produce its own
  text. Shared store or separate? Lean separate — different
  retention, different UX. Revisit when SPEC-006 lands.
- **Streaming + history overlap.** If SPEC-012 lands first, its
  chunked writes double as crash-recovery audio; until then, recovery
  covers "post-stop, pre-paste" failures only. We do not commit to
  ordering — whichever ships first does the persistence work, the
  second adopts the existing layer.

## References

- SPEC-001 — voice capture; in-memory-only contract that this spec
  selectively relaxes.
- SPEC-006 — agent dispatch; conversation history is a separate store.
- SPEC-012 — streaming transcription; shares the chunked-write pattern.
- VISION.md privacy contract — binding constraints restated above.
- `URLResourceKey.fileProtectionKey` / `.complete` — Apple docs.
- `AVAssetWriter` Opus encoding — `kAudioFormatOpus`, mono 16 kHz, 24 kbps.
