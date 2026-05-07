import XCTest
@testable import OpenQuackKit

final class PolishPipelineTests: XCTestCase {

    // MARK: - makeEngine

    func testMakeEngineOffReturnsNil() {
        let engine = PolishPipeline.makeEngine(
            kind: .off,
            ollamaURL: URL(string: "http://localhost:11434/api/chat")!,
            ollamaModel: "gemma3:1b"
        )
        XCTAssertNil(engine)
    }

    func testMakeEngineOllamaWithModelReturnsEngine() {
        let engine = PolishPipeline.makeEngine(
            kind: .ollama,
            ollamaURL: URL(string: "http://localhost:11434/api/chat")!,
            ollamaModel: "gemma3:1b"
        )
        XCTAssertNotNil(engine)
        XCTAssertEqual(type(of: engine!).engineName, "ollama")
    }

    func testMakeEngineOllamaWithEmptyModelReturnsNil() {
        let engine = PolishPipeline.makeEngine(
            kind: .ollama,
            ollamaURL: URL(string: "http://localhost:11434/api/chat")!,
            ollamaModel: ""
        )
        XCTAssertNil(engine, "empty model should be treated as off")
    }

    func testMakeEngineOllamaWithWhitespaceModelReturnsNil() {
        let engine = PolishPipeline.makeEngine(
            kind: .ollama,
            ollamaURL: URL(string: "http://localhost:11434/api/chat")!,
            ollamaModel: "   "
        )
        XCTAssertNil(engine)
    }

    func testMakeEngineMlxLMReturnsNilUntilPR5() {
        let engine = PolishPipeline.makeEngine(
            kind: .mlxLM,
            ollamaURL: URL(string: "http://localhost:11434/api/chat")!,
            ollamaModel: "qwen2.5:1.5b-instruct"
        )
        XCTAssertNil(engine, "MLX-LM engine lands in SPEC-007 PR #5; until then, .mlxLM is a no-op")
    }

    // MARK: - applyLLMPolish

    func testApplyLLMPolishWithNilEngineReturnsRaw() async {
        let result = await PolishPipeline.applyLLMPolish(
            "raw text",
            engine: nil,
            context: PolishContext()
        )
        XCTAssertEqual(result, "raw text")
    }

    func testApplyLLMPolishWithSucceedingEngineReturnsEngineOutput() async {
        final class StubEngine: TextPolishEngine {
            static let engineName = "stub-ok"
            let requiresNetwork = false
            let modelLabel = "stub"
            func polish(_ raw: String, context: PolishContext) async throws -> String {
                "polished: " + raw
            }
        }
        let result = await PolishPipeline.applyLLMPolish(
            "raw text",
            engine: StubEngine(),
            context: PolishContext()
        )
        XCTAssertEqual(result, "polished: raw text")
    }

    func testApplyLLMPolishWithThrowingEngineReturnsRaw() async {
        final class ThrowingEngine: TextPolishEngine {
            static let engineName = "stub-throws"
            let requiresNetwork = false
            let modelLabel = "stub"
            func polish(_ raw: String, context: PolishContext) async throws -> String {
                throw PolishError.timeout
            }
        }
        let result = await PolishPipeline.applyLLMPolish(
            "raw text",
            engine: ThrowingEngine(),
            context: PolishContext()
        )
        XCTAssertEqual(result, "raw text", "engine throw must fall back to raw")
    }

    // MARK: - isLoopback (URL validation for the Settings UI)

    func testIsLoopbackAcceptsCanonicalForms() {
        XCTAssertTrue(PolishPipeline.isLoopback("http://localhost:11434/api/chat"))
        XCTAssertTrue(PolishPipeline.isLoopback("http://127.0.0.1:11434/api/chat"))
        XCTAssertTrue(PolishPipeline.isLoopback("http://[::1]:11434/api/chat"))
        XCTAssertTrue(PolishPipeline.isLoopback("https://localhost/api/chat"))
    }

    func testIsLoopbackCaseInsensitive() {
        XCTAssertTrue(PolishPipeline.isLoopback("http://LOCALHOST:11434/api/chat"))
        XCTAssertTrue(PolishPipeline.isLoopback("http://LocalHost:11434/api/chat"))
    }

    func testIsLoopbackRejectsLANIPs() {
        XCTAssertFalse(PolishPipeline.isLoopback("http://192.168.1.5:11434/api/chat"),
                       "LAN IPs leak transcript to other machines on the network")
        XCTAssertFalse(PolishPipeline.isLoopback("http://10.0.0.1:11434/api/chat"))
        XCTAssertFalse(PolishPipeline.isLoopback("http://172.16.0.1:11434/api/chat"))
    }

    func testIsLoopbackRejectsPublicHosts() {
        XCTAssertFalse(PolishPipeline.isLoopback("https://api.openai.com/v1/chat/completions"))
        XCTAssertFalse(PolishPipeline.isLoopback("http://example.com:11434/api/chat"))
    }

    func testIsLoopbackRejectsMalformedURLs() {
        XCTAssertFalse(PolishPipeline.isLoopback("not a url"))
        XCTAssertFalse(PolishPipeline.isLoopback(""))
        // Schemeless host doesn't parse as a host with URL(string:) — must reject.
        XCTAssertFalse(PolishPipeline.isLoopback("localhost:11434"))
    }

    func testApplyLLMPolishPassesContextToEngine() async {
        final class CapturingEngine: TextPolishEngine, @unchecked Sendable {
            static let engineName = "stub-capture"
            let requiresNetwork = false
            let modelLabel = "stub"
            var capturedContext: PolishContext?
            func polish(_ raw: String, context: PolishContext) async throws -> String {
                capturedContext = context
                return raw
            }
        }
        let engine = CapturingEngine()
        let ctx = PolishContext(language: "en", foregroundApp: "Cursor")
        _ = await PolishPipeline.applyLLMPolish("hello", engine: engine, context: ctx)
        XCTAssertEqual(engine.capturedContext?.language, "en")
        XCTAssertEqual(engine.capturedContext?.foregroundApp, "Cursor")
    }
}
