import XCTest
@testable import OpenQuackKit

final class DownloadRateEstimatorTests: XCTestCase {
    func testSpeedOverWindow() {
        var e = DownloadRateEstimator(window: 4)
        e.add(completed: 0, at: 0)
        e.add(completed: 2_000, at: 2)
        XCTAssertEqual(e.bytesPerSecond ?? 0, 1_000, accuracy: 1)
    }

    func testEtaFromSpeed() {
        var e = DownloadRateEstimator(window: 4)
        e.add(completed: 0, at: 0)
        e.add(completed: 1_000, at: 1)            // 1000 B/s
        // 4000 bytes remain → 4 s.
        XCTAssertEqual(e.eta(completed: 1_000, total: 5_000) ?? 0, 4, accuracy: 0.01)
    }

    func testFewerThanTwoSamplesIsNil() {
        var e = DownloadRateEstimator(window: 4)
        e.add(completed: 100, at: 0)
        XCTAssertNil(e.bytesPerSecond)
        XCTAssertNil(e.eta(completed: 100, total: 1_000))
    }

    func testStaleSamplesEvicted() {
        var e = DownloadRateEstimator(window: 4)
        e.add(completed: 0, at: 0)
        e.add(completed: 10_000, at: 1)           // would imply 10k B/s if kept
        e.add(completed: 11_000, at: 10)          // evicts the two samples >4s old
        // Only the last sample survives the 4s window → not enough to estimate.
        XCTAssertNil(e.bytesPerSecond)
    }

    func testZeroOrNegativeSpanIsNil() {
        var e = DownloadRateEstimator(window: 4)
        e.add(completed: 100, at: 5)
        e.add(completed: 200, at: 5)              // same timestamp
        XCTAssertNil(e.bytesPerSecond)
    }
}
