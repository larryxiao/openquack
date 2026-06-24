# SPEC-004a — Recording overlay on another app's fullscreen Space (investigation)

**Status:** draft — investigation, unresolved (tentative fix under test)
**Extends:** [SPEC-004](SPEC-004-overlay.md)
**Last updated:** 2026-06-24

---

## Problem statement

The recording overlay (`Sources/OpenQuackApp/RecordingOverlay.swift`, an
`NSPanel`) intermittently fails to appear on the user's current Space when
dictation is triggered while another app is in native (green-button)
fullscreen. macOS gives each fullscreen app its own Space; in the failing case
the pill is created (alpha = 1) and positioned on the correct physical screen,
but it lands on a *background* desktop Space instead of the active fullscreen
one — so the user sees nothing while dictating.

Dictation itself is unaffected (capture, transcription, and paste all work);
this is a visual-only defect. But the privacy contract (SPEC-004 §Goal) wants
the user to always see when the mic is hot, so it still matters.

### Why it is intermittent

The panel is created lazily on the first dictation after launch and then reused
for the app's lifetime. It appears bound to the Space it was *born* on:
`.canJoinAllSpaces` extends it across regular desktops but not into a fullscreen
Space entered later. So whether it shows in fullscreen depends on where the
first dictation of that launch happened:

- First dictation in a fullscreen Space → works for that whole session.
- First dictation on a regular desktop → fails in fullscreen for that session.

Deterministic *within* a launch, but varies *across* launches — which reads as
"sometimes it works." A restart that happens to begin in fullscreen "fixes" it
until the next launch.

## Constraint: the overlay must not steal focus

Per SPEC-004 §Behaviour the overlay must never become key — `makeKeyAndOrderFront`
is explicitly forbidden. Paste delivers the transcript by writing to the
pasteboard and posting a synthetic ⌘V to *whatever app is frontmost at paste
time* (`PasteService`, called from `OpenQuackApp.swift`). A focus-stealing panel
would (a) move focus off the target app and (b) risk intercepting the synthetic
⌘V — breaking paste-at-cursor. This rules out the otherwise-standard fix.

## Diagnosis method

External, no in-app instrumentation: `CGWindowListCopyWindowInfo` distinguishes
"window exists on some Space" (`.optionAll`) from "window is on the *active*
Space" (`.optionOnScreenOnly`). The overlay (owner `OpenQuack`, 320×60) showing
in the former but not the latter — i.e. `isOnActiveSpace == false` while
alpha = 1 — is the failure signature. `NSWindow.isOnActiveSpace` reports the
same for an in-process check.

## Attempts

| # | Change | Result |
|---|--------|--------|
| 1 | Window level `.floating` → `.statusBar` | No effect on Space membership; level only governs z-order. Abandoned. |
| 2 | `orderFront(nil)` → `orderFrontRegardless()` (merged in #102) | Confirmed via CGWindowList: still `isOnActiveSpace == false`. Did **not** fix. |
| 3 | Rebuild the panel on each show (this branch) | Under test — born on the active Space every dictation. |

## Approaches considered and rejected

- **`makeKeyAndOrderFront` (key window)** — what the open-source Sol launcher
  (`ospfranco/sol`) uses; reliably lands on any active Space *including*
  fullscreen, with a single reused window. Rejected: steals focus / risks the
  ⌘V paste (see Constraint). Note this proves a reused window *can* join a
  fullscreen Space — the operative factor there is becoming key, not the
  collection-behavior flags.
- **`NSWorkspace.activeSpaceDidChangeNotification`** — a legitimate, standard
  API, but the failure happens at show-time (panel born on the wrong Space),
  not on a Space change while the pill is visible. Wrong tool for this case.
- **Conditional rebuild via `isOnActiveSpace`** — the field is unreliable when
  the window is ordered-out and stale immediately after `orderFront`. Flaky,
  for a saving that is negligible (one small window per dictation).
  Unconditional rebuild is simpler and deterministic.
- **Removing `.stationary`** — Sol omits it, but per Apple docs `.stationary`
  governs Exposé/Mission Control behaviour, not Space membership. Low
  confidence; untested.

## Current approach (this branch)

Tear the panel down on hide (`panel = nil`) so the next dictation rebuilds it
via `ensurePanel()` on whatever Space is active then. Cost is one 320×60
`NSPanel` + `NSHostingView` per dictation — negligible (not per-frame).

## Acceptance criteria

Validated when, against a reproducible failing baseline, the overlay appears on
the active fullscreen Space:

1. **Baseline (current build):** relaunch OpenQuack, do the first dictation on a
   regular desktop, then enter another app's fullscreen and dictate. Expected:
   pill not visible; `isOnActiveSpace == false`.
2. **With the fix:** same steps → pill visible over the fullscreen app;
   `isOnActiveSpace == true`.

Verification is manual (the app layer is an `executableTarget`, untestable by
SwiftPM; Space behaviour needs a live GUI). The bug is intermittent across
launches but deterministic given the first-dictation Space, so step 1 must
establish a failing baseline before step 2 is meaningful.

## Status / risk

Tentative, and possibly not cleanly solvable in the short term. Three attempts
so far; the strongest non-focus-stealing levers (level, `orderFrontRegardless`)
did not fix it. If rebuild also fails, the fallback is to accept the limitation
as a documented known issue, or surface fullscreen recording state through a
different channel (e.g. the menu-bar item, which always renders over fullscreen).

## References

- [SPEC-004](SPEC-004-overlay.md) — base overlay spec (esp. §Behaviour: no `makeKeyAndOrderFront`, cursor-screen positioning).
- Sol launcher window setup — `ospfranco/sol`: `macos/sol-macOS/views/Panel.swift`, `macos/sol-macOS/managers/PanelManager.swift`.
- Apple Developer Forums — "Window visible on all spaces (including fullscreen apps)" (thread 26677).
