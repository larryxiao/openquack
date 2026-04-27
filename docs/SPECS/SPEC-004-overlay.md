# SPEC-004 — Recording overlay

**Status:** ratified — shipped 2026-04-27 (`Sources/OpenQuackApp/RecordingOverlay.swift`)
**Owner:** `apps/OpenQuack/Sources/Overlay/` (when the app target lands)
**Last updated:** 2026-04-26

## Goal

Show a small, non-intrusive floating window that surfaces recording state so the user knows when the mic is hot, when the transcription is running, and when the agent is acting. Privacy-critical: the user must always know we're listening.

## Non-goals

- Live waveform during recording — nice-to-have, defer to M3 (level meter is enough for M2).
- A "resizable window with history" — we want a pill, not a panel.
- Showing transcript text in real-time during transcription — defer to streaming spec.

## States

```
RECORDING (red dot + timer + level meter)
   │ stop hotkey
   ▼
TRANSCRIBING (orange spinner + model name)
   │ transcript ready
   ▼
DISPATCHING (purple, only if non-passthrough agent + network indicator)
   │ result returned
   ▼
DONE (green check, fade out 1s)

CANCELLED (grey, fade out 0.6s) — from any state
ERROR (red banner, dismiss after 4s) — from any state
```

## Visual

- Pill-shaped `NSPanel`, ~280 × 56 pt, top-centre of the screen, 24 pt below menu bar.
- `NSWindowLevel.floating`, click-through (mouse events pass through to apps below).
- Visual language: warm cream background, dark slate text/accents, soft 12 pt corners.
- Network-using-agent indicator: small globe icon on the right, **always visible** when the active agent has `requiresNetwork == true`.

## Public surface

```swift
public enum OverlayState: Sendable {
    case hidden
    case recording(seconds: Double, level: Float)
    case transcribing(modelLabel: String)
    case dispatching(agentLabel: String, network: Bool)
    case done(message: String)
    case cancelled
    case error(message: String)
}

@MainActor
public final class OverlayController {
    public init()
    public func transition(to state: OverlayState)
}
```

## Behaviour

- All transitions go through `transition(to:)`. No direct mutation.
- Level meter (`recording.level`) updates at 30 fps; the overlay subscribes to `AudioRecorder.currentLevel` (SPEC-001).
- The overlay window does NOT steal focus. Don't call `makeKeyAndOrderFront`; use `orderFront(nil)`.
- Click-through except on the cancel button area, which acts as cancel.

## Open questions

- Should we render in a SwiftUI `Window` or an `NSPanel` host? `NSPanel` is more controllable (level, click-through). Lean `NSPanel` hosting a SwiftUI view via `NSHostingView`.
- Position customisable (top / bottom / cursor)? Default top-centre per voxt's convention; defer customisation to M3.
- Color tokens — declare these here or in a separate design-tokens spec? Lean separate.

## References

- voxt's overlay window — `NSPanel` based, similar shape.
- the visual language — see `docs/VISION.md` references.
