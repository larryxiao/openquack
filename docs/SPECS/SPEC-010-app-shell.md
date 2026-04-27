# SPEC-010 — App shell

**Status:** ratified — task 1 (shell + menu bar + About) shipped 2026-04-26 via SwiftPM target rather than `.xcodeproj` (see implementation note below)
**Owner:** `apps/OpenQuack/`
**Last updated:** 2026-04-26

## Goal

The minimum viable Xcode app target: a menu-bar app that owns the dictation lifecycle, consumes `OpenQuackKit`, and survives long-running sessions without leaks. Boots into a sane idle state on first launch.

## Non-goals

- Settings UI (separate spec, M2 follow-up).
- Onboarding (separate spec, M2 follow-up).
- Code signing / notarisation (M3).

## Surface

- `apps/OpenQuack/OpenQuack.xcodeproj` — hand-written; consumes the local SPM package via "Add Local Package".
- `apps/OpenQuack/Sources/App/OpenQuackApp.swift` — `@main`, sets up `AppDelegate`.
- `apps/OpenQuack/Sources/App/AppDelegate.swift` — `NSApplicationDelegate`, owns the `StatusItemController`, wires `HotkeyManager`, `AudioRecorder`, `Transcriber`, `AgentRouter`, `OverlayController` together.
- `Info.plist`:
  - `LSUIElement = YES` (no Dock icon, just menu bar)
  - `NSMicrophoneUsageDescription` = "OpenQuack transcribes your voice locally to dispatch commands to your AI agent."
  - `NSAppleEventsUsageDescription` (if we end up using AppleScript anywhere)
  - Hardened runtime; entitlements: `com.apple.security.device.audio-input`

## Behaviour

- On launch: register hotkeys, install status item with menu (Pause / Settings / Quit). No window shown.
- Hotkey toggle:
  ```
  start recording → overlay.recording → audio.start
                        ⋮
  stop hotkey   → audio.stop → overlay.transcribing → transcribe → overlay.dispatching → agent.dispatch → result
                                                                                              ↓
                                                                                       PasteService.paste
                                                                                              ↓
                                                                                    overlay.done → fade
  ```
- Cancel hotkey: at any pre-dispatch stage, discards the buffer and shows `cancelled` overlay state.

## Quality gates

- Memory growth ≤ 10 MB across 50 dictation cycles (no leaks).
- `xcodebuild -project … build` green in CI on `macos-15` runner.
- App launches and hotkey works headlessly in CI smoke (status-item appears, no crash).

## Implementation note (2026-04-26)

Settled the Xcode-project question by going **SwiftPM-only** for the app target:

- `Sources/OpenQuackApp/` is a SwiftPM `.executable` target consuming `OpenQuackKit`.
- SwiftUI's `MenuBarExtra` + `AppDelegate.applicationDidFinishLaunching → NSApp.setActivationPolicy(.accessory)` gives us a Dock-less menu-bar app.
- `scripts/wrap_app.sh` builds a release binary and assembles a minimal `.app` bundle (Info.plist with `LSUIElement=YES` + `NSMicrophoneUsageDescription`, ad-hoc codesigned). Output at `build/OpenQuack.app`.
- We can graduate to a hand-written `.xcodeproj` if/when a feature needs Xcode-specific tooling (Asset Catalog editor, storyboards, signing UI). None do today.

Trade-off accepted: no SwiftUI Previews from the SwiftPM target (the `#Preview` macro requires the Xcode plugin). That's a per-developer ergonomic loss; for the menu-bar surface, we use the running app to iterate.

## Open questions

- Lazy-load the transcriber (load on first hotkey) vs eager-load on app launch (cold-start hidden behind onboarding "first dictation test"). Lean lazy with a "warming…" overlay state — the warm-cache load is fast enough that the first key-press feels OK.

## References

- voxt's app target — single Xcode project, `LSUIElement` menu-bar pattern.
- `Sources/OpenQuackKit/` — the brain we wrap.
