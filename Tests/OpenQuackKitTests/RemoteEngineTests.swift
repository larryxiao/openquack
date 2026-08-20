import AVFoundation
import XCTest
@testable import OpenQuackKit

/// Captures the one request the engine sends and serves a canned response.
final class RemoteStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var responseBody = Data(#"{"text": "hello"}"#.utf8)
    nonisolated(unsafe) static var redirectTo: String?
    nonisolated(unsafe) static var requestCount = 0

    static func reset() {
        lastRequest = nil
        lastBody = nil
        status = 200
        responseBody = Data(#"{"text": "hello"}"#.utf8)
        redirectTo = nil
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func stopLoading() {}

    override func startLoading() {
        Self.lastRequest = request
        Self.requestCount += 1
        if let location = Self.redirectTo, Self.requestCount == 1 {
            let redirect = HTTPURLResponse(
                url: request.url!, statusCode: 307, httpVersion: nil,
                headerFields: ["Location": location]
            )!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: location)!), redirectResponse: redirect)
            // If the session's delegate refuses the redirect, the task
            // completes with this 307 and no second request is made.
            client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if let stream = request.httpBodyStream {
            var data = Data()
            stream.open()
            let bufSize = 64 * 1024
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buf.deallocate() }
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: bufSize)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            stream.close()
            Self.lastBody = data
        } else {
            Self.lastBody = request.httpBody
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: String]
    private(set) var requestedHosts: [String] = []

    init(_ secrets: [String: String] = [:]) { self.secrets = secrets }

    func secret(forHost host: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        requestedHosts.append(host)
        return secrets[host]
    }

    func setSecret(_ secret: String?, forHost host: String) {
        lock.lock(); defer { lock.unlock() }
        secrets[host] = secret
    }
}

final class RemoteEngineTests: XCTestCase {
    private var wavURL: URL!

