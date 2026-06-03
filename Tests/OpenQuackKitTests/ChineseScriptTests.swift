import XCTest
@testable import OpenQuackKit

final class ChineseScriptTests: XCTestCase {
    // MARK: convert (ICU transform)

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
        XCTAssertEqual(ChineseScriptConverter.convert(already, to: .simplified), already)
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

    // MARK: resolve (system-language → script). Machine-independent: the
    // input list is supplied, not read from the host locale.

    func testResolveTraditionalLocales() {
        for id in ["zh-Hant", "zh-Hant-TW", "zh-TW", "zh-HK", "zh-MO"] {
            XCTAssertEqual(
                ChineseScript.resolve(preferredLanguages: [id]), .traditional,
                "\(id) should resolve Traditional"
            )
        }
    }

    func testResolveSimplifiedLocales() {
        for id in ["zh-Hans", "zh-Hans-CN", "zh-CN", "zh-SG", "zh"] {
            XCTAssertEqual(
                ChineseScript.resolve(preferredLanguages: [id]), .simplified,
                "\(id) should resolve Simplified"
            )
        }
    }

    func testResolveDefaultsSimplifiedForNonChineseOrEmpty() {
        XCTAssertEqual(ChineseScript.resolve(preferredLanguages: ["en-US"]), .simplified)
        XCTAssertEqual(ChineseScript.resolve(preferredLanguages: []), .simplified)
    }

    func testResolveFirstChineseEntryWins() {
        XCTAssertEqual(
            ChineseScript.resolve(preferredLanguages: ["en-US", "zh-Hant-TW"]), .traditional
        )
        XCTAssertEqual(
            ChineseScript.resolve(preferredLanguages: ["en-US", "zh-Hans-CN"]), .simplified
        )
    }

    // MARK: normalize (language-gated entry point used by the app)

    func testNormalizeConvertsDetectedChinese() {
        // System prefers Traditional → mixed/Simplified zh output is forced Traditional.
        XCTAssertEqual(
            ChineseScriptConverter.normalize("软件", language: "zh", preferredLanguages: ["zh-Hant-TW"]),
            "軟件"
        )
        // System prefers Simplified → Traditional zh output is forced Simplified.
        XCTAssertEqual(
            ChineseScriptConverter.normalize("軟體", language: "zh", preferredLanguages: ["zh-Hans-CN"]),
            "软体"
        )
    }

    func testNormalizeProtectsJapaneseKorean() {
        // Japanese kanji / Korean hanja share code points with hanzi; the gate
        // must spare them even when the system locale is Chinese. "繁體" would
        // become "繁体" if the transform ran — it must not.
        let han = "繁體"
        XCTAssertEqual(ChineseScriptConverter.normalize(han, language: "ja", preferredLanguages: ["zh-Hans-CN"]), han)
        XCTAssertEqual(ChineseScriptConverter.normalize(han, language: "ko", preferredLanguages: ["zh-Hans-CN"]), han)
    }

    func testNormalizeConvertsEnglishAndUnknownStreams() {
        // Mixed-language handling: a stream transcribed as `en` (or with
        // detection unknown) may still carry Chinese characters — those get
        // normalised to the system script. Pure English/Latin passes through
        // because the ICU transform is a no-op on non-Han characters.
        XCTAssertEqual(
            ChineseScriptConverter.normalize("繁體", language: "en", preferredLanguages: ["zh-Hans-CN"]),
            "繁体"
        )
        XCTAssertEqual(
            ChineseScriptConverter.normalize("繁體", language: nil, preferredLanguages: ["zh-Hans-CN"]),
            "繁体"
        )
        XCTAssertEqual(
            ChineseScriptConverter.normalize("Hello, world!", language: "en", preferredLanguages: ["zh-Hans-CN"]),
            "Hello, world!"
        )
    }

    func testNormalizeMixedLatinAndChinese() {
        // The motivating case: English-detected utterance with an embedded
        // Traditional phrase, system prefers Simplified → English untouched,
        // Chinese normalised in place.
        XCTAssertEqual(
            ChineseScriptConverter.normalize("I use 軟體 daily", language: "en", preferredLanguages: ["zh-Hans-CN"]),
            "I use 软体 daily"
        )
    }
}
