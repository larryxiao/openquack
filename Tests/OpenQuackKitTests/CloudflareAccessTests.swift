import AVFoundation
import XCTest
@testable import OpenQuackKit

final class CloudflareAccessTests: XCTestCase {

    /// Unsigned but structurally valid JWT with the given expiry.
    private func makeJWT(exp: TimeInterval, payloadExtras: [String: Any] = [:]) -> String {
        func b64url(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        var payload: [String: Any] = ["exp": exp, "aud": "test"]
        payload.merge(payloadExtras) { a, _ in a }
        return "\(b64url(["alg": "RS256", "typ": "JWT"])).\(b64url(payload)).fakesig"
    }

    // MARK: expiry / usability parsing

    func testExpiryParsing() {
        let exp = Date().addingTimeInterval(3600).timeIntervalSince1970
        let date = CloudflareAccessClient.expiry(of: makeJWT(exp: exp))
        XCTAssertNotNil(date)
        XCTAssertEqual(date!.timeIntervalSince1970, exp, accuracy: 1)
    }

    func testExpiryPaddingVariants() {
        // Different payload lengths force each base64url padding case.
        for extra in ["a", "ab", "abc", "abcd"] {
            let jwt = makeJWT(exp: 1_900_000_000, payloadExtras: ["pad": extra])
            XCTAssertNotNil(CloudflareAccessClient.expiry(of: jwt), "padding variant \(extra) failed")
        }
    }

    func testMalformedTokensRejected() {
        XCTAssertNil(CloudflareAccessClient.expiry(of: "not-a-jwt"))
        XCTAssertNil(CloudflareAccessClient.expiry(of: "ey.only.two.dots.everywhere"))
        XCTAssertNil(CloudflareAccessClient.expiry(of: "ey!!!.ey!!!.sig"))
        XCTAssertFalse(CloudflareAccessClient.isUsable("garbage"))
    }

    func testUsabilityLeeway() {
        XCTAssertTrue(CloudflareAccessClient.isUsable(makeJWT(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)))
        // Inside the 60 s leeway → unusable even though not yet expired.
        XCTAssertFalse(CloudflareAccessClient.isUsable(makeJWT(exp: Date().addingTimeInterval(30).timeIntervalSince1970)))
        XCTAssertFalse(CloudflareAccessClient.isUsable(makeJWT(exp: Date().addingTimeInterval(-10).timeIntervalSince1970)))
    }

    // MARK: engine integration

    private func makeEngine(store: InMemoryCredentialStore) -> RemoteEngine {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [RemoteStubURLProtocol.self]
        return RemoteEngine(
            profile: RemoteProfile(
                baseURL: URL(string: "https://stt.corp.example/v1")!,
                model: "m",
                auth: .cloudflareAccess
            ),
            credentials: store,
            session: URLSession(configuration: cfg)
        )
    }

    private func makeWAV() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oq-cf-test-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let file = try! AVAudioFile(forWriting: url, settings: settings)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
        buf.frameLength = 1600
        try! file.write(from: buf)
        return url
    }

    func testValidJWTAttachedAsCFAccessTokenHeader() async throws {
        RemoteStubURLProtocol.reset()
        let jwt = makeJWT(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)
        let store = InMemoryCredentialStore(["stt.corp.example": jwt])
        let wav = makeWAV()
        defer { try? FileManager.default.removeItem(at: wav) }

        _ = try await makeEngine(store: store).transcribe(audioFile: wav, language: nil)

        let request = try XCTUnwrap(RemoteStubURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "cf-access-token"), jwt)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testExpiredJWTRefusedBeforeNetwork() async {
        RemoteStubURLProtocol.reset()
        let store = InMemoryCredentialStore(
            ["stt.corp.example": makeJWT(exp: Date().addingTimeInterval(-60).timeIntervalSince1970)]
        )
        let wav = makeWAV()
        defer { try? FileManager.default.removeItem(at: wav) }

        do {
            _ = try await makeEngine(store: store).transcribe(audioFile: wav, language: nil)
            XCTFail("expected expired-session error")
        } catch {
            XCTAssertTrue("\(error)".contains("expired"))
        }
        XCTAssertNil(RemoteStubURLProtocol.lastRequest, "an expired token must never be sent")
    }

    func testMissingJWTRefusedBeforeNetwork() async {
        RemoteStubURLProtocol.reset()
        let wav = makeWAV()
        defer { try? FileManager.default.removeItem(at: wav) }

        do {
            _ = try await makeEngine(store: InMemoryCredentialStore()).transcribe(audioFile: wav, language: nil)
            XCTFail("expected not-signed-in error")
        } catch {
            XCTAssertTrue("\(error)".contains("sign in"))
        }
        XCTAssertNil(RemoteStubURLProtocol.lastRequest)
    }

    func testJWTShapeValidation() {
        XCTAssertTrue(CloudflareAccessClient.isJWTShaped(makeJWT(exp: 1_900_000_000)))
        XCTAssertFalse(CloudflareAccessClient.isJWTShaped("token-without-dots"))
        XCTAssertFalse(CloudflareAccessClient.isJWTShaped("a.b.c"))   // no "ey" prefix
    }
}
