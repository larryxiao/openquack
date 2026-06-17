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

    /// End-to-end freeze scenario, no hardware: audio flows, then the tap dies on
    /// a configuration change. Asserts the whole response chain — interruption
    /// fires, the captured tally reflects only what was delivered, and the
    /// captured-vs-wall shortfall reads as incomplete capture. This is the
    /// regression the two rollbacks were about.
    func testFreezeScenario_tapStopsMidRecording_interruptsAndCaptureFallsShort() {
        let rec = AudioRecorder()
        var interrupted = 0
        rec.interruptionHandler = { interrupted += 1 }
        var framesSeen = 0
        rec.framesHandler = { samples, _ in framesSeen += samples.count }

        rec.beginCaptureForTesting(sampleRate: 16_000)
        // ~2 s of audio delivered through the capture pipeline (20 × 0.1 s).
        for _ in 0..<20 {
            rec.deliverFramesForTesting([Float](repeating: 0.05, count: 1_600), sampleRate: 16_000)
        }
        XCTAssertEqual(framesSeen, 32_000, "the streaming consumer must see every delivered frame")
        XCTAssertEqual(rec.capturedSeconds, 2.0, accuracy: 0.01)

        // The tap dies from a real config change (engine stopped).
        rec.handleConfigurationChange(engineRunning: false)
        XCTAssertEqual(interrupted, 1, "a dead tap must trigger the graceful auto-stop")

        // The session ran ~10 s wall but captured only 2 s → flagged incomplete.
        let health = RecordingHealth.assess(wallSeconds: 10, capturedSeconds: rec.capturedSeconds)
        XCTAssertTrue(health.isIncomplete, "a large captured-vs-wall shortfall must read as incomplete capture")
    }
}
