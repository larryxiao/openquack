import XCTest
@testable import OpenQuackKit

/// Gated regression for the in-process llama.cpp engine — runs only when
/// `OQ_LLAMA_MODEL` points at a Gemma 4 GGUF (skipped in CI). Guards the
/// SPEC-007 turn-marker root cause: with the wrong chat-turn markers the
/// model never sees a valid turn structure and emits generic English
/// boilerplate ("I am a large language model…") instead of formatting the
/// input. Asserts the polish keeps the input language and isn't boilerplate.
final class LlamaCppPolishEngineModelTests: XCTestCase {
    func testPolishKeepsChineseAndIsNotBoilerplate() async throws {
        guard let path = ProcessInfo.processInfo.environment["OQ_LLAMA_MODEL"] else {
            throw XCTSkip("set OQ_LLAMA_MODEL=<gguf path> to run")
        }
        let engine = LlamaCppPolishEngine(modelPath: URL(fileURLWithPath: path))
        let raw = "目前就有两个bug你可以看一下这两个log明显是有bug一个是多加了一个标识符另外一个是多加了一个阶段"
        let out = try await engine.polish(raw, context: PolishContext(language: "zh", timestamp: Date()))

        let hasCJK = out.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        XCTAssertTrue(hasCJK, "expected Chinese output (turn markers may be wrong); got: \(out)")
        XCTAssertFalse(out.lowercased().contains("large language model"),
                       "model emitted generic boilerplate — turn markers likely wrong; got: \(out)")
        XCTAssertFalse(out.contains("<<<END>>>") || out.contains("turn|>"),
                       "scaffold/turn markers leaked into output; got: \(out)")
    }
}
