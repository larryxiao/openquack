import XCTest
@testable import OpenQuackKit

final class OllamaPolishEngineTests: XCTestCase {

    // MARK: - Heuristics

    func testWordCountSpaceSeparated() {
        XCTAssertEqual(OllamaPolishEngine.wordCount("hello world"), 2)
        XCTAssertEqual(OllamaPolishEngine.wordCount("  one  two  three  "), 3)
        XCTAssertEqual(OllamaPolishEngine.wordCount(""), 0)
    }

    func testWordCountCJKCharsAsWords() {
        // 4 CJK characters + 2 Latin words
        XCTAssertEqual(OllamaPolishEngine.wordCount("今天 hello 是 world 好天气"), 8)
        // Pure CJK
        XCTAssertEqual(OllamaPolishEngine.wordCount("今天天气好"), 5)
        // Hiragana + katakana
        XCTAssertEqual(OllamaPolishEngine.wordCount("こんにちは"), 5)
    }

    func testNumPredictBounds() {
        XCTAssertEqual(OllamaPolishEngine.numPredict(forWords: 0), 80)   // floor
        XCTAssertEqual(OllamaPolishEngine.numPredict(forWords: 30), 80)  // floor still wins
        XCTAssertEqual(OllamaPolishEngine.numPredict(forWords: 50), 100)
        XCTAssertEqual(OllamaPolishEngine.numPredict(forWords: 600), 1024) // ceil
    }

    func testTemperatureSwitch() {
        XCTAssertEqual(OllamaPolishEngine.temperature(forWords: 10), 0.3)
        XCTAssertEqual(OllamaPolishEngine.temperature(forWords: 50), 0.3) // boundary
        XCTAssertEqual(OllamaPolishEngine.temperature(forWords: 51), 0.5)
        XCTAssertEqual(OllamaPolishEngine.temperature(forWords: 200), 0.5)
    }

    // MARK: - Request shape

    func testEncodeRequestProducesExpectedShape() throws {
        let body = try OllamaPolishEngine.encodeRequest(
            model: "gemma3:1b",
            systemPrompt: "Sys prompt.",
            userText: "raw user text",
            wordCount: 3
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gemma3:1b")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual(json["keep_alive"] as? Int, -1)
        XCTAssertEqual(json["think"] as? Bool, false)

        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "Sys prompt.")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "raw user text")

        let options = try XCTUnwrap(json["options"] as? [String: Any])
        XCTAssertEqual(options["temperature"] as? Double, 0.3)
        XCTAssertEqual(options["num_predict"] as? Int, 80)
    }

    // MARK: - End-to-end via URLProtocol mock

    func testPolishHappyPath() async throws {
        MockURLProtocol.respondWith = { _ in
            let body = #"{"message":{"content":"Polished output."}}"#.data(using: .utf8)!
            return (Self.makeOK(), body, nil)
        }
        let engine = makeEngine()
        let polished = try await engine.polish("um, raw text yeah", context: PolishContext())
        XCTAssertEqual(polished, "Polished output.")
    }

    func testPolishEmptyInputReturnsRawWithoutCallingBackend() async throws {
        MockURLProtocol.respondWith = { _ in
            XCTFail("backend should not be called for empty input")
            return (Self.makeOK(), Data(), nil)
        }
        let engine = makeEngine()
        let result = try await engine.polish("   ", context: PolishContext())
        XCTAssertEqual(result, "   ")
    }

    func testPolishEmptyResponseFallsBackToRaw() async throws {
        MockURLProtocol.respondWith = { _ in
            let body = #"{"message":{"content":""}}"#.data(using: .utf8)!
            return (Self.makeOK(), body, nil)
        }
        let engine = makeEngine()
        let result = try await engine.polish("hello", context: PolishContext())
        XCTAssertEqual(result, "hello")
    }

    func testPolishConnectionRefusedThrowsBackendUnavailable() async {
        MockURLProtocol.respondWith = { _ in
            (Self.makeOK(), nil, URLError(.cannotConnectToHost))
        }
        let engine = makeEngine()
        do {
            _ = try await engine.polish("hello", context: PolishContext())
            XCTFail("expected throw")
        } catch let err as PolishError {
            if case .backendUnavailable = err {} else {
                XCTFail("expected backendUnavailable, got \(err)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testPolishTimeoutThrowsTimeout() async {
        MockURLProtocol.respondWith = { _ in
            (Self.makeOK(), nil, URLError(.timedOut))
        }
        let engine = makeEngine()
        do {
            _ = try await engine.polish("hello", context: PolishContext())
            XCTFail("expected throw")
        } catch PolishError.timeout {
            // expected
        } catch {
            XCTFail("expected .timeout, got \(error)")
        }
    }

    func testPolishModelNotPulledThrowsModelNotLoaded() async {
        MockURLProtocol.respondWith = { _ in
            (Self.makeStatus(404), Data(), nil)
        }
        let engine = makeEngine()
        do {
            _ = try await engine.polish("hello", context: PolishContext())
            XCTFail("expected throw")
        } catch let err as PolishError {
            if case .modelNotLoaded(let label) = err {
                XCTAssertEqual(label, "gemma3:1b")
            } else {
                XCTFail("expected .modelNotLoaded, got \(err)")
            }
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testPolishMalformedJSONThrowsDecodingFailed() async {
        MockURLProtocol.respondWith = { _ in
            (Self.makeOK(), Data("not json".utf8), nil)
        }
        let engine = makeEngine()
        do {
            _ = try await engine.polish("hello", context: PolishContext())
            XCTFail("expected throw")
        } catch PolishError.decodingFailed {
            // expected
        } catch {
            XCTFail("expected .decodingFailed, got \(error)")
        }
    }

    func testPolishRequestPayloadShape() async throws {
        MockURLProtocol.respondWith = { request in
            // Verify the request shape that hit the wire.
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.url?.absoluteString, "http://example.invalid/api/chat")
            // Note: URLProtocol mock loses request.httpBody on iOS/macOS in some
            // configurations; skip body assertion here. See the
            // testEncodeRequestProducesExpectedShape unit for body coverage.
            let body = #"{"message":{"content":"ok"}}"#.data(using: .utf8)!
            return (Self.makeOK(), body, nil)
        }
        let engine = makeEngine()
        _ = try await engine.polish("hello", context: PolishContext())
    }

    // MARK: - Test helpers

    private func makeEngine() -> OllamaPolishEngine {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return OllamaPolishEngine(
            endpoint: URL(string: "http://example.invalid/api/chat")!,
            model: "gemma3:1b",
            urlSession: session,
            timeoutSeconds: 1
        )
    }

    private static func makeOK() -> HTTPURLResponse {
        makeStatus(200)
    }

    private static func makeStatus(_ code: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "http://example.invalid/api/chat")!,
            statusCode: code,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }
}

/// URLProtocol mock — registers via `URLSessionConfiguration.protocolClasses`
/// so each test instance has its own intercepted session.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var respondWith: ((URLRequest) -> (HTTPURLResponse, Data?, Error?))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = MockURLProtocol.respondWith else {
            fatalError("MockURLProtocol.respondWith not set")
        }
        let (response, data, error) = responder(request)
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
