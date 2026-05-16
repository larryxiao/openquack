import XCTest
@testable import OpenQuackKit

final class HistoryEntryProcessSecondsTests: XCTestCase {

    private func makeEntry(durationSeconds: TimeInterval,
                           transcribedAt: Date?,
                           recordedAt: Date = Date(timeIntervalSinceReferenceDate: 1_000_000)) -> HistoryEntry {
        HistoryEntry(id: UUID(),
                     recordedAt: recordedAt,
                     transcribedAt: transcribedAt,
                     durationSeconds: durationSeconds,
                     transcript: nil,
                     language: nil,
                     modelID: nil,
                     audioURL: nil)
    }

    // MARK: - processSeconds

    func testProcessSecondsNilWhenTranscribedAtNil() {
        let entry = makeEntry(durationSeconds: 5, transcribedAt: nil)
        XCTAssertNil(entry.processSeconds)
    }

    func testProcessSecondsPositiveCase() throws {
        let recordedAt = Date(timeIntervalSinceReferenceDate: 0)
        let duration: TimeInterval = 60
        // Transcription finishes 3 s after the recording ended.
        let transcribedAt = recordedAt.addingTimeInterval(duration + 3)
        let entry = makeEntry(durationSeconds: duration,
                              transcribedAt: transcribedAt,
                              recordedAt: recordedAt)
        let elapsed = try XCTUnwrap(entry.processSeconds)
        XCTAssertEqual(elapsed, 3, accuracy: 0.001)
    }

    func testProcessSecondsNilWhenTranscribedAtBeforeRecordingEnd() {
        // Defensive: clock-skew / recovery-flow can stamp transcribedAt
        // earlier than recordedAt + durationSeconds. The guard returns nil
        // rather than a negative elapsed.
        let recordedAt = Date(timeIntervalSinceReferenceDate: 0)
        let duration: TimeInterval = 60
        let transcribedAt = recordedAt.addingTimeInterval(duration - 1)
        let entry = makeEntry(durationSeconds: duration,
                              transcribedAt: transcribedAt,
                              recordedAt: recordedAt)
        XCTAssertNil(entry.processSeconds)
    }

    func testProcessSecondsNilWhenTranscribedAtExactlyAtRecordingEnd() {
        // elapsed == 0 isn't a meaningful "processed in 0 s" claim; treat
        // as nil so the UI hides the tail rather than show 0.0 s.
        let recordedAt = Date(timeIntervalSinceReferenceDate: 0)
        let duration: TimeInterval = 5
        let transcribedAt = recordedAt.addingTimeInterval(duration)
        let entry = makeEntry(durationSeconds: duration,
                              transcribedAt: transcribedAt,
                              recordedAt: recordedAt)
        XCTAssertNil(entry.processSeconds)
    }

    // MARK: - realtimeMultiple

    func testRealtimeMultipleNilWhenProcessSecondsNil() {
        let entry = makeEntry(durationSeconds: 100, transcribedAt: nil)
        XCTAssertNil(entry.realtimeMultiple)
    }

    func testRealtimeMultiplePositiveCase() throws {
        let recordedAt = Date(timeIntervalSinceReferenceDate: 0)
        let duration: TimeInterval = 300            // 5 min audio
        let processSecs: TimeInterval = 3
        let transcribedAt = recordedAt.addingTimeInterval(duration + processSecs)
        let entry = makeEntry(durationSeconds: duration,
                              transcribedAt: transcribedAt,
                              recordedAt: recordedAt)
        let rtm = try XCTUnwrap(entry.realtimeMultiple)
        XCTAssertEqual(rtm, 100, accuracy: 0.001)
    }
}
