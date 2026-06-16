import XCTest
@testable import OpenQuackPlatform

/// SPEC-036 — the bounded in-memory event ring the diagnostics dump reads.
final class DiagnosticsRingTests: XCTestCase {
    func testRingCapsAtCapacityAndKeepsNewest() {
        let d = Diagnostics(capacity: 5)
        for i in 0..<20 { d.log(.app, .info, "e\(i)") }
        let events = d.recentEvents()
        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(events.first?.message, "e15")
        XCTAssertEqual(events.last?.message, "e19")
    }

    func testEventsAreInOrder() {
        let d = Diagnostics(capacity: 10)
        d.log(.recording, .info, "a")
        d.log(.streaming, .warn, "b")
        d.log(.transcription, .error, "c")
        let msgs = d.recentEvents().map(\.message)
        XCTAssertEqual(msgs, ["a", "b", "c"])
    }

    func testClear() {
        let d = Diagnostics(capacity: 10)
        d.log(.app, .info, "x")
        d.clear()
        XCTAssertTrue(d.recentEvents().isEmpty)
    }
}
