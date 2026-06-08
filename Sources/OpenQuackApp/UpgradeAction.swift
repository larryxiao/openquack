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
    ///   1. waits for *this* process to exit, so brew never tries to swap a
    ///      live bundle (the old "quit + race brew" timing risked
    ///      mid-upgrade corruption / a brew "app is running" abort).
    ///   2. runs `brew upgrade --cask openquack`
    ///   3. strips `com.apple.quarantine` from the new bundle as insurance.
    ///      Originally suspected as the cure (un-notarised app re-quarantined
    ///      by brew → Gatekeeper blocks a headless `open`) — but a live
    ///      alpha.17→alpha.18 upgrade DISPROVED that: the new bundle is
    ///      `spctl`-rejected yet launches fine unstripped, because brew writes
    ///      a launchable quarantine. Kept as cheap defence against quarantine-
    ///      flag variance across brew versions; brew already verified the DMG
    ///      against the cask's pinned sha256. Notarisation (SPEC-025) is a
    ///      separate goal and would NOT have fixed this bug.
    ///   4. relaunches — by full path first (the exact bundle brew installed),
    ///      then bundle id, then name; robust against the LaunchServices races
    ///      a brew swap can introduce, and always runs so the duck comes back
    ///      even if brew exits non-zero.
    ///   5. removes itself.
    ///
    /// The actual cure for "quits and never comes back" is (1) + (4): the old
    /// script ran `brew upgrade` *while the app was still alive* (it quit on a
    /// fixed 1.5 s timer) and relaunched by name with all output discarded.
    ///
    /// Everything is logged to `~/Library/Logs/OpenQuack/upgrade.log` so a
    /// failed self-upgrade is diagnosable instead of silently vanishing (the
    /// previous script discarded all output).
    ///
    /// PATH is set explicitly because GUI-launched processes inherit a sparse
    /// PATH (/usr/bin:/bin:…) that omits /opt/homebrew/bin; brew itself needs
    /// curl, git, and gpg from the brew prefix.
    private static func runBrewUpgrade(prefix: String, release: UpdateChecker.ReleaseInfo, appState: AppState) {
        let brewPath = "\(prefix)/bin/brew"
        // Resolve the running bundle once, on the main side — after brew
        // swaps it the path is stable (brew reinstalls to the same location)
        // but `Bundle.main` inside a detached shell isn't available to us.
        let appPath = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier

        // Write a temp script. UUID prefix keeps the name unique so
        // concurrent invocations (unlikely but possible) don't collide.
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openquack-upgrade-\(UUID().uuidString.prefix(8)).sh")
        let scriptContent = """
        #!/bin/bash
        APP="\(appPath)"
        LOGDIR="$HOME/Library/Logs/OpenQuack"
        mkdir -p "$LOGDIR"
        exec >>"$LOGDIR/upgrade.log" 2>&1
        echo "=== $(date) brew upgrade --cask openquack (app pid \(pid)) ==="

        # Wait for OpenQuack to exit before brew touches the bundle (max ~10s).
        for (( i = 0; i < 50; i++ )); do
            kill -0 \(pid) 2>/dev/null || break
            sleep 0.2
        done

        "\(brewPath)" upgrade --cask openquack
        echo "brew exit: $?"

        # Insurance only: a live upgrade showed brew's quarantine is launchable
        # even un-notarised, but strip it so quarantine-flag variance can't
        # block the relaunch. (Notarisation, SPEC-025, is unrelated to this bug.)
        xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

        # Path first — the exact bundle brew just installed — then bundle id,
        # then name, so a stale/ambiguous LaunchServices entry can't misfire.
        open "$APP" || open -b org.openquack.OpenQuack || open -a OpenQuack
        echo "relaunch rc: $?"

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
