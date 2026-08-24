import XCTest
@testable import OpenQuackKit

final class DictationFailureTests: XCTestCase {
    private let host = "stt.example"

    /// Unsigned but structurally valid JWT expiring `seconds` from now.
    private func makeJWT(expiresIn seconds: TimeInterval) -> String {
        func b64url(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let payload: [String: Any] = ["exp": Date().addingTimeInterval(seconds).timeIntervalSince1970]
        return "\(b64url(["alg": "RS256", "typ": "JWT"])).\(b64url(payload)).fakesig"
    }

    private func profile(_ auth: RemoteAuth) -> RemoteProfile {
        RemoteProfile(baseURL: URL(string: "https://\(host)/v1")!, model: "", auth: auth)
    }

    func testMessageDropsTheEngineWrapper() {
        let error = EngineError.runtimeFailed("Access session expired — sign in again in Settings → General.")
        XCTAssertEqual(
            DictationFailure.message(for: error),
            "Access session expired — sign in again in Settings → General."
        )
    }

    func testMessageKeepsOnlyTheFirstLine() {
        // A server's error body rides on the second line and may be huge.
        let error = EngineError.runtimeFailed("Remote endpoint returned HTTP 500:\n<html>…body…</html>")
        XCTAssertEqual(DictationFailure.message(for: error), "Remote endpoint returned HTTP 500:")
    }

    func testPreflightPassesWhenNoAuthIsNeeded() {
        XCTAssertNil(DictationFailure.remotePreflightMessage(
            profile: profile(.none), credentials: InMemoryCredentialStore()
        ))
    }

    func testPreflightCatchesMissingAPIKey() {
        let message = DictationFailure.remotePreflightMessage(
            profile: profile(.bearer), credentials: InMemoryCredentialStore()
        )
        XCTAssertEqual(message, "No API key saved for \(host) — enter it in Settings → General.")
        XCTAssertNil(DictationFailure.remotePreflightMessage(
            profile: profile(.bearer), credentials: InMemoryCredentialStore([host: "sk-1"])
        ))
    }

    func testPreflightCatchesMissingAndExpiredAccessSessions() {
        let store = InMemoryCredentialStore()
        XCTAssertEqual(
            DictationFailure.remotePreflightMessage(profile: profile(.cloudflareAccess), credentials: store),
            "Not signed in to \(host) — sign in in Settings → General."
        )

        CloudflareAccessClient.setAccessToken(makeJWT(expiresIn: -60), forHost: host, in: store)
        XCTAssertEqual(
            DictationFailure.remotePreflightMessage(profile: profile(.cloudflareAccess), credentials: store),
            "Access session for \(host) expired — sign in again in Settings → General."
        )

        CloudflareAccessClient.setAccessToken(makeJWT(expiresIn: 3600), forHost: host, in: store)
        XCTAssertNil(DictationFailure.remotePreflightMessage(
            profile: profile(.cloudflareAccess), credentials: store
        ))
    }
}
