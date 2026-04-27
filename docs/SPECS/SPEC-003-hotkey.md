# SPEC-003 — Global hotkey

**Status:** ratified — shipped 2026-04-26 (`Sources/OpenQuackKit/Hotkey/HotkeyManager.swift`)
**Owner:** `OpenQuackKit/Hotkey/`
**Last updated:** 2026-04-26

## Goal

A global hotkey toggles recording. While recording, a separate cancel hotkey discards the buffer. Defaults: `⌃⇧Space` (toggle), `Esc` while overlay is focused (cancel).

## Non-goals

- Push-to-talk (hold hotkey) — supported as an option but defaulting to toggle is simpler. Revisit in M3.
- Per-app shortcuts — out of scope for v2.0.

## Public surface

```swift
public extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("openquack.toggleRecording")
    static let cancelRecording = Self("openquack.cancelRecording")
}

public final class HotkeyManager {
    public init()
    public func register(toggle: @escaping () -> Void, cancel: @escaping () -> Void)
    public func unregister()
}
```

Implementation uses `sindresorhus/KeyboardShortcuts` (MIT). The package handles persistence to `UserDefaults`, conflict resolution with system shortcuts, and the SwiftUI `Recorder` UI for Settings.

## Behaviour

- `register(...)` wires `KeyboardShortcuts.onKeyDown(for: .toggleRecording, action: toggle)` etc.
- `toggle` callback fires on key-down (not up). Recording starts on first press, stops on next press.
- `cancel` callback fires only when overlay window is key (don't shadow Esc globally).
- If the user clears the shortcut in Settings, `register` becomes a no-op for that one.

## Permissions

`KeyboardShortcuts` works inside the App Sandbox. No Accessibility permission needed *for the hotkey itself* — but our paste service (SPEC-005) does need Accessibility. Surface the two requirements separately.

## Open questions

- Should we support a "press and hold" mode in addition to toggle? Useful for short utterances; complicates UX. Defer to M3.
- What if the user binds a one-key shortcut (e.g. `F5`)? Allow it, but warn in the Recorder UI.

## References

- KeyboardShortcuts: https://github.com/sindresorhus/KeyboardShortcuts
- voxt uses Carbon's `RegisterEventHotKey`. KeyboardShortcuts is a thin wrapper over the same; no functional difference.
