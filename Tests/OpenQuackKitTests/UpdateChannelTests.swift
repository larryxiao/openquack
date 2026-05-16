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
}
