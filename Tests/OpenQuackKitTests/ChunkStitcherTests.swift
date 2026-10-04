import XCTest
@testable import OpenQuackPlatform

// SPEC-046 (ASD-STE100) — Unit tests for CJK and Latin chunk stitching.

final class ChunkStitcherTests: XCTestCase {
    func testStitchesCJKChunksWithoutInsertingASCIISpace() {
        let chunks = ["今天天气", "真好"]
        XCTAssertEqual(ChunkStitcher.stitch(chunks), "今天天气真好")
    }

    func testDeduplicatesSingleBoundaryCJKCharacter() {
        let chunks = ["今天天气", "气真好"]
        XCTAssertEqual(ChunkStitcher.stitch(chunks), "今天天气真好")
    }

    func testDeduplicatesMultiCharacterBoundaryCJKOverlap() {
        let chunks = ["今天天气", "天气真好"]
        XCTAssertEqual(ChunkStitcher.stitch(chunks), "今天天气真好")
    }

    func testStitchesAfterCJKFullWidthStopWithoutASCIISpace() {
        let chunks = ["提供关键材料。", "蘋果公司宣布"]
        XCTAssertEqual(ChunkStitcher.stitch(chunks), "提供关键材料。蘋果公司宣布")
    }

    func testStitchesLatinChunksWithSpaceAndDeduplicatesBoundaryWord() {
        let chunks = ["Hello world,", "world how are you"]
        XCTAssertEqual(ChunkStitcher.stitch(chunks), "Hello world, how are you")
    }

    func testStitchesLatinChunksWithoutOverlap() {
        let chunks = ["First sentence.", "Second sentence."]
        XCTAssertEqual(ChunkStitcher.stitch(chunks), "First sentence. Second sentence.")
    }

    func testIgnoresEmptyAndWhitespaceChunks() {
        let chunks = ["", "  ", "你好", "  ", "世界"]
        XCTAssertEqual(ChunkStitcher.stitch(chunks), "你好世界")
    }
}
