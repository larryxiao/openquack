import Foundation
import KeyboardShortcuts

/// SPEC-003 — Global hotkey, backed by sindresorhus/KeyboardShortcuts.
public extension KeyboardShortcuts.Name {
    /// Default: ⌃⇧Space. User-overridable via `KeyboardShortcuts.Recorder` once
    /// the Settings scene lands.
    static let toggleRecording = Self(
        "openquack.toggleRecording",
        default: .init(.space, modifiers: [.control, .shift])
    )
}

public enum HotkeyMode: String, Sendable, CaseIterable {
    /// Press to start; press again to stop.
    case toggle
    /// Hold to record; release to transcribe. Better for short utterances.
    case pushToTalk
}

public final class HotkeyManager {
    public init() {}

    /// Register both keyDown and keyUp handlers. The caller dispatches based
    /// on its current `HotkeyMode` (read at handler-call time so a Settings
    /// change takes effect immediately, no re-register needed).
    public func register(
        onKeyDown: @escaping @MainActor () -> Void,
        onKeyUp:   @escaping @MainActor () -> Void
    ) {
        KeyboardShortcuts.removeAllHandlers()
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) {
            Task { @MainActor in onKeyDown() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) {
            Task { @MainActor in onKeyUp() }
        }
    }

    /// Single-handler convenience — kept for any caller that only cares about
    /// toggle-on-press. Equivalent to `register(onKeyDown: action, onKeyUp: {})`.
    public func registerToggle(_ action: @escaping @MainActor () -> Void) {
        register(onKeyDown: action, onKeyUp: {})
    }

    public func unregister() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
