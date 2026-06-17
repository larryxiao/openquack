import XCTest
@testable import OpenQuackKit

/// SPEC-042 increment 1 — the load-bearing freeze-fix gate (SPEC-036): a
/// configuration change auto-stops the recording ONLY when the audio engine
/// actually stopped. A benign reconfig that leaves capture running must not cut
/// a dictation short. This is the most regression-prone line in the freeze fix.
final class AudioRecorderInterruptionTests: XCTestCase {
    func testConfigChange_engineStopped_firesInterruption() {
        let rec = AudioRecorder()
        var fired = 0
        rec.interruptionHandler = { fired += 1 }
        rec.handleConfigurationChange(engineRunning: false)
        XCTAssertEqual(fired, 1, "engine stopped mid-capture must trigger the graceful auto-stop")
    }

    func testConfigChange_engineRunning_doesNotFire() {
        let rec = AudioRecorder()
        var fired = 0
        rec.interruptionHandler = { fired += 1 }
        rec.handleConfigurationChange(engineRunning: true)
        XCTAssertEqual(fired, 0, "a benign reconfig (engine still running) must NOT truncate the recording")
    }

    func testConfigChange_noHandler_isNoOp() {
        let rec = AudioRecorder()
        rec.interruptionHandler = nil
        rec.handleConfigurationChange(engineRunning: false)  // must not crash
    }

    func testConfigChange_idempotentPerEvent() {
        let rec = AudioRecorder()
        var fired = 0
        rec.interruptionHandler = { fired += 1 }
        rec.handleConfigurationChange(engineRunning: false)
        rec.handleConfigurationChange(engineRunning: true)   // a later benign change
        rec.handleConfigurationChange(engineRunning: false)
        XCTAssertEqual(fired, 2, "each genuine stop fires once; the benign change in between does not")
    }
}
