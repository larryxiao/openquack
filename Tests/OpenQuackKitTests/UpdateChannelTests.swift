import XCTest
@testable import OpenQuackKit

// SPEC-026 — covers `chooseAppcastURL` across all three channels.
// Pure function, no Sparkle mocking (mirrors `LaunchAtLoginTests`).

final class UpdateChannelTests: XCTestCase {

    func testStableMapsToAppcastXML() {
        XCTAssertEqual(
            chooseAppcastURL(channel: .stable).absoluteString,
            "https://larryxiao.github.io/openquack/appcast.xml"
        )
    }

    func testBetaMapsToAppcastBetaXML() {
        XCTAssertEqual(
            chooseAppcastURL(channel: .beta).absoluteString,
            "https://larryxiao.github.io/openquack/appcast-beta.xml"
        )
    }

    func testAlphaMapsToAppcastAlphaXML() {
        XCTAssertEqual(
            chooseAppcastURL(channel: .alpha).absoluteString,
            "https://larryxiao.github.io/openquack/appcast-alpha.xml"
        )
    }

    /// Belt-and-braces: every channel resolves to a non-nil HTTPS URL on
    /// the same host. Catches the case where someone adds a new case
    /// without extending the mapping.
    func testAllChannelsResolveToHTTPSOnSameHost() {
        for channel in UpdateChannel.allCases {
            let url = chooseAppcastURL(channel: channel)
            XCTAssertEqual(url.scheme, "https", "\(channel)")
            XCTAssertEqual(url.host, "larryxiao.github.io", "\(channel)")
        }
    }

    // MARK: - defaultReceivePrereleases (SPEC-026 PR-B)

    func testDefaultReceivePrereleases_alphaBuild_unset_isTrue() {
        XCTAssertTrue(
            defaultReceivePrereleases(version: "2.0.0-alpha.12", persistedValue: nil)
        )
    }

    func testDefaultReceivePrereleases_betaBuild_unset_isTrue() {
        XCTAssertTrue(
            defaultReceivePrereleases(version: "2.0.0-beta.1", persistedValue: nil)
        )
    }

    func testDefaultReceivePrereleases_stableBuild_unset_isFalse() {
        XCTAssertFalse(
            defaultReceivePrereleases(version: "2.0.0", persistedValue: nil)
        )
    }

    /// Persisted choice MUST win over the alpha-build default, otherwise
    /// users who opted out on an alpha would silently get re-opted-in.
    func testDefaultReceivePrereleases_alphaBuild_userOptedOut_isFalse() {
        XCTAssertFalse(
            defaultReceivePrereleases(version: "2.0.0-alpha.12", persistedValue: false)
        )
    }

    /// Persisted choice MUST win over the stable-build default, otherwise
    /// users who opted in on a stable build would silently get reverted.
    func testDefaultReceivePrereleases_stableBuild_userOptedIn_isTrue() {
        XCTAssertTrue(
            defaultReceivePrereleases(version: "2.0.0", persistedValue: true)
        )
    }
}
