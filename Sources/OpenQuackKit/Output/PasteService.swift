import AppKit
import Foundation

/// SPEC-005 — Paste at cursor.
///
/// Pasteboard + simulated ⌘V is the standard idiom on macOS for "type this
/// somewhere"; it works in 99 % of apps without Accessibility-tree poking.
/// The simulated keystroke does require Accessibility permission; if missing,
/// `paste` returns false and the caller should fall back to clipboard-only
/// behaviour (the text is already on the pasteboard at that point, so the
/// user can ⌘V manually).
public enum PasteService {
    /// Writes `text` to the system pasteboard and posts a synthetic ⌘V at the
    /// HID event tap so the focused app receives a paste. Restores the previous
    /// pasteboard string after `restoreDelay` so we don't permanently overwrite
    /// the user's clipboard.
    ///
    /// - Returns: `true` if both the pasteboard write and the keystroke succeeded.
    ///   `false` means Accessibility permission is missing — the text is on the
    ///   pasteboard but the user must press ⌘V themselves.
    @discardableResult
    public static func paste(_ text: String, restoreDelay: TimeInterval = 0.6) -> Bool {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        guard isAccessibilityTrusted() else {
            return false
        }

        guard postCommandV() else { return false }

        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                pb.clearContents()
                pb.setString(previous, forType: .string)
            }
        }
        return true
    }

    /// Pasteboard-only — for "Copy" buttons / fallback paths.
    public static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Whether the process has Accessibility permission. `prompt:true` surfaces
    /// the system dialog (and immediately returns the trusted state, which will
    /// usually still be `false` until the user grants).
    @discardableResult
    public static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Open System Settings → Privacy & Security → Accessibility, scrolled to
    /// our entry. Useful for the "permission missing" CTA.
    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - private

    private static func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09  // virtual keycode for "V"
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let up   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
