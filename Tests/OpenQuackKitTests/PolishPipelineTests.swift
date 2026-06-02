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
        let result = await PolishPipeline.polish("um hello", engine: engine, regexEnabled: true, context: ctx)
        XCTAssertEqual(result, TextPolisher.polish("um hello"))
    }

    func testEngineSuccessThenRegex() async {
        let engine = StubEngine(outcome: .success("the build is failing"))
        let result = await PolishPipeline.polish("raw input", engine: engine, regexEnabled: true, context: ctx)
        XCTAssertEqual(result, TextPolisher.polish("the build is failing"))
    }

    func testEngineSuccessRegexDisabledIsVerbatim() async {
        let engine = StubEngine(outcome: .success("exact LLM output"))
        let result = await PolishPipeline.polish("raw", engine: engine, regexEnabled: false, context: ctx)
        XCTAssertEqual(result, "exact LLM output")
    }

    func testNilEngineRegexOnly() async {
        let result = await PolishPipeline.polish("um hello", engine: nil, regexEnabled: true, context: ctx)
        XCTAssertEqual(result, TextPolisher.polish("um hello"))
    }

    func testNilEngineRegexDisabledIsRaw() async {
        let result = await PolishPipeline.polish("um hello", engine: nil, regexEnabled: false, context: ctx)
        XCTAssertEqual(result, "um hello")
    }

    func testEngineFailureRegexDisabledIsRaw() async {
        let engine = StubEngine(outcome: .failure(StubError()))
        let result = await PolishPipeline.polish("um hello", engine: engine, regexEnabled: false, context: ctx)
        XCTAssertEqual(result, "um hello")
    }
}
