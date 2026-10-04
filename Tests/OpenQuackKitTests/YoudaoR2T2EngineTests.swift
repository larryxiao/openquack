import XCTest
@testable import OpenQuackKit

// SPEC-046 (ASD-STE100) — Unit tests for YoudaoR2T2Engine and EngineKind.youdao.

final class YoudaoR2T2EngineTests: XCTestCase {
    func testEngineKindParsesYoudaoAndAliases() throws {
        XCTAssertEqual(try EngineKind.parse("youdao"), .youdao)
        XCTAssertEqual(try EngineKind.parse("r2t2"), .youdao)
        XCTAssertEqual(try EngineKind.parse("Confucius4-R2T2"), .youdao)
        XCTAssertEqual(try EngineKind.parse("qwen3-asr"), .youdao)
    }

    func testResolvesModelAliases() {
        XCTAssertEqual(
            YoudaoR2T2Engine.resolveModelID("confucius4-r2t2"),
            "netease-youdao/Confucius4-R2T2"
        )
        XCTAssertEqual(
            YoudaoR2T2Engine.resolveModelID("r2t2"),
            "netease-youdao/Confucius4-R2T2"
        )
        XCTAssertEqual(
            YoudaoR2T2Engine.resolveModelID("qwen3-asr-1.7b"),
            "Qwen/Qwen3-ASR-1.7B"
        )
        XCTAssertEqual(
            YoudaoR2T2Engine.resolveModelID("qwen3-asr-0.6b"),
            "Qwen/Qwen3-ASR-0.6B"
        )
        XCTAssertEqual(
            YoudaoR2T2Engine.resolveModelID("custom/model-path"),
            "custom/model-path"
        )
    }

    func testParsesLanguageOutputWithAsrTextTag() {
        let raw = "language Chinese<asr_text>今天的天气真好, 我们出去散步吧."
        let parsed = YoudaoR2T2Engine.parseLanguageOutput(raw)
        XCTAssertEqual(parsed.language, "zh")
        XCTAssertEqual(parsed.text, "今天的天气真好，我们出去散步吧。")
    }

    func testParsesLanguageOutputWithoutTag() {
        let raw = "Hello world."
        let parsed = YoudaoR2T2Engine.parseLanguageOutput(raw, fallbackLanguage: "en")
        XCTAssertEqual(parsed.language, "en")
        XCTAssertEqual(parsed.text, "Hello world.")
    }

    func testFormatsTabDelimitedTranscribeCommand() {
        let cmd = YoudaoR2T2Engine.formatTranscribeCommand(
            audioPath: "/tmp/sample.wav",
            language: "zh",
            customWords: "OpenQuack\nConfucius4"
        )
        XCTAssertEqual(cmd, "TRANSCRIBE\t/tmp/sample.wav\tzh\tOpenQuack, Confucius4")
    }

    func testParsesRunnerJSONResponse() throws {
        let json = #"{"text":"language Chinese<asr_text>你好, 世界!","wall_seconds":0.42,"audio_seconds":2.5,"language":"Chinese"}"#
        let res = try YoudaoR2T2Engine.parseRunnerResponse(json)
        XCTAssertEqual(res.text, "你好，世界！")
        XCTAssertEqual(res.detectedLanguage, "zh")
        XCTAssertEqual(res.wallSeconds, 0.42, accuracy: 0.001)
        XCTAssertEqual(res.audioSeconds, 2.5, accuracy: 0.001)
    }

    func testParsesRunnerErrorResponse() {
        XCTAssertThrowsError(try YoudaoR2T2Engine.parseRunnerResponse("ERROR model missing"))
    }

    func testSubprocessMockRoundTrip() async throws {
        let engine = try await YoudaoR2T2Engine(model: "mock:今天的天气真好, 我们出去散步吧.")
        let dummyURL = URL(fileURLWithPath: "/tmp/nonexistent-youdao-test.wav")
        let result = try await engine.transcribe(
            audioFile: dummyURL,
            language: "zh",
            customWords: "OpenQuack"
        )
        XCTAssertEqual(result.text, "今天的天气真好，我们出去散步吧。")
        XCTAssertEqual(result.detectedLanguage, "zh")
    }
}
