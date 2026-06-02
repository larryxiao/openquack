import XCTest
@testable import OpenQuackKit

final class PolishPromptTests: XCTestCase {
    func testEstimateWordsEnglish() {
        XCTAssertEqual(PolishPrompt.estimateWords("the build is failing"), 4)
    }

    func testEstimateWordsCJK() {
        // No whitespace → split yields 1 chunk; 4 hanzi → +4. Sizing heuristic
        // (ported from the bench) intentionally over-counts mixed CJK.
        XCTAssertEqual(PolishPrompt.estimateWords("我们应该"), 5)
    }

    func testNumPredictFloorIs80() {
        XCTAssertEqual(PolishPrompt.numPredict("hi"), 80)
    }

    func testNumPredictScalesWithWords() {
        let hundred = String(repeating: "x ", count: 100)
        XCTAssertEqual(PolishPrompt.numPredict(hundred), 200)
    }

    func testNumPredictCappedAt1024() {
        let sixHundred = String(repeating: "x ", count: 600)
        XCTAssertEqual(PolishPrompt.numPredict(sixHundred), 1024)
    }

    func testTemperatureIsConservative() {
        XCTAssertEqual(PolishPrompt.temperature, 0.2, accuracy: 0.0001)
    }

    func testSystemPromptForbidsTranslationAndCommentary() {
        XCTAssertTrue(PolishPrompt.system.contains("never change the words"))
        XCTAssertTrue(PolishPrompt.system.contains("Translate"))
    }
}
