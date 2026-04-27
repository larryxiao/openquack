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

public final class HotkeyManager {
    public init() {}

    /// Register a single handler for the toggle-recording hotkey. Calling this
    /// again replaces the previous handler.
    public func registerToggle(_ action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.removeAllHandlers()
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) {
            Task { @MainActor in action() }
        }
    }

    public func unregister() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
