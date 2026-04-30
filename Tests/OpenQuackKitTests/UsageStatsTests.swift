import XCTest
@testable import OpenQuackKit

final class UsageStatsTests: XCTestCase {
    private var suiteName: String!
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test-\(UUID().uuidString)"
        store = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        store?.removePersistentDomain(forName: suiteName)
        store = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - tracking toggle

    func testTrackingEnabledByDefault() async {
        let stats = UsageStats(store: store)
        let enabled = await stats.trackingEnabled
        XCTAssertTrue(enabled)
    }

    func testRecordIncrementsCountersWhenEnabled() async {
        let stats = UsageStats(store: store)
        await stats.record(transcript: "hello world", audioSeconds: 2.5)

        let snap = await stats.snapshot()
        XCTAssertEqual(snap.wordsDictated, 2)
        XCTAssertEqual(snap.audioSeconds, 2.5, accuracy: 0.001)
        XCTAssertEqual(snap.dictationCount, 1)
        XCTAssertNotNil(snap.firstRecordedAt)
    }

    func testRecordAccumulatesAcrossCalls() async {
        let stats = UsageStats(store: store)
        await stats.record(transcript: "hello world", audioSeconds: 2)
        await stats.record(transcript: "another three words here", audioSeconds: 3)

        let snap = await stats.snapshot()
        XCTAssertEqual(snap.wordsDictated, 6)
        XCTAssertEqual(snap.audioSeconds, 5, accuracy: 0.001)
        XCTAssertEqual(snap.dictationCount, 2)
    }

    func testTrackingDisabledIsNoop() async {
        let stats = UsageStats(store: store)
        await stats.setTrackingEnabled(false)
        await stats.record(transcript: "hello world", audioSeconds: 2)

        let snap = await stats.snapshot()
        XCTAssertEqual(snap.wordsDictated, 0)
        XCTAssertEqual(snap.audioSeconds, 0)
        XCTAssertEqual(snap.dictationCount, 0)
        XCTAssertNil(snap.firstRecordedAt)
    }

    func testTrackingTogglePersistsAcrossInstances() async {
        let first = UsageStats(store: store)
        await first.setTrackingEnabled(false)

        let second = UsageStats(store: store)
        let enabled = await second.trackingEnabled
        XCTAssertFalse(enabled)
    }

    // MARK: - firstRecordedAt

    func testFirstRecordedAtSetOnFirstRecordOnly() async throws {
        let stats = UsageStats(store: store)
        await stats.record(transcript: "first", audioSeconds: 1)
        let snap1 = await stats.snapshot()
        let first = try XCTUnwrap(snap1.firstRecordedAt)

        // Wait long enough that the timestamp would visibly differ if updated.
        try await Task.sleep(nanoseconds: 30_000_000)
        await stats.record(transcript: "second", audioSeconds: 1)
        let snap2 = await stats.snapshot()
        let second = try XCTUnwrap(snap2.firstRecordedAt)

        XCTAssertEqual(first.timeIntervalSince1970, second.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - word count

    func testWordCountEnglish() {
        XCTAssertEqual(UsageStats.wordCount("hello world"), 2)
        XCTAssertEqual(UsageStats.wordCount("one"), 1)
        XCTAssertEqual(UsageStats.wordCount("a b c d e"), 5)
    }

    func testWordCountCJKHan() {
        XCTAssertEqual(UsageStats.wordCount("你好世界"), 4)
    }

    func testWordCountJapaneseKana() {
        XCTAssertEqual(UsageStats.wordCount("こんにちは"), 5)
    }

    func testWordCountKoreanHangul() {
        // 안녕하세요 — five Hangul syllables.
        XCTAssertEqual(UsageStats.wordCount("안녕하세요"), 5)
    }

    func testWordCountMixedScripts() {
        // "hello" (1 word) + "世界" (2 chars) = 3
        XCTAssertEqual(UsageStats.wordCount("hello 世界"), 3)
    }

    func testWordCountEmpty() {
        XCTAssertEqual(UsageStats.wordCount(""), 0)
    }

    func testWordCountWhitespaceOnly() {
        XCTAssertEqual(UsageStats.wordCount("   "), 0)
        XCTAssertEqual(UsageStats.wordCount("\n\t  "), 0)
    }

    func testWordCountCollapsesRepeatedSpaces() {
        // "hello   world" still two words, regardless of how many spaces.
        XCTAssertEqual(UsageStats.wordCount("hello   world"), 2)
    }

    // MARK: - timeSaved

    func testTimeSavedPositiveCase() {
        let snap = UsageStatsSnapshot(
            wordsDictated: 100,
            audioSeconds: 30,
            dictationCount: 1,
            firstRecordedAt: nil
        )
        // 100 words / 60 wpm × 60 = 100 s typing; saved = 100 − 30 = 70.
        XCTAssertEqual(snap.timeSaved(typingWordsPerMinute: 60), 70, accuracy: 0.001)
    }

    func testTimeSavedFloorsAtZero() {
        let snap = UsageStatsSnapshot(
            wordsDictated: 5,
            audioSeconds: 30,
            dictationCount: 1,
            firstRecordedAt: nil
        )
        // 5 words / 60 wpm × 60 = 5 s typing; saved = max(0, 5 − 30) = 0.
        XCTAssertEqual(snap.timeSaved(typingWordsPerMinute: 60), 0)
    }

    // MARK: - reset / export

    func testResetClearsCountersAndFirstRecordedAt() async {
        let stats = UsageStats(store: store)
        await stats.record(transcript: "hello world", audioSeconds: 2)
        await stats.reset()

        let snap = await stats.snapshot()
        XCTAssertEqual(snap.wordsDictated, 0)
        XCTAssertEqual(snap.audioSeconds, 0)
        XCTAssertEqual(snap.dictationCount, 0)
        XCTAssertNil(snap.firstRecordedAt)
    }

    func testResetPreservesTrackingFlag() async {
        let stats = UsageStats(store: store)
        await stats.setTrackingEnabled(false)
        await stats.reset()

        let enabled = await stats.trackingEnabled
        XCTAssertFalse(enabled, "reset() should wipe counters but leave the tracking toggle alone")
    }

    func testExportJSONRoundTripsSnapshot() async throws {
        let stats = UsageStats(store: store)
        await stats.record(transcript: "hello world", audioSeconds: 2)

        let data = try await stats.exportJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UsageStatsSnapshot.self, from: data)

        let expected = await stats.snapshot()
        XCTAssertEqual(decoded.wordsDictated, expected.wordsDictated)
        XCTAssertEqual(decoded.audioSeconds, expected.audioSeconds, accuracy: 0.001)
        XCTAssertEqual(decoded.dictationCount, expected.dictationCount)
        // ISO8601 has 1-second precision; firstRecordedAt round-trips lossily.
        XCTAssertEqual(
            decoded.firstRecordedAt?.timeIntervalSince1970 ?? 0,
            expected.firstRecordedAt?.timeIntervalSince1970 ?? 0,
            accuracy: 1.0
        )
    }
}
