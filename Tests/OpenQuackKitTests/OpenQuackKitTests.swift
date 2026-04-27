import XCTest
@testable import OpenQuackKit

final class OpenQuackKitTests: XCTestCase {
    func testVersionExists() {
        XCTAssertFalse(OpenQuackKit.version.isEmpty)
    }
}
