# SPEC-044 — Agent-driven UI snapshot validation

## Goal

Let an agent **see** the app's UI and validate it against the specs, **locally**
— render each surface to a PNG, look at the pixels, check them against the
governing spec's acceptance criteria, fix discrepancies, and re-render. No cloud,
no launching the menu-bar app, no screen-capture, no live mic. Catches the class
of bug unit tests miss: a state whose *logic* is correct but whose *rendered UI*
is wrong (truncated, mislabelled, off-layout).

## Background

Unit tests cover logic; SPEC-042 covers recording behaviour. Neither sees what
the user sees. The recording overlay, Settings panes, and onboarding are SwiftUI
— and on macOS 13+ `ImageRenderer` renders any `View` to a bitmap deterministically
and headlessly, so the UI can be captured without the WindowServer dance.

## Mechanism

### Snapshot mode

`OQ_SNAPSHOT_DIR=<dir> openquack` renders fixed UI states to `<dir>/*.png` and
exits, instead of running the menu bar (`SnapshotRenderer`, gated in `main()`).
States are deterministic (constructed `AppState`, no live data). Today it covers
`OverlayPill` in its phases — listening, thinking, pasted, **interrupted**
(SPEC-036), kickoff (SPEC-031). The Settings panes reach into `NSApp.delegate`
(~10 spots) and need light decoupling (inject the data) before they render
standalone — added incrementally.

### The validation loop

An agent runs snapshot mode → for each PNG, reads the image *and* the governing
spec's `## Acceptance criteria` → judges whether the rendered UI matches → reports
or fixes → re-renders to confirm. The "improve on its own" is that
render → see → validate → fix → re-render cycle; it runs locally (e.g. a Workflow
`ui-validator` agent per SPEC-037).

**Proven on the first run:** the loop caught two bugs in the interrupted-overlay
state that no unit test would — the notice was **truncated** ("…audio devic…")
and the headline misread **"Copied to clipboard"** on a cut-short recording.
Both are fixed in this PR (headline → "Recording interrupted"; notice →
"Saved what we captured", which fits the pill), confirmed by re-rendering.

## Privacy impact

None. Snapshot mode renders local SwiftUI views to local PNGs; it's inert unless
`OQ_SNAPSHOT_DIR` is set, and adds no network or data collection.

## Acceptance criteria

- [ ] `OQ_SNAPSHOT_DIR=<dir> openquack` writes one PNG per overlay state and exits
      0, without showing a menu-bar item or requiring mic/screen permission. (manual)
- [ ] Each rendered overlay matches its spec: listening shows the level meter +
      "Listening" + elapsed; interrupted shows "Recording interrupted" + an
      untruncated notice; kickoff shows the claude affordance. (agent visual check)
- [ ] `swift build && swift test` green.

## Out of scope

- The full app-launch **behaviour** harness (inject a WAV, assert the transcript)
  — that's **SPEC-042 increment 2**; this spec is the *visual* half.
- Pixel-diff golden-image testing — the agent validates against the *spec*, not a
  frozen baseline, so intentional UI changes don't need golden re-baselining.
- Decoupling every Settings pane from `NSApp.delegate` — tracked, incremental.
