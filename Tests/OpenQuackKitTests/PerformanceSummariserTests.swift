import XCTest
@testable import OpenQuackKit

final class PerformanceSummariserTests: XCTestCase {

    private func makeEntry(durationSeconds: TimeInterval,
                           transcribedAt: Date? = nil,
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

    /// Build a transcribed entry whose `realtimeMultiple` equals the
    /// requested multiple — caller controls duration; `processSeconds`
    /// is derived as `duration / rtm`.
    private func makeTranscribedEntry(durationSeconds: TimeInterval,
                                      realtimeMultiple rtm: Double) -> HistoryEntry {
        let recordedAt = Date(timeIntervalSinceReferenceDate: 0)
        let processSecs = durationSeconds / rtm
        let transcribedAt = recordedAt.addingTimeInterval(durationSeconds + processSecs)
        return makeEntry(durationSeconds: durationSeconds,
                         transcribedAt: transcribedAt,
                         recordedAt: recordedAt)
    }

    // MARK: - empty / single

    func testSummariseEmpty() {
        let summary = PerformanceSummariser.summarise([])
        XCTAssertNil(summary.longestEntry)
        XCTAssertNil(summary.averageRealtimeMultiple)
        // Every bucket present, all zero.
        for b in DurationBucket.allCases {
            XCTAssertEqual(summary.bucketCounts[b], 0, "\(b) expected 0")
        }
    }

    func testSummariseSingleEntry() throws {
        let e = makeTranscribedEntry(durationSeconds: 45, realtimeMultiple: 10)
        let summary = PerformanceSummariser.summarise([e])
        XCTAssertEqual(summary.longestEntry?.id, e.id)
        let avg = try XCTUnwrap(summary.averageRealtimeMultiple)
        XCTAssertEqual(avg, 10, accuracy: 0.001)
        XCTAssertEqual(summary.bucketCounts[.to1min], 1)
        XCTAssertEqual(summary.bucketCounts[.under30s], 0)
    }

    // MARK: - bucket edges

    /// Each (duration, expected) probes a half-open boundary. 30.0 must
    /// fall into `30s–1m`, 29.999 into `<30s`, etc.
    func testBucketEdges_under30s_30s_30s001() {
        XCTAssertEqual(bucket(for: 0),       .under30s)
        XCTAssertEqual(bucket(for: 29.999),  .under30s)
        XCTAssertEqual(bucket(for: 30.0),    .to1min)
        XCTAssertEqual(bucket(for: 30.001),  .to1min)
    }

    func testBucketEdges_1m() {
        XCTAssertEqual(bucket(for: 59.999),  .to1min)
        XCTAssertEqual(bucket(for: 60.0),    .to3min)
        XCTAssertEqual(bucket(for: 60.001),  .to3min)
    }

    func testBucketEdges_3m() {
        XCTAssertEqual(bucket(for: 179.999), .to3min)
        XCTAssertEqual(bucket(for: 180.0),   .to10min)
        XCTAssertEqual(bucket(for: 180.001), .to10min)
    }

    func testBucketEdges_10m() {
        XCTAssertEqual(bucket(for: 599.999), .to10min)
        XCTAssertEqual(bucket(for: 600.0),   .over10min)
        XCTAssertEqual(bucket(for: 600.001), .over10min)
        XCTAssertEqual(bucket(for: 9_999),   .over10min)
    }

    private func bucket(for duration: TimeInterval) -> DurationBucket {
        let summary = PerformanceSummariser.summarise([makeEntry(durationSeconds: duration)])
        // Find the single bucket with a non-zero count.
        let hit = summary.bucketCounts.first { $0.value == 1 }
        return hit?.key ?? .under30s
    }

    // MARK: - longest

    func testLongestEntryAcrossMultiple() {
        let a = makeEntry(durationSeconds: 10)
        let b = makeEntry(durationSeconds: 500)
        let c = makeEntry(durationSeconds: 120)
        let summary = PerformanceSummariser.summarise([a, b, c])
        XCTAssertEqual(summary.longestEntry?.id, b.id)
    }

    func testLongestEntryIncludesUntranscribed() {
        // Untranscribed entry is still eligible — UI must guard the
        // process-time tail, not the summariser.
        let mid = makeTranscribedEntry(durationSeconds: 60, realtimeMultiple: 20)
        let longUntranscribed = makeEntry(durationSeconds: 800, transcribedAt: nil)
        let summary = PerformanceSummariser.summarise([mid, longUntranscribed])
        XCTAssertEqual(summary.longestEntry?.id, longUntranscribed.id)
        XCTAssertNil(summary.longestEntry?.realtimeMultiple)
    }

    // MARK: - average RTM

    func testAverageRealtimeMultipleSkipsNilRTM() throws {
        let transcribed = makeTranscribedEntry(durationSeconds: 60, realtimeMultiple: 20)
        let stillRecording = makeEntry(durationSeconds: 30, transcribedAt: nil)
        let alsoTranscribed = makeTranscribedEntry(durationSeconds: 120, realtimeMultiple: 40)

        let summary = PerformanceSummariser.summarise([transcribed, stillRecording, alsoTranscribed])
        let avg = try XCTUnwrap(summary.averageRealtimeMultiple)
        XCTAssertEqual(avg, 30, accuracy: 0.001)  // (20 + 40) / 2
    }

    func testAverageRealtimeMultipleNilWhenZeroQualifyingEntries() {
        let stillRecording = makeEntry(durationSeconds: 30, transcribedAt: nil)
        let summary = PerformanceSummariser.summarise([stillRecording])
        XCTAssertNil(summary.averageRealtimeMultiple)
    }
}
