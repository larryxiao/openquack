import XCTest
@testable import OpenQuackPlatform

/// SPEC-036 — the captured-vs-wall assessment that flags a tap that stopped
/// mid-recording (the freeze signature).
final class RecordingHealthTests: XCTestCase {
    func testIncompleteWhenCaptureFallsShort() {
        let h = RecordingHealth.assess(wallSeconds: 90, capturedSeconds: 20)
        XCTAssertTrue(h.isIncomplete)
        guard case let .incompleteCapture(wall, captured, shortfall) = h else {
            return XCTFail("expected incompleteCapture, got \(h)")
        }
        XCTAssertEqual(wall, 90, accuracy: 0.001)
        XCTAssertEqual(captured, 20, accuracy: 0.001)
        XCTAssertEqual(shortfall, 70, accuracy: 0.001)
    }

    func testOkWhenCaptureMatchesWall() {
        XCTAssertEqual(RecordingHealth.assess(wallSeconds: 10, capturedSeconds: 9.6), .ok)
    }

    func testOkForShortfallUnderMinimum() {
        // 1.5 s shortfall is below the 2 s floor → not flagged.
        XCTAssertEqual(RecordingHealth.assess(wallSeconds: 10, capturedSeconds: 8.5), .ok)
    }

    func testOkWhenWallZero() {
        XCTAssertEqual(RecordingHealth.assess(wallSeconds: 0, capturedSeconds: 0), .ok)
    }

    func testFractionBoundaryIsStrict() {
        // Exactly 85 % captured → ok (the fraction test is strict `<`).
        XCTAssertEqual(RecordingHealth.assess(wallSeconds: 100, capturedSeconds: 85), .ok)
        // Just under 85 % with a >2 s shortfall → flagged.
        XCTAssertTrue(RecordingHealth.assess(wallSeconds: 100, capturedSeconds: 84).isIncomplete)
    }
}
