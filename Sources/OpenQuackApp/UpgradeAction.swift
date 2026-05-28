import AppKit
import Foundation
import OpenQuackKit

/// One-click upgrade flow used by both the popover update banner and
/// the Settings → About status line. Picks the smoothest path that
/// matches how OpenQuack got onto this Mac.
enum UpgradeAction {
    static func run(release: UpdateChecker.ReleaseInfo, installMethod: InstallMethod, appState: AppState) {
        switch installMethod {
        case .homebrew(let prefix):
            runBrewUpgrade(prefix: prefix, release: release, appState: appState)
        case .manual:
            // Browser handles download → mount → drag for DMG users.
            // The DMG asset URL is the most direct path; fall back to
            // the release page if no asset is attached.
            NSWorkspace.shared.open(release.dmgURL ?? release.pageURL)
        }
    }

    /// Writes a self-deleting shell script to /tmp, runs it detached under
    /// /bin/bash (so it outlives this process), then quits the running
    /// instance after 1.5 s. No Terminal window opens.
    ///
    /// The script:
    ///   1. runs `brew upgrade --cask openquack`
    ///   2. always runs `open -a OpenQuack` (semicolon, not &&) so the duck
    ///      comes back even if brew exits non-zero (already up-to-date, etc.)
    ///   3. removes itself
    ///
    /// Quitting before brew swaps the bundle is load-bearing: keeping the
    /// running process alive while brew replaces resources risks opaque
    /// mid-upgrade crashes. The detached script survives the parent exit
    /// (reparented to launchd) and does the relaunch when brew finishes.
    ///
    /// PATH is set explicitly because GUI-launched processes inherit a sparse
    /// PATH (/usr/bin:/bin:…) that omits /opt/homebrew/bin; brew itself needs
    /// curl, git, and gpg from the brew prefix.
    private static func runBrewUpgrade(prefix: String, release: UpdateChecker.ReleaseInfo, appState: AppState) {
        let brewPath = "\(prefix)/bin/brew"

        // Write a temp script. UUID prefix keeps the name unique so
        // concurrent invocations (unlikely but possible) don't collide.
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openquack-upgrade-\(UUID().uuidString.prefix(8)).sh")
        let scriptContent = """
        #!/bin/bash
        "\(brewPath)" upgrade --cask openquack
        open -a OpenQuack
        rm -- "$0"
        """

        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            // Script write failed — restore the available state so the
            // user can retry (or use the clipboard fallback manually).
            appState.updateStatus = .available(release)
            return
        }

        // Explicit PATH so brew can find curl/git/gpg from its own prefix.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(prefix)/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_PREFIX"] = prefix

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.environment = env

        do {
            try process.run()
        } catch {
            // Can't exec /bin/bash — restore available state.
            try? FileManager.default.removeItem(at: scriptURL)
            appState.updateStatus = .available(release)
            return
        }

        // Script is running detached. Transition to .upgrading so the
        // banner shows "Installing…" for the brief moment before we quit.
        appState.updateStatus = .upgrading

        // Quit after 1.5 s — long enough for the banner update to render
        // and give the user a moment to see what's happening before the
        // duck disappears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}
