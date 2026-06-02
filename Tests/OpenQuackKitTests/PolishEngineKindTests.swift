import XCTest
@testable import OpenQuackKit

final class PolishEngineKindTests: XCTestCase {
    func testParsesKnownRawValues() {
        XCTAssertEqual(PolishEngineKind(rawValue: "off"), .off)
        XCTAssertEqual(PolishEngineKind(rawValue: "ollama"), .ollama)
    }

    func testUnknownRawValueIsNil() {
        XCTAssertNil(PolishEngineKind(rawValue: "mlx"))
    }

    func testAllCasesCovered() {
        XCTAssertEqual(Set(PolishEngineKind.allCases), [.off, .ollama])
    }
}
