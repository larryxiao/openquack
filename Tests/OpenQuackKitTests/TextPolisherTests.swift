import XCTest
@testable import OpenQuackKit

final class TextPolisherTests: XCTestCase {
    func testCapitalisesFirstLetter() {
        XCTAssertEqual(TextPolisher.polish("hello world"), "Hello world.")
    }

    func testAddsEndPunctuation() {
        XCTAssertEqual(TextPolisher.polish("Hello world"), "Hello world.")
        XCTAssertEqual(TextPolisher.polish("Hello world!"), "Hello world!")
        XCTAssertEqual(TextPolisher.polish("Hello world?"), "Hello world?")
    }

    func testStripsFillers() {
        // "so" is intentionally NOT stripped — too many legit uses.
        XCTAssertEqual(
            TextPolisher.polish("um I think uh we should ship"),
            "I think we should ship."
        )
    }

    func testKeepsLegitimateConjunctions() {
        // "so", "like", "you know", "I mean" all have legitimate meanings.
        XCTAssertEqual(
            TextPolisher.polish("so we agreed"),
            "So we agreed."
        )
    }

    func testFixesSoloI() {
        XCTAssertEqual(TextPolisher.polish("i think i can"), "I think I can.")
    }

    func testDoesNotMangleContractions() {
        // "i'm" / "i'll" are usually output as "I'm" by Whisper already, but
        // make sure our solo-I rule doesn't break them if they're lowercase.
        let result = TextPolisher.polish("i'm fine")
        XCTAssertEqual(result, "I'm fine.")
    }

    func testCollapsesRepeatedSpaces() {
        XCTAssertEqual(
            TextPolisher.polish("hello    world"),
            "Hello world."
        )
    }

    func testRemovesSpaceBeforePunctuation() {
        XCTAssertEqual(
            TextPolisher.polish("hello , world ."),
            "Hello, world."
        )
    }

    func testCJKEndPunctuation() {
        // Chinese sentence without trailing stop should get 。
        XCTAssertEqual(
            TextPolisher.polish("今天天气真好"),
            "今天天气真好。"
        )
    }

    func testPreservesAlreadyClean() {
        let clean = "Hello world."
        XCTAssertEqual(TextPolisher.polish(clean), clean)
    }

    func testHandlesEmpty() {
        XCTAssertEqual(TextPolisher.polish(""), "")
        XCTAssertEqual(TextPolisher.polish("   "), "")
    }

    func testOffDoesNothing() {
        let raw = "um hello world"
        XCTAssertEqual(TextPolisher.polish(raw, settings: .off), raw)
    }

    // MARK: - SPEC-046 CJK punctuation and spacing

    func testNormalizesHalfWidthCJKPunctuationInContext() {
        let raw = "今天的天气真好, 我们出去散步吧."
        XCTAssertEqual(
            TextPolisher.polish(raw),
            "今天的天气真好，我们出去散步吧。"
        )
    }

    func testNormalizesCJKQuestionAndExclamationMarks() {
        let raw = "请问现在几点了? 已经八点了!"
        XCTAssertEqual(
            TextPolisher.polish(raw),
            "请问现在几点了？已经八点了！"
        )
    }

    func testStripsInterCJKSpaces() {
        let raw = "今天 天气 真好"
        XCTAssertEqual(
            TextPolisher.polish(raw),
            "今天天气真好。"
        )
    }

    func testPreservesEnglishAndDecimalPunctuationInsideCJKSentence() {
        let raw = "版本 3.14 已经发布, 请升级"
        XCTAssertEqual(
            TextPolisher.polish(raw),
            "版本 3.14 已经发布，请升级。"
        )
    }

    func testNormalizesFullWidthPunctuationInPureEnglishContext() {
        let raw = "Hello，world！"
        XCTAssertEqual(
            TextPolisher.polish(raw),
            "Hello,world!"
        )
    }
}
