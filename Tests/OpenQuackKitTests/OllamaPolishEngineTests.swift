import XCTest
@testable import OpenQuackKit

final class OllamaPolishEngineTests: XCTestCase {
    func testRequestCarriesCriticalFlags() {
        let req = OllamaPolishEngine.makeRequest(model: "gemma4-textonly:Q4_K_M", raw: "hello world")
        XCTAssertEqual(req.model, "gemma4-textonly:Q4_K_M")
        XCTAssertFalse(req.stream)
        XCTAssertFalse(req.think)        // thinking-mode budget would eat output
        XCTAssertEqual(req.keep_alive, -1) // keep warm across calls
    }

    func testRequestMessagesShape() {
        let req = OllamaPolishEngine.makeRequest(model: "m", raw: "the build is failing")
        XCTAssertEqual(req.messages.count, 2)
        XCTAssertEqual(req.messages.first?.role, "system")
        XCTAssertEqual(req.messages.last?.role, "user")
        XCTAssertTrue(req.messages.last!.content.contains("the build is failing"))
        XCTAssertTrue(req.messages.last!.content.contains("<<<END>>>"))
    }

    func testRequestOptions() {
        let req = OllamaPolishEngine.makeRequest(model: "m", raw: "hi")
        XCTAssertEqual(req.options.temperature, 0.2, accuracy: 0.0001)
        XCTAssertEqual(req.options.num_predict, 80) // floor for tiny input
    }

    func testModelLabel() {
        let engine = OllamaPolishEngine(model: "gemma4-textonly:Q4_K_M")
        XCTAssertEqual(engine.modelLabel, "gemma4-textonly:Q4_K_M")
    }
}
