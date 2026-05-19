import Foundation
import Sparkle
import OpenQuackKit

// MARK: - SPEC-026 PR-B — Sparkle channel selection via delegate

extension AppDelegate: SPUUpdaterDelegate {
    /// Called by Sparkle on every update check. Returns the appcast URL
    /// for the user's currently selected channel.
    ///
    /// Implemented via the delegate callback (rather than mutating
    /// `SPUUpdater.feedURL` directly) because `SPUUpdater.feedURL` is
    /// read-only in Sparkle 2.x and `-setFeedURL:` is deprecated in
    /// favor of this callback. See `SPUUpdater.h:278-299`.
    func feedURLString(for updater: SPUUpdater) -> String? {
        let channel: UpdateChannel =
            UserDefaults.standard.bool(forKey: "receivePrereleases")
                ? .alpha
                : .stable
        return chooseAppcastURL(channel: channel).absoluteString
    }
}
