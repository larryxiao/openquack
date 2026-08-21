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

    private func canDelete(
        _ variant: String,
        selected: String = "large-v3",
        loaded: String? = "large-v3",
        remote: Bool = false,
        dictating: Bool = false
    ) -> Bool {
        SpeechModelCatalog.canDelete(
            variant: variant, selected: selected, loaded: loaded,
            remoteBackend: remote, dictating: dictating
        )
    }

    func testLocalBackendProtectsSelectedAndLoadedModels() {
        XCTAssertFalse(canDelete("large-v3"))                       // selected + loaded
        XCTAssertFalse(canDelete("medium", selected: "medium", loaded: "large-v3"))
        XCTAssertTrue(canDelete("small"))
    }

    func testRemoteBackendFreesEverySelectedModel() {
        // SPEC-044 — nothing is loaded locally, so the selection is just disk.
        XCTAssertTrue(canDelete("large-v3", remote: true))
        XCTAssertTrue(canDelete("small", remote: true))
    }

    func testDictationProtectsEveryModelOnEitherBackend() {
        XCTAssertFalse(canDelete("small", dictating: true))
        // A local dictation started before the switch is still using its engine.
        XCTAssertFalse(canDelete("large-v3", remote: true, dictating: true))
    }
}
