import XCTest
@testable import OpenQuackPlatform

/// SPEC-036 — the attachable diagnostics text the bug-report flow produces.
final class DiagnosticsReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testRenderFlagsIncompleteCapture() {
        let health = RecordingHealth.assess(wallSeconds: 92, capturedSeconds: 21)
        let last = DiagnosticsReport.LastRecording(
            wallSeconds: 92, capturedSeconds: 21, health: health,
            path: "streaming", chunkCount: 1, chunkFailures: 0,
            transcribeWallSeconds: 9.0, audioSeconds: 21,
            detectedLanguage: "en", interrupted: true
        )
        let events = [
            DiagEvent(time: now.addingTimeInterval(-3), category: .recording, level: .info, message: "start: input 48000 Hz"),
            DiagEvent(time: now.addingTimeInterval(-1), category: .recording, level: .warn, message: "AVAudioEngineConfigurationChange mid-capture"),
        ]
        let out = DiagnosticsReport.render(
            appVersion: "2.0.0-alpha.18", osVersion: "15.5", chip: "Apple M4",
            model: "medium", lastRecording: last, events: events, generatedAt: now
        )
        XCTAssertTrue(out.contains("INCOMPLETE"), out)
        XCTAssertTrue(out.contains("RTF"), out)
        XCTAssertTrue(out.contains("1 chunk"), out)
        XCTAssertTrue(out.contains("lang=en"), out)
        XCTAssertTrue(out.contains("interrupted"), out)
        XCTAssertTrue(out.contains("ConfigurationChange"), out)
        XCTAssertTrue(out.contains("Apple M4"), out)
    }

    func testRenderOkRecordingHasNoIncompleteMarker() {
        let last = DiagnosticsReport.LastRecording(
            wallSeconds: 30, capturedSeconds: 29.8, health: .ok, path: "streaming",
            chunkCount: 2, chunkFailures: 0, transcribeWallSeconds: 8,
            audioSeconds: 30, detectedLanguage: "en"
        )
        let out = DiagnosticsReport.render(
            appVersion: "x", osVersion: "y", chip: "z", model: nil,
            lastRecording: last, events: [], generatedAt: now
        )
        XCTAssertFalse(out.contains("INCOMPLETE"), out)
        XCTAssertTrue(out.contains("2 chunks"), out)
        XCTAssertTrue(out.contains("RTF 0.27"), out)   // 8 / 30
    }

    func testRenderNoRecording() {
        let out = DiagnosticsReport.render(
            appVersion: "x", osVersion: "y", chip: "z", model: nil,
            lastRecording: nil, events: [], generatedAt: now
        )
        XCTAssertTrue(out.contains("(none this session)"), out)
    }

    func testRTFComputation() {
        XCTAssertEqual(DiagnosticsReport.rtf(transcribe: 5, audio: 10)!, 0.5, accuracy: 0.0001)
        XCTAssertNil(DiagnosticsReport.rtf(transcribe: nil, audio: 10))
        XCTAssertNil(DiagnosticsReport.rtf(transcribe: 5, audio: 0))
    }
}
