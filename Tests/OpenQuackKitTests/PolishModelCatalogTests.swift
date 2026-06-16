import XCTest
@testable import OpenQuackKit

final class PolishModelCatalogTests: XCTestCase {
    private func tmp() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("oq-cat-\(UUID().uuidString).gguf")
    }

    func testMissingFileIsNotInstalled() {
        XCTAssertFalse(PolishModelCatalog.isInstalled(at: tmp()))
    }

    func testWrongSizeIsNotInstalled() throws {
        let url = tmp()
        try Data(count: 10).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertFalse(PolishModelCatalog.isInstalled(at: url, expectedBytes: 11))
    }

    func testExactSizeIsInstalled() throws {
        let url = tmp()
        try Data(count: 32).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(PolishModelCatalog.isInstalled(at: url, expectedBytes: 32))
    }

    func testRemoteURLAndFilenameAreConsistent() {
        XCTAssertEqual(PolishModelCatalog.filename, "gemma-4-E2B-it-Q4_K_M.gguf")
        XCTAssertTrue(PolishModelCatalog.remoteURL.absoluteString.hasSuffix(PolishModelCatalog.filename))
        XCTAssertEqual(PolishModelCatalog.localURL.lastPathComponent, PolishModelCatalog.filename)
    }
}
