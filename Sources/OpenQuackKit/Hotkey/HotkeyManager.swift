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

/// Convenience helpers for surfacing the user's current hotkey in copy.
public enum HotkeyDisplay {
    /// Returns the user's bound shortcut as a glyph string ("⌃⇧Space"), or
    /// "your hotkey" if they've cleared it.
    public static var current: String {
        if let fn = FnShortcut.stored {
            return fn.displayLabel
        }
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .toggleRecording) else {
            return "your hotkey"
        }
        let str = "\(shortcut)"
        return str.isEmpty ? "your hotkey" : str
    }
}

public enum HotkeyMode: String, Sendable, CaseIterable {
    /// Press to start; press again to stop.
    case toggle
    /// Hold to record; release to transcribe. Better for short utterances.
    case pushToTalk
}

public final class HotkeyManager {
    private let fnMonitor = FnHotkeyMonitor()

    public init() {}

    /// Register both keyDown and keyUp handlers. The caller dispatches based
    /// on its current `HotkeyMode` (read at handler-call time so a Settings
    /// change takes effect immediately, no re-register needed).
    ///
    /// If `FnShortcut.stored` is set the fn monitor is used; otherwise the
    /// Carbon-backed `KeyboardShortcuts` path handles the binding. Both paths
    /// fire the same `onKeyDown` / `onKeyUp` callbacks.
    public func register(
        onKeyDown: @escaping @MainActor () -> Void,
        onKeyUp:   @escaping @MainActor () -> Void
    ) {
        if let fnShortcut = FnShortcut.stored {
            KeyboardShortcuts.removeAllHandlers()
            // FnHotkeyMonitor callbacks are plain () -> Void; dispatch to
            // @MainActor so the caller's contract is preserved.
            fnMonitor.onKeyDown = { Task { @MainActor in onKeyDown() } }
            fnMonitor.onKeyUp   = { Task { @MainActor in onKeyUp() } }
            fnMonitor.setShortcut(fnShortcut)
        } else {
            fnMonitor.setShortcut(nil)
            KeyboardShortcuts.removeAllHandlers()
            KeyboardShortcuts.onKeyDown(for: .toggleRecording) {
                Task { @MainActor in onKeyDown() }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleRecording) {
                Task { @MainActor in onKeyUp() }
            }
        }
    }

    /// Single-handler convenience — kept for any caller that only cares about
    /// toggle-on-press. Equivalent to `register(onKeyDown: action, onKeyUp: {})`.
    public func registerToggle(_ action: @escaping @MainActor () -> Void) {
        register(onKeyDown: action, onKeyUp: {})
    }

    public func unregister() {
        KeyboardShortcuts.removeAllHandlers()
        fnMonitor.setShortcut(nil)
    }
}
