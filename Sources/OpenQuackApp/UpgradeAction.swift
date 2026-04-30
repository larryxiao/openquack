import AppKit
import OpenQuackKit

/// One-click upgrade flow used by both the popover update banner and
/// the Settings → About status line. Picks the smoothest path that
/// matches how OpenQuack got onto this Mac.
enum UpgradeAction {
    static func run(release: UpdateChecker.ReleaseInfo, installMethod: InstallMethod) {
        switch installMethod {
        case .homebrew:
            runBrewUpgrade()
        case .manual:
            // Browser handles download → mount → drag for DMG users.
            // The DMG asset URL is the most direct path; fall back to
            // the release page if no asset is attached.
            NSWorkspace.shared.open(release.dmgURL ?? release.pageURL)
        }
    }

    /// Tries to make Terminal run `brew upgrade --cask openquack`
    /// directly. Falls back to clipboard + plain Terminal launch if
    /// the AppleScript path is denied (the user hasn't granted
    /// Automation permission for OpenQuack → Terminal yet).
    private static func runBrewUpgrade() {
        let cmd = "brew upgrade --cask openquack"

        // Always populate the clipboard first — guarantees that even
        // if AppleScript fails, the user can ⌘V + ⏎ without retyping.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)

        let script = """
        tell application "Terminal"
            activate
            do script "\(cmd)"
        end tell
        """
        var error: NSDictionary?
        if let apple = NSAppleScript(source: script) {
            apple.executeAndReturnError(&error)
        }

        // If AppleScript failed (typically the first run before
        // Automation permission is granted), at least bring Terminal
        // forward so the user can paste.
        if error != nil,
           let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.open(terminal)
        }
    }
}
