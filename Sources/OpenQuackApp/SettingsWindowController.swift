import AppKit
import SwiftUI

/// Hosts `SettingsView` in a regular NSWindow. The app target doesn't use
/// SwiftUI's App protocol (Settings scene), so we manage the window manually.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Show the Dock icon while the Settings window is up, so the user
        // can re-find it after switching to System Settings or another app.
        NSApp.setActivationPolicy(.regular)

        let view = SettingsView()
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

        let controller = SettingsWindowController(window: window)
        shared = controller
        window.delegate = controller
        controller.windowDidLoad()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
        DispatchQueue.main.async {
            ActivationPolicy.refresh()
        }
    }
}
