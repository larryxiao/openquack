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

    /// Cmd+W → close. The app is `LSUIElement` so there's no application
    /// menu, which means the standard "File → Close" routing for the
    /// shortcut is missing. A local key monitor fills that gap while the
    /// Settings window is the key window.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let window = self?.window, window.isKeyWindow else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .command,
               event.charactersIgnoringModifiers?.lowercased() == "w" {
                window.performClose(nil)
                return nil
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
