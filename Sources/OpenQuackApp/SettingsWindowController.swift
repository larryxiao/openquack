import AppKit
import SwiftUI

/// Hosts `SettingsView` in a regular NSWindow. The app target doesn't use
/// SwiftUI's App protocol (Settings scene), so we manage the window manually.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?
    private var keyMonitor: Any?

    static func show(appState: AppState) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Show the Dock icon while the Settings window is up, so the user
        // can re-find it after switching to System Settings or another app.
        NSApp.setActivationPolicy(.regular)

        let view = SettingsView(appState: appState)
        let host = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenQuack Settings"
        window.contentViewController = host
        window.center()
        window.isReleasedWhenClosed = false
        // Don't auto-focus into a text field — TextEditor in the Custom-
        // dictionary section grabs first-responder otherwise, and AppKit
        // then scrolls the form to make it visible (i.e. to the bottom).
        window.initialFirstResponder = nil

        let controller = SettingsWindowController(window: window)
        shared = controller
        window.delegate = controller
        controller.windowDidLoad()
        controller.installKeyMonitor()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The app is `LSUIElement` so there's no application menu — the standard
    /// menu-item key equivalents (Close, and the Edit-menu editing commands)
    /// never reach the key window or its focused text view. A local key monitor
    /// fills that gap while the Settings window is key: ⌘W closes, and the
    /// editing shortcuts are routed to the first responder ourselves so the
    /// text editors support select-all / copy / paste / cut / undo.
    private static let editingShortcuts: [(NSEvent.ModifierFlags, String, Selector)] = [
        (.command, "a", #selector(NSResponder.selectAll(_:))),
        (.command, "c", #selector(NSText.copy(_:))),
        (.command, "v", #selector(NSText.paste(_:))),
        (.command, "x", #selector(NSText.cut(_:))),
        // No Swift declaration to point #selector at; the responder chain's
        // undo manager handles these at runtime.
        (.command, "z", Selector(("undo:"))),
        ([.command, .shift], "z", Selector(("redo:"))),
    ]

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let window = self?.window, window.isKeyWindow else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard let key = event.charactersIgnoringModifiers?.lowercased() else { return event }

            if mods == .command, key == "w" {
                window.performClose(nil)
                return nil
            }

            for (m, k, selector) in Self.editingShortcuts where mods == m && key == k {
                // sendAction returns false when nothing in the responder chain
                // handles it (e.g. focus isn't in a text view) — pass the event
                // through unchanged in that case.
                if NSApp.sendAction(selector, to: nil, from: nil) { return nil }
                break
            }
            return event
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        Self.shared = nil
        DispatchQueue.main.async {
            ActivationPolicy.refresh()
        }
    }
}
