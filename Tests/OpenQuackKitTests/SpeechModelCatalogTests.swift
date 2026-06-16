import XCTest
@testable import OpenQuackKit

final class SpeechModelCatalogTests: XCTestCase {
    func testDisplayName_knownVariants() {
        XCTAssertEqual(SpeechModelCatalog.displayName(for: "medium"), "Medium")
        XCTAssertEqual(SpeechModelCatalog.displayName(for: "large-v3"), "Large v3")
        XCTAssertEqual(SpeechModelCatalog.displayName(for: "tiny"), "Tiny")
    }

    func testDisplayName_unknownVariantFallsBackToRaw() {
        XCTAssertEqual(SpeechModelCatalog.displayName(for: "distil-large-v3"), "distil-large-v3")
    }

    func testSizeLabel_knownVariants() {
        XCTAssertEqual(SpeechModelCatalog.sizeLabel(for: "tiny"), "~150 MB")
        XCTAssertEqual(SpeechModelCatalog.sizeLabel(for: "medium"), "~1.5 GB")
        XCTAssertEqual(SpeechModelCatalog.sizeLabel(for: "large-v3"), "~3 GB")
    }

    func testSizeLabel_unknownVariantFallsBack() {
        XCTAssertEqual(SpeechModelCatalog.sizeLabel(for: "mystery"), "the model")
    }
}