    override func setUp() {
        super.setUp()
        RemoteStubURLProtocol.reset()
        wavURL = Self.makeWAV(seconds: 0.2)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: wavURL)
        super.tearDown()
    }

    private static func makeWAV(seconds: Double, sampleRate: Double = 48_000, channels: AVAudioChannelCount = 2) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oq-remote-test-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let settings: [String: Any] = [
            AVFormatIDKey:             kAudioFormatLinearPCM,
            AVSampleRateKey:           sampleRate,
            AVNumberOfChannelsKey:     channels,
            AVLinearPCMBitDepthKey:    16,
            AVLinearPCMIsFloatKey:     false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try! AVAudioFile(forWriting: url, settings: settings)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        for ch in 0..<Int(channels) {
            let samples = buf.floatChannelData![ch]
            for i in 0..<Int(frames) {
                samples[i] = sinf(2 * .pi * 440 * Float(i) / Float(sampleRate)) * 0.5
            }
        }
        try! file.write(from: buf)
        return url
    }

    private func makeEngine(
        base: String,
        model: String = "whisper-1",
        auth: RemoteAuth = .none,
        userAgent: String = "",
        store: InMemoryCredentialStore = InMemoryCredentialStore()
    ) -> RemoteEngine {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [RemoteStubURLProtocol.self]
        return RemoteEngine(
            profile: RemoteProfile(baseURL: URL(string: base)!, model: model, auth: auth, userAgent: userAgent),
            credentials: store,
            session: URLSession(configuration: cfg)
        )
    }

    func testOpenAIRequestShapeWithBearerAuth() async throws {
        let store = InMemoryCredentialStore(["api.example.com": "sk-test-123"])
        let engine = makeEngine(base: "https://api.example.com/v1", auth: .bearer, store: store)

        let result = try await engine.transcribe(audioFile: wavURL, language: "zh")

        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.audioSeconds, 0.2, accuracy: 0.02)
        let request = try XCTUnwrap(RemoteStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-123")
        let body = try XCTUnwrap(RemoteStubURLProtocol.lastBody)
        let printable = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(printable.contains("name=\"model\"\r\n\r\nwhisper-1"))
        XCTAssertTrue(printable.contains("name=\"language\"\r\n\r\nzh"))
        XCTAssertTrue(printable.contains("name=\"response_format\"\r\n\r\njson"))
        XCTAssertTrue(printable.contains("filename=\"audio.wav\""))
        XCTAssertTrue(printable.contains("RIFF"), "multipart body should embed a WAV payload")
        // The uploaded WAV is the 16 kHz mono re-encode, not the 48 kHz original.
        XCTAssertLessThan(body.count, 20_000)
    }

    func testFullPathEndpointIsNotDoubled() async throws {
        let engine = makeEngine(base: "https://api.example.com/v1/audio/transcriptions")
        _ = try await engine.transcribe(audioFile: wavURL, language: nil)
        XCTAssertEqual(
            RemoteStubURLProtocol.lastRequest?.url?.absoluteString,
            "https://api.example.com/v1/audio/transcriptions"
        )
    }

    func testRequestNeverAdvertisesTheApp() async throws {
        let engine = makeEngine(base: "https://api.example.com/v1")
        _ = try await engine.transcribe(audioFile: wavURL, language: nil)
        let request = try XCTUnwrap(RemoteStubURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), RemoteProfile.defaultUserAgent)
        // Neither headers (UA, multipart boundary) nor body may name the app.
        let headers = (request.allHTTPHeaderFields ?? [:]).map { "\($0.key)=\($0.value)" }.joined()
        XCTAssertFalse(headers.lowercased().contains("quack"))
        let body = try XCTUnwrap(RemoteStubURLProtocol.lastBody)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).lowercased().contains("quack"))
    }

    func testConfiguredUserAgentIsSentFoldedToOneLine() async throws {
        let engine = makeEngine(base: "https://api.example.com/v1", userAgent: " my-client/2.0 \r\nX-Sneaky: 1")
        _ = try await engine.transcribe(audioFile: wavURL, language: nil)
        let request = try XCTUnwrap(RemoteStubURLProtocol.lastRequest)
        let sent = try XCTUnwrap(request.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertTrue(sent.hasPrefix("my-client/2.0"))
        XCTAssertFalse(sent.contains("\r") || sent.contains("\n"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Sneaky"))
    }

    func testCustomHeaderAuth() async throws {
        let store = InMemoryCredentialStore(["gw.corp.example": "token-abc"])
        let engine = makeEngine(base: "https://gw.corp.example/stt", auth: .header(name: "X-Api-Key"), store: store)
        _ = try await engine.transcribe(audioFile: wavURL, language: nil)
        let request = try XCTUnwrap(RemoteStubURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "token-abc")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testCredentialLookupUsesRequestHost() async throws {
        let store = InMemoryCredentialStore(["api.example.com": "sk-test"])
        let engine = makeEngine(base: "https://api.example.com/v1", auth: .bearer, store: store)
        _ = try await engine.transcribe(audioFile: wavURL, language: nil)
        XCTAssertEqual(store.requestedHosts, ["api.example.com"])
    }

    func testMissingCredentialThrowsWithoutSendingRequest() async {
        let engine = makeEngine(base: "https://api.example.com/v1", auth: .bearer)
        do {
            _ = try await engine.transcribe(audioFile: wavURL, language: nil)
            XCTFail("expected missing-credential error")
        } catch {
            XCTAssertTrue("\(error)".contains("No API key saved"))
        }
        XCTAssertNil(RemoteStubURLProtocol.lastRequest, "no request may leave the machine without a credential")
    }

    func testPlainHTTPRejectedForNonLocalhost() async {
        let engine = makeEngine(base: "http://api.example.com/v1")
        do {
            _ = try await engine.transcribe(audioFile: wavURL, language: nil)
            XCTFail("expected https-required error")
        } catch {
            XCTAssertTrue("\(error)".contains("https"))
        }
        XCTAssertNil(RemoteStubURLProtocol.lastRequest)
    }

    func testPlainHTTPAllowedForLocalhost() async throws {
        let engine = makeEngine(base: "http://localhost:8080/v1")
        let result = try await engine.transcribe(audioFile: wavURL, language: nil)
        XCTAssertEqual(result.text, "hello")
    }

    func testNon2xxSurfacesStatusAndDetail() async {
        RemoteStubURLProtocol.status = 401
        RemoteStubURLProtocol.responseBody = Data(#"{"error": "bad key"}"#.utf8)
        let engine = makeEngine(base: "https://api.example.com/v1")
        do {
            _ = try await engine.transcribe(audioFile: wavURL, language: nil)
            XCTFail("expected HTTP error")
        } catch {
            XCTAssertTrue("\(error)".contains("401"))
            XCTAssertTrue("\(error)".contains("bad key"))
        }
    }

    func testRedirectIsRefused() async {
        RemoteStubURLProtocol.redirectTo = "https://evil.example/steal"
        let store = InMemoryCredentialStore(["api.example.com": "sk-test"])
        let engine = makeEngine(base: "https://api.example.com/v1", auth: .bearer, store: store)
        do {
            _ = try await engine.transcribe(audioFile: wavURL, language: nil)
            XCTFail("expected the refused redirect to surface as an HTTP error")
        } catch {
            XCTAssertTrue("\(error)".contains("307"))
        }
        XCTAssertEqual(RemoteStubURLProtocol.requestCount, 1, "audio must never follow a redirect to another host")
    }

    func testUserinfoInURLRejected() async {
        let engine = makeEngine(base: "https://user:tok@api.example.com/v1")
        do {
            _ = try await engine.transcribe(audioFile: wavURL, language: nil)
            XCTFail("expected embedded-credentials rejection")
        } catch {
            XCTAssertTrue("\(error)".contains("embed"))
        }
        XCTAssertNil(RemoteStubURLProtocol.lastRequest)
    }

    func testTrailingSlashVariants() {
        func target(_ s: String) -> String {
            RemoteProfile(baseURL: URL(string: s)!, model: "m", auth: .none).requestURL.absoluteString
        }
        XCTAssertEqual(target("https://h/v1/audio/transcriptions/"), "https://h/v1/audio/transcriptions")
        XCTAssertEqual(target("https://h/v1/"), "https://h/v1/audio/transcriptions")
        XCTAssertEqual(target("https://h"), "https://h/audio/transcriptions")
    }

    func testParseTextFallsBackToPlainBody() throws {
        XCTAssertEqual(try RemoteEngine.parseText(from: Data("  plain text \n".utf8)), "plain text")
        XCTAssertEqual(try RemoteEngine.parseText(from: Data(#"{"text": " hi "}"#.utf8)), "hi")
        XCTAssertThrowsError(try RemoteEngine.parseText(from: Data(#"{"error": "nope"}"#.utf8)))
    }

    func testResamplerProduces16kMonoWAV() throws {
        let source = Self.makeWAV(seconds: 1.0, sampleRate: 48_000, channels: 2)
        defer { try? FileManager.default.removeItem(at: source) }
        let converted = try AudioResampler.wav16kMono(from: source)
        defer { try? FileManager.default.removeItem(at: converted.url) }

        XCTAssertEqual(converted.seconds, 1.0, accuracy: 0.02)
        let file = try AVAudioFile(forReading: converted.url)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        let outSeconds = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertEqual(outSeconds, 1.0, accuracy: 0.05)
    }
}
