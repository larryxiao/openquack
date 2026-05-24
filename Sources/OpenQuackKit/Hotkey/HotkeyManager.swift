import Foundation
import KeyboardShortcuts

/// SPEC-003 — Global hotkey, backed by sindresorhus/KeyboardShortcuts.
public extension KeyboardShortcuts.Name {
    /// SPEC-003 — Dictation hotkey. Default: ⌃Space (simpler combo for
    /// the more-frequent action). User-overridable via the Settings
    /// recorder.
    static let toggleRecording = Self(
        "openquack.toggleRecording",
        default: .init(.space, modifiers: [.control])
    )

    /// SPEC-031 — Agent kickoff hotkey. Default: ⌃⇧Space (the "shift
    /// up" modifier signals louder/escalated action vs plain
    /// dictation). User-overridable. Distinct binding from dictation
    /// so the two paths never collide.
    static let agentKickoff = Self(
        "openquack.agentKickoff",
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

    /// SPEC-031 — wire the agent-kickoff hotkey. Carbon-only for v1: bare-fn
    /// support for kickoff is a flagged follow-up in the spec's open
    /// questions. Intended to be called once at app launch, AFTER
    /// `register(...)` — the dictation register clears all handlers, so
    /// kickoff is installed second to survive.
    public func registerKickoff(_ action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .agentKickoff) {
            Task { @MainActor in action() }
        }
    }

    public func unregister() {
        KeyboardShortcuts.removeAllHandlers()
        fnMonitor.setShortcut(nil)
    }
}
