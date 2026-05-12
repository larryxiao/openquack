# SPEC-003a — `fn` / Globe key as a bindable hotkey

**Status:** draft
**Extends:** [SPEC-003](SPEC-003-hotkey.md)
**Tracks:** [#23](https://github.com/larryxiao/openquack/issues/23)

---

## Problem statement

The onboarding shortcut picker (`Sources/OpenQuackApp/OnboardingFlow.swift`'s
`HotkeyStep`) is `KeyboardShortcuts.Recorder`, which is backed by Carbon's
`RegisterEventHotKey`. Carbon does not recognise the `fn` (Globe / Function)
key as a registerable modifier or key code — macOS reserves it at the HID
layer for OS-level handling (input source switch, dictation double-tap,
Function-row remapping). Result: pressing `fn` inside the picker is silently
ignored — the field waits for another key, as if nothing happened (#23).

This matters because `fn` is the de-facto push-to-talk key for Mac dictation
on Apple Silicon: Apple's built-in dictation uses double-tap-`fn`, and
third-party dictation/voice apps (Wispr Flow, MacWhisper, Superwhisper) all
let users bind it as a single-key hotkey. For new users coming from those
apps, `fn` is the *first* key they try in our picker, and right now we look
broken when they do.

## Goal

Let the user bind `fn` (alone, or as a modifier in combination with another
key) as the toggle / push-to-talk hotkey, from both onboarding and Settings.
Existing `KeyboardShortcuts`-backed bindings (default `⌃⇧Space`, plus any
the user has already chosen) continue to work unchanged.

## Non-goals

- **Double-tap-`fn` to activate.** Apple's dictation uses this idiom; we
  default to single-press to stay consistent with our existing toggle/PTT
  semantics. Revisit once the basic single-press path is shipped.
- **Replacing `KeyboardShortcuts` wholesale.** The package handles every
  Carbon-friendly shortcut just fine; we only need a parallel path for `fn`.
- **System-level Globe key remapping.** macOS's *System Settings → Keyboard →
  Press 🌐 to* controls a separate OS action; we don't touch it. We do warn
  the user when their OS-level setting will fire in addition to our hotkey
  (§5).
- **Non-Apple keyboards that lack a `fn` key.** We don't fall back to
  anything magical — the picker just won't ever see a `fn` flag from such a
  keyboard, and the user picks a Carbon shortcut as today.

## Why Carbon can't do this and what to use instead

`fn` arrives in Cocoa as `NSEvent.ModifierFlags.function` and in CG as
`CGEventFlags.maskSecondaryFn`. It does **not** appear in the Carbon
`EventHotKeyModifier` bitfield that `RegisterEventHotKey` accepts. There is
no fix at the `KeyboardShortcuts` layer — the limitation is in the OS API
the package wraps.

The lowest-cost path is a Cocoa global monitor:

```swift
NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
    let fnDown = event.modifierFlags.contains(.function)
    ...
}
```

`addGlobalMonitorForEvents` for keyboard events requires the same
Accessibility trust that OpenQuack already requests for paste-at-cursor
(SPEC-005). No new permission, no new entitlement, no `CGEventTap` (which
would additionally trigger an Input Monitoring prompt).

A local monitor (`addLocalMonitorForEvents`) is used in parallel only inside
the recorder UI, so a press while the recorder field is focused captures
even when the global tap is filtered out by another responder.

## Public surface

A new module-private monitor sits behind a shared façade with the existing
manager. Callers do not learn about the split.

```swift
// Sources/OpenQuackKit/Hotkey/FnHotkeyMonitor.swift
final class FnHotkeyMonitor {
    /// Bind a stored fn shortcut (or clear it).
    func setShortcut(_ shortcut: FnShortcut?)
    /// Fires on each fn-down (and on fn+key-down when a key code is bound).
    var onKeyDown: (@MainActor () -> Void)?
    /// Fires on each fn-up. Used for push-to-talk release.
    var onKeyUp:   (@MainActor () -> Void)?
}

struct FnShortcut: Codable, Equatable {
    var keyCode: UInt16?  // nil = bare `fn`
    // No `modifiers`: `fn` cannot be combined with `⌘⌥⌃⇧` reliably (Cocoa
    // exposes them, but the value is keyboard-firmware-dependent). v1 binds
    // either bare `fn` or `fn` + one printable key.
}
```

`HotkeyManager.register(...)` (SPEC-003) gains an internal branch: if the
stored binding is a `FnShortcut`, it drives `FnHotkeyMonitor`; otherwise it
drives `KeyboardShortcuts` as today. From the caller's perspective —
`AppState`'s start-recording / stop-recording closures — nothing changes.

Storage: a separate `UserDefaults` key
(`openquack.toggleRecording.fn`) stored as a JSON-encoded `FnShortcut`.
Mutual exclusion: setting an `fn` shortcut clears the
`KeyboardShortcuts`-side binding, and vice versa. Both keys are read at
startup; if both somehow exist, the `fn` one wins and the other is cleared
(should not happen in practice).

## Picker UX

A new `FnAwareShortcutRecorder` SwiftUI view wraps the existing
`KeyboardShortcuts.Recorder` and, while focused, runs an
`addLocalMonitorForEvents` for `.flagsChanged`. On a `fn`-down event:

1. Consume the event (return `nil` from the local monitor closure so it
   doesn't propagate to the underlying `Recorder`, which would ignore it).
2. If the user releases `fn` within ~600 ms without pressing another key →
   store `FnShortcut(keyCode: nil)` and display "fn 🌐".
3. If the user presses a printable key while `fn` is held → store
   `FnShortcut(keyCode: code)` and display "fn 🌐 + D" (etc).
4. Show a clear-button next to the field, same affordance as today.

Display strings use the actual macOS Globe glyph (`globe` SF Symbol, or the
inline U+1F310 emoji as fallback) so the picker reads "fn 🌐", matching the
key cap.

This view replaces the bare `KeyboardShortcuts.Recorder("Hotkey:", name:
.toggleRecording)` call in two places only:

- `Sources/OpenQuackApp/OnboardingFlow.swift` (`HotkeyStep`)
- `Sources/OpenQuackApp/SettingsView.swift` (Shortcut pane — same wrapper)

## OS-level collision warning

If the user's macOS *System Settings → Keyboard → Press 🌐 to* is set to
anything other than "Do Nothing" (the common one is "Show Emoji & Symbols"
or "Start Dictation"), bare-`fn` as our hotkey will *also* trigger that
system action on every press — annoying but not breaking. We can't read the
user's choice directly without a private API, but we know what the system
defaults are:

After a fresh `fn`-bind, show a one-shot info row under the recorder:

> ℹ️ macOS may also do something when you press 🌐 — check **System
> Settings → Keyboard → Press 🌐 to** and set it to *Do Nothing* if you
> see double behaviour.

Dismissible, shown once per session per binding change.

## Hotkey mode interaction

The two existing `HotkeyMode` values (SPEC-003: `toggle`, `pushToTalk`)
keep their semantics:

- `toggle`: each `fn`-down toggles recording. `fn`-up is ignored.
- `pushToTalk`: `fn`-down starts recording, `fn`-up stops it. This is the
  *whole point* of binding `fn`, so we surface a one-line nudge under the
  mode picker: *"Push-to-talk pairs well with the 🌐 / fn key."*

## Migration

None. Existing users keep their `⌃⇧Space` (or whatever they bound). The
`fn` path is opt-in via the picker. No defaults change.

## Test plan

- **Onboarding picker**: press `fn` → field accepts it and reads "fn 🌐".
  Continue advances. (Reproduces #23 as fixed.)
- **Settings picker**: same.
- **Bare `fn` toggle**: bind `fn`, set mode to toggle, press `fn` → record
  starts; press `fn` → record stops. Verify no recording starts when
  another modifier is held.
- **Bare `fn` PTT**: bind `fn`, set mode to push-to-talk, hold `fn` for 3 s
  while speaking, release → transcript appears.
- **`fn` + key**: bind `fn`+`D`, verify only the combo (not bare `fn`)
  fires the callback.
- **Collision**: with *Press 🌐 to* set to *Show Emoji & Symbols*, confirm
  our hotkey still fires and the warning row appears once.
- **Mutual exclusion**: starting from a `⌃⇧Space` binding, set the picker
  to `fn`; confirm `⌃⇧Space` no longer toggles recording, and vice versa.
- **Permission edge**: revoke Accessibility, restart, confirm `fn` does
  nothing and the existing AX-not-granted banner surfaces (no silent
  failure mode).
- Existing `swift build && swift test` green; no bench delta expected
  (hotkey path is not in the transcription hot path).

## Open questions

- **Should we ship a *Press 🌐 twice* mode for parity with Apple's
  dictation?** Defer to a follow-up — single-press covers the issue and the
  double-tap idiom is a separate UX decision (timing window, conflict with
  any other `fn`-using app).
- **`fn` + arrow / function keys.** Some Mac keyboards already use `fn`
  with the F-row to expose hardware controls (volume, brightness). Binding
  `fn`+`F5` would steal that. v1 disallows binding `fn` together with any
  F-row key (`F1`…`F19`); the picker rejects the combo and shows a
  tooltip.

## PR shape

| PR | Title | SPEC cite | Effort |
|---|---|---|---|
| this | `docs(SPEC-003a): fn / Globe key as a bindable hotkey` | SPEC-003a | XS |
| PR-A | `feat(hotkey): FnHotkeyMonitor + FnAwareShortcutRecorder` | SPEC-003a | M |
| PR-B | `feat(onboarding,settings): swap recorder, surface 🌐-collision warning` | SPEC-003a | S |

PR-A merges before PR-B. PR-A is a no-op from the user's perspective until
PR-B wires the recorder in; that's intentional so the infra change can land
on its own with unit tests for `FnHotkeyMonitor`'s dispatch logic before
any UI is touched.
