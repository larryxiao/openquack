# SPEC-020 — One-click "Copy" button for the last transcript

## Goal

Give users a one-click way to copy the last transcript to the clipboard from the menu-bar popover. Today the transcript card has `textSelection(.enabled)` (manual ⌘A → ⌘C works) but no button. When the user dictated into a window that has since lost focus — the most common failure mode for paste-at-cursor — they need to grab the text and paste it manually elsewhere. Selecting text by hand inside the popover is fiddly because closing the popover (e.g., switching to Mail) can collapse the selection.

## What it does

- Adds a small `Copy` button in the "Last transcript" section header of `MenuBarContent.swift`, sibling to the existing `dur · rtf` metric.
- On tap: writes `state.lastTranscript` to the general pasteboard via the existing `PasteService.copyToClipboard(_:)` helper. No clearing of previous clipboard, no special types.
- Visual feedback: the button label flips to `Copied` for ~1.5s, then reverts to `Copy`. Implemented with a `@State` flag + `Task.sleep`. SF Symbol on the button: `doc.on.doc` (the standard "copy" glyph).
- The button is only rendered inside the same `if let transcript = state.lastTranscript, !transcript.isEmpty` guard that already governs the section, so it's never visible when there's nothing to copy.

## Non-goals

- No new keyboard shortcut. The popover's existing `textSelection(.enabled)` continues to handle ⌘A / ⌘C for power users.
- No clipboard history — that's `SPEC-014-local-history.md`.
- No analytics on usage. (Privacy contract: nothing leaves the device.)
- No haptic / sound feedback. The label flip is sufficient on macOS.

## Why this is small

- One-file change in `Sources/OpenQuackApp/MenuBarContent.swift`.
- No new dependencies, no new SwiftUI surface, no settings.
- `PasteService.copyToClipboard(_:)` already exists (defined as the "Copy buttons / fallback paths" helper at `Sources/OpenQuackKit/Output/PasteService.swift` line 45) — this SPEC just wires the button to it.
- No model migration, no settings persistence, no SettingsView change.

## How it interacts with existing behaviour

- The transcript already lands on the clipboard automatically in two cases:
  - Paste-at-cursor succeeds — clipboard is restored to its previous contents (per `PasteService.swift`).
  - Paste-at-cursor falls back (no Accessibility / focus-loss race) — the transcript is left on the clipboard, and the popover status reads "On clipboard".
- The `Copy` button is the deterministic third path: works in both cases above, lets the user re-copy at will (e.g., after their own pasteboard has cycled through other things), without depending on whether paste-at-cursor succeeded.

## Test plan

- Manual: dictate, lose focus on target window before transcription finishes, verify popover still shows transcript and "Copy" works.
- Manual: dictate twice in a row; verify "Copy" copies the *latest* transcript, not the previous one.
- Manual: tap "Copy" repeatedly; verify the "Copied" label correctly reverts and re-flips on the second tap (no stuck state from a cancelled Task).
- Manual: confirm the button is hidden when no transcript exists.
- Existing build/test/smoke-bench CI passes (no behavioural change to tests).

## Out of scope (future)

- Multi-transcript history with per-row Copy (deferred to SPEC-014 local history).
- Right-click context menu on the transcript card with Copy + Save + Send to (also deferred).
- Per-app smart copy formats (rich text vs plain) — overkill for v1; plain-text only.
