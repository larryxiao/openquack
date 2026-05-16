import Foundation

// SPEC-026 — Multi-channel appcast selection.
//
// Pure mapping from a logical channel to the GitHub-Pages-hosted appcast
// URL. Lives in OpenQuackKit so the function is unit-testable without a
// Sparkle import (kit stays Sparkle-free per SPEC-026 §Technical approach).
// The Settings toggle (PR-B) wires this to `SPUUpdater.feedURL`; PR-A
// lands the function but doesn't call it yet — the Info.plist still
// hardcodes `SUFeedURL` to the stable channel.

public enum UpdateChannel: String, Sendable, Equatable, CaseIterable {
    /// Stable releases only — non-prerelease tags.
    case stable
    /// Beta releases. Reserved for the future stable/beta split; the
    /// Settings UI in PR-B exposes only a binary stable↔alpha toggle.
    /// The `.beta` case exists so PR-C's release script can emit
    /// `appcast-beta.xml` against the same mapping later.
    case beta
    /// Alpha / prerelease feed — carries every release.
    case alpha
}

/// Maps an `UpdateChannel` to its appcast URL on `larryxiao.github.io`.
/// Force-unwrapping the URLs is safe — they're static literals checked at
/// compile time by the tests; a typo would fail the unit test immediately.
public func chooseAppcastURL(channel: UpdateChannel) -> URL {
    let base = "https://larryxiao.github.io/openquack"
    let filename: String
    switch channel {
    case .stable: filename = "appcast.xml"
    case .beta:   filename = "appcast-beta.xml"
    case .alpha:  filename = "appcast-alpha.xml"
    }
    return URL(string: "\(base)/\(filename)")!
}
