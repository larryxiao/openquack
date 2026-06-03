import XCTest
@testable import OpenQuackKit

final class LlamaCppPolishEngineTests: XCTestCase {
    private let ctx = PolishContext(language: "en", timestamp: Date(timeIntervalSince1970: 0))

    func testModelLabelIsFilename() {
        let engine = LlamaCppPolishEngine(modelPath: URL(fileURLWithPath: "/models/gemma-e2b.gguf"))
        XCTAssertEqual(engine.modelLabel, "gemma-e2b.gguf")
    }

    func testMissingModelThrows() async {
        let engine = LlamaCppPolishEngine(
            modelPath: URL(fileURLWithPath: "/tmp/openquack-no-such-model-\(UUID().uuidString).gguf"))
        do {
            _ = try await engine.polish("hello there", context: ctx)
            XCTFail("expected polish to throw when the GGUF is absent")
        } catch {
            // expected — PolishPipeline relies on this to fall back to regex.
        }
    }

    func testMissingModelFallsBackInPipeline() async {
        let engine = LlamaCppPolishEngine(
            modelPath: URL(fileURLWithPath: "/tmp/openquack-no-such-model-\(UUID().uuidString).gguf"))
        let r = await PolishPipeline.polish("um hello", engine: engine, regexEnabled: true, context: ctx)
        XCTAssertEqual(r.text, TextPolisher.polish("um hello"))
        XCTAssertTrue(r.llmRan)
        XCTAssertFalse(r.llmSucceeded)
    }
}
