# SPEC-022 — Custom dictionary auto-learn from user corrections

**Status:** draft  

---

## Problem statement

OpenQuack already supports a static custom dictionary that biases WhisperKit toward
user-defined terms (proper nouns, brand names, jargon). Adding a term today is
manual: the user must notice the error, open Settings, type the correction. In
practice most users don't do this — the cognitive overhead is too high in the
middle of a dictation flow.

Meanwhile, OpenQuack has all the signal it needs to infer bad terms automatically:
the user's transcript (what Whisper produced) and the text the user actually
committed (what they pasted, typed after correction, or sent). The gap between
those two strings is a training signal. A word Whisper consistently gets wrong is
a candidate for the dictionary.

---

## Goal

1. **Detect corrections silently.** When the committed text differs from the raw
   transcript, record the per-word substitutions without any user interruption.
2. **Surface candidates proactively.** Once a word pair (wrong → right) has been
   observed enough times, offer a one-tap "Add to dictionary" nudge.
3. **Close the feedback loop.** Let the user export their accumulated corrections
   as a pre-filled GitHub issue, so the signal can inform future bench corpus
   additions and model tuning decisions.

---

## How correction detection works

### 2.1 Committed-text capture

OpenQuack already knows the raw transcript (`state.lastTranscript`). The
highest-value signal is **paste-at-cursor + subsequent in-field editing**: the user
pastes, sees "cloud code", and fixes it to "Claude Code" without leaving the app
they're working in. Capturing this requires observing the focused text field after
the paste — which OpenQuack can already do, because Accessibility permission is
granted at onboarding for paste-at-cursor itself.

Capture happens in two paths:

| Commit path | How to capture |
|---|---|
| Paste-at-cursor succeeds | After `CGEvent` paste fires, attach an `AXObserver` to the focused element. Read the initial field value to establish a baseline. When focus leaves the element (or 60 s elapses), read the final value. Diff final vs. the pasted transcript to extract corrections. |
| User copies via the Copy button | Transcript text at button-tap time is snapshotted as `rawTranscript`. No field observation needed; the copy path is recorded as-is (no correction signal, but the word is logged for future diff if re-used). |

### 2.2 Post-paste field observer

Immediately after a successful paste:

1. **Snapshot** the focused element's current value via
   `AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute, ...)`.
   This is the field content including the pasted transcript.
2. **Register** an `AXObserver` callback on `kAXValueChangedNotification` for that
   element. This fires on every keystroke in the field — no polling needed.
3. **On focus-change or 60 s timeout**, read the element's value one final time.
   Unregister the observer.
4. **Extract the edited segment**: the transcript was appended at a known cursor
   position (or replaced a selection). Locate the start offset by finding the
   longest common prefix of the pasted transcript and the captured text. Run
   the token-level diff (§2.3) on that segment only — ignore pre-existing text in
   the field.
5. Feed any substitution pairs into the `CorrectionCandidate` store (§2.4).

The observer is scoped to a single element and a single paste event — it does not
persist across focus changes or new transcriptions. No continuous surveillance of
the user's typing.

### 2.3 Diff algorithm

Use a token-level diff (word-split on whitespace + punctuation). For each aligned
token pair `(whisper_word, user_word)` where `whisper_word != user_word` and
edit-distance is ≤ 3 (case-insensitive), record it as a candidate substitution:

```
CorrectionCandidate {
    wrong:   String   // what Whisper said
    right:   String   // what the user intended
    count:   Int      // how many times seen
    lastSeen: Date
}
```

Discard pairs where `wrong` is a common filler or stop word (the, a, is, was, …)
— those aren't dictionary candidates.

### 2.4 Persistence

Store candidates in a JSON file at
`~/Library/Application Support/OpenQuack/correction_candidates.json`.
Append-only within a session; deduplicate and merge counts on write.
Cap at 500 entries total; evict by `lastSeen` ascending when over the cap.

---

## Surface 1 — "Add to dictionary" nudge

### 3.1 Trigger

When a `CorrectionCandidate` reaches `count >= 3` and its `right` value is not
already in the custom dictionary, show a non-blocking banner notification (macOS
`NSUserNotification` / `UNUserNotificationCenter`) with the copy:

> **OpenQuack learned something** — Add "Claude Code" to your custom dictionary?
> [Add] [Not now]

"Add" appends `right` to the custom dictionary and removes the candidate from the
file. "Not now" suppresses the nudge for that word for 14 days (stored as a
`suppressedUntil` field in the candidate).

### 3.2 No interruption guarantee

The nudge fires at most once per session, and only after the session has been idle
for 30 s (no active transcription). Never during a recording or transcription in
progress.

---

## Surface 2 — Feedback export (GitHub issue template)

### 4.1 Entry point

Settings → Privacy pane: a "Export correction feedback" button, visible only when
`correction_candidates.json` contains ≥ 1 entry.

### 4.2 What gets exported

A pre-filled GitHub issue URL (opened in the default browser) with:

```
Title: [Feedback] STT corrections from user session

Body:
## Auto-generated correction log

These word-pairs were consistently mis-transcribed and corrected by the user.
They are candidates for custom dictionary defaults or bench corpus additions.

| Whisper output | Intended word | Occurrences |
|---|---|---|
| cloud code     | Claude Code   | 5           |
| whisper kit    | WhisperKit    | 3           |
...

OpenQuack version: 0.x.y
Model: whisperkit-medium
```

The body is URL-encoded and opened via
`https://github.com/openquack/openquack/issues/new?title=...&body=...`.

No data is sent anywhere automatically. The user sees the pre-filled browser form
and chooses whether to submit.

### 4.3 Privacy

Only `wrong` and `right` word pairs (plus counts) go into the export — no audio,
no full transcripts, no timestamps. The user sees the exact text before any
submission. A one-sentence disclaimer appears above the Settings button:
"Only the word pairs below are included — no audio or full transcripts."

---

## Out of scope

- Fully automatic dictionary updates without user confirmation (too aggressive;
  Whisper errors can be intentional slang or code-switching).
- Continuous or cross-session keylogging — the observer is per-paste, per-element,
  and unregistered on focus-change. No ambient text capture.
- Fields that do not expose `kAXValueAttribute` (password fields, some Electron
  apps): the observer silently no-ops; no fallback needed.
- ML-based candidate ranking (overkill at current correction volume; simple count
  threshold is sufficient).
- Sending correction data to any server (privacy contract: nothing leaves the
  device without explicit user action).
- The GitHub issue template as a YAML file in the repo (that's a separate PR with
  no new Swift code, trivially done alongside or after this SPEC lands).

---

## PR shape

| PR | Title | SPEC cite | Effort | CI gate |
|---|---|---|---|---|
| PR-A | `feat: post-paste AXObserver + correction candidate persistence` | SPEC-022 | S | swift build + swift test |
| PR-B | `feat: "Add to dictionary" nudge (≥3 occurrences threshold)` | SPEC-022 | S | swift build + swift test |
| PR-C | `feat: Settings — correction feedback export to GitHub issue` | SPEC-022 | S | swift build |

PR-A must land before PR-B and PR-C. PR-B and PR-C can be parallelised.
