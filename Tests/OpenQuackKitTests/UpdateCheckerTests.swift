import XCTest
@testable import OpenQuackKit

final class UpdateCheckerTests: XCTestCase {
    // MARK: isNewer — the cases the old .numeric compare got wrong

    func testEqualVersionsAreNotNewer() {
        // The bug report: installed == latest, yet the badge stayed on.
        XCTAssertFalse(UpdateChecker.isNewer(remote: "2.0.0-alpha.16", than: "2.0.0-alpha.16"))
        XCTAssertFalse(UpdateChecker.isNewer(remote: "v2.0.0-alpha.16", than: "2.0.0-alpha.16"))
    }

    func testPrereleaseOrderingIsNumericNotLexical() {
        XCTAssertTrue(UpdateChecker.isNewer(remote: "2.0.0-alpha.16", than: "2.0.0-alpha.2"))
        XCTAssertFalse(UpdateChecker.isNewer(remote: "2.0.0-alpha.2", than: "2.0.0-alpha.16"))
    }

    func testReleaseOutranksItsPrereleases() {
        XCTAssertTrue(UpdateChecker.isNewer(remote: "2.0.0", than: "2.0.0-alpha.16"))
        XCTAssertFalse(UpdateChecker.isNewer(remote: "2.0.0-alpha.16", than: "2.0.0"))
    }

    func testCoreVersionPrecedence() {
        XCTAssertTrue(UpdateChecker.isNewer(remote: "2.0.1", than: "2.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer(remote: "2.1.0", than: "2.0.9"))
        XCTAssertFalse(UpdateChecker.isNewer(remote: "2.0.0", than: "2.0.1"))
    }

    func testStageOrdering() {
        // alpha < beta < rc < release
        XCTAssertTrue(UpdateChecker.isNewer(remote: "2.0.0-beta.1", than: "2.0.0-alpha.99"))
        XCTAssertTrue(UpdateChecker.isNewer(remote: "2.0.0-rc.1", than: "2.0.0-beta.5"))
    }

    func testShortCoreAndBuildMetadata() {
        XCTAssertFalse(UpdateChecker.isNewer(remote: "2.0", than: "2.0.0"))      // 2.0 == 2.0.0
        XCTAssertFalse(UpdateChecker.isNewer(remote: "2.0.0+build9", than: "2.0.0")) // metadata ignored
    }
}
