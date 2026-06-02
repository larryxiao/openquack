import XCTest
@testable import OpenQuackKit

private struct StubEngine: TextPolishEngine {
    let modelLabel = "stub"
    let outcome: Result<String, Error>
    func polish(_ raw: String, context: PolishContext) async throws -> String {
        try outcome.get()
    }
}

private struct StubError: Error {}

final class PolishPipelineTests: XCTestCase {
    private let ctx = PolishContext(language: "en", timestamp: Date(timeIntervalSince1970: 0))

    func testEngineFailureFallsBackToRegexOnRaw() async {
        let engine = StubEngine(outcome: .failure(StubError()))
        let r = await PolishPipeline.polish("um hello", engine: engine, regexEnabled: true, context: ctx)
        XCTAssertEqual(r.text, TextPolisher.polish("um hello"))
        XCTAssertTrue(r.llmRan)
        XCTAssertFalse(r.llmSucceeded)
    }

    func testEngineSuccessThenRegex() async {
        let engine = StubEngine(outcome: .success("the build is failing"))
        let r = await PolishPipeline.polish("raw input", engine: engine, regexEnabled: true, context: ctx)
        XCTAssertEqual(r.text, TextPolisher.polish("the build is failing"))
        XCTAssertTrue(r.llmRan)
        XCTAssertTrue(r.llmSucceeded)
        XCTAssertNotNil(r.llmMillis)
    }

    func testEngineSuccessRegexDisabledIsVerbatim() async {
        let engine = StubEngine(outcome: .success("exact LLM output"))
        let r = await PolishPipeline.polish("raw", engine: engine, regexEnabled: false, context: ctx)
        XCTAssertEqual(r.text, "exact LLM output")
    }

    func testEngineFailureRegexDisabledIsRaw() async {
        let engine = StubEngine(outcome: .failure(StubError()))
        let r = await PolishPipeline.polish("um hello", engine: engine, regexEnabled: false, context: ctx)
        XCTAssertEqual(r.text, "um hello")
        XCTAssertTrue(r.llmRan)
        XCTAssertFalse(r.llmSucceeded)
    }

    func testNilEngineRegexOnly() async {
        let r = await PolishPipeline.polish("um hello", engine: nil, regexEnabled: true, context: ctx)
        XCTAssertEqual(r.text, TextPolisher.polish("um hello"))
        XCTAssertFalse(r.llmRan)
        XCTAssertNil(r.llmMillis)
    }

    func testNilEngineRegexDisabledIsRaw() async {
        let r = await PolishPipeline.polish("um hello", engine: nil, regexEnabled: false, context: ctx)
        XCTAssertEqual(r.text, "um hello")
        XCTAssertFalse(r.llmRan)
    }
}
