import XCTest
@testable import OpenQuackKit

final class ChineseScriptTests: XCTestCase {
    func testAutoIsNoOp() {
        let mixed = "今天的軟體更新有点慢"
        XCTAssertEqual(ChineseScriptConverter.convert(mixed, to: .auto), mixed)
    }

    func testTraditionalToSimplified() {
        let trad = "繁體中文軟體與計算機技術"
        let simp = ChineseScriptConverter.convert(trad, to: .simplified)
        XCTAssertEqual(simp, "繁体中文软体与计算机技术")
    }

    func testSimplifiedToTraditional() {
        let simp = "简体中文软件与计算机技术"
        let trad = ChineseScriptConverter.convert(simp, to: .traditional)
        XCTAssertEqual(trad, "簡體中文軟件與計算機技術")
    }

    func testIdempotentSimplified() {
        let already = "已经是简体的句子"
        XCTAssertEqual(
            ChineseScriptConverter.convert(already, to: .simplified),
            already
        )
    }

    func testNonChineseUnchanged() {
        let s = "Hello, world! 123."
        XCTAssertEqual(ChineseScriptConverter.convert(s, to: .simplified), s)
        XCTAssertEqual(ChineseScriptConverter.convert(s, to: .traditional), s)
    }

    func testEmptyString() {
        XCTAssertEqual(ChineseScriptConverter.convert("", to: .simplified), "")
        XCTAssertEqual(ChineseScriptConverter.convert("", to: .traditional), "")
    }
}
