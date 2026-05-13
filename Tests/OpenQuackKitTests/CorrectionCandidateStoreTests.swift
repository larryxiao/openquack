import XCTest
import Foundation
@testable import OpenQuackKit

final class CorrectionCandidateStoreTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenQuackCorrectionStoreTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir,
                                                withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("correction_candidates.json")
    }

    override func tearDown() async throws {
        if let d = tempDir, FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.removeItem(at: d)
        }
        try await super.tearDown()
    }

    private func makeStore() -> CorrectionCandidateStore {
        CorrectionCandidateStore(fileURL: fileURL)
    }

    // MARK: - load / save

    func testLoadAll_emptyWhenFileMissing() async throws {
        let store = makeStore()
        let entries = try await store.loadAll()
        XCTAssertTrue(entries.isEmpty)
    }

    func testRecord_persistsAcrossInstances() async throws {
        let store = makeStore()
        let now = Date()
        try await store.record([
            CorrectionCandidate(wrong: "cloud", right: "Claude",
                                count: 1, lastSeen: now)
        ])

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let reopened = makeStore()
        let entries = try await reopened.loadAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.wrong, "cloud")
        XCTAssertEqual(entries.first?.right, "Claude")
        XCTAssertEqual(entries.first?.count, 1)
    }

    // MARK: - dedupe / merge

    func testRecord_dedupesAndMergesCounts() async throws {
        let store = makeStore()
        let t1 = Date(timeIntervalSince1970: 1_000_000)
        let t2 = Date(timeIntervalSince1970: 2_000_000)

        try await store.record([
            CorrectionCandidate(wrong: "cloud", right: "Claude",
                                count: 1, lastSeen: t1)
        ])
        try await store.record([
            CorrectionCandidate(wrong: "cloud", right: "Claude",
                                count: 2, lastSeen: t2)
        ])

        let entries = try await store.loadAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.count, 3)
        XCTAssertEqual(entries.first?.lastSeen, t2)
    }

    func testRecord_caseInsensitiveDedupeKey() async throws {
        let store = makeStore()
        try await store.record([
            CorrectionCandidate(wrong: "Cloud", right: "Claude",
                                count: 1, lastSeen: Date())
        ])
        try await store.record([
            CorrectionCandidate(wrong: "cloud", right: "claude",
                                count: 1, lastSeen: Date())
        ])
        let entries = try await store.loadAll()
        XCTAssertEqual(entries.count, 1, "same pair under different casing must dedupe")
        XCTAssertEqual(entries.first?.count, 2)
    }

    func testRecord_keepsDistinctRightValuesAsSeparate() async throws {
        let store = makeStore()
        try await store.record([
            CorrectionCandidate(wrong: "cloud", right: "Claude",
                                count: 1, lastSeen: Date()),
            CorrectionCandidate(wrong: "cloud", right: "cloud9",
                                count: 1, lastSeen: Date())
        ])
        let entries = try await store.loadAll()
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: - cap-500 eviction

    // MARK: - observer test-seam

    func testObserverTestSeam_recordsCorrectionsFromSynthesizedFinalValue() async throws {
        let store = makeStore()
        let observer = PostPasteCorrectionObserver(store: store)
        // `start()` would require live Accessibility trust; the test seam
        // drives the "final value captured" branch directly so the diff →
        // store wiring is verified without a live AX event.
        await observer.testOnlyFire(
            transcript: "use cloud code please",
            finalFieldValue: "use Claude code please"
        )
        let entries = try await store.loadAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.wrong, "cloud")
        XCTAssertEqual(entries.first?.right, "Claude")
    }

    func testObserverTestSeam_noEditMeansNoCandidates() async throws {
        let store = makeStore()
        let observer = PostPasteCorrectionObserver(store: store)
        await observer.testOnlyFire(
            transcript: "untouched paste",
            finalFieldValue: "untouched paste"
        )
        let entries = try await store.loadAll()
        XCTAssertTrue(entries.isEmpty)
    }

    func testRecord_capsAt500_evictingByLastSeenAscending() async throws {
        let store = makeStore()
        // Pre-fill with 500 entries with increasing lastSeen — entry 0 is the
        // oldest.
        let base = Date(timeIntervalSince1970: 1_000_000)
        var seed: [CorrectionCandidate] = []
        for i in 0..<500 {
            seed.append(CorrectionCandidate(
                wrong: "w\(i)",
                right: "r\(i)",
                count: 1,
                lastSeen: base.addingTimeInterval(Double(i))
            ))
        }
        try await store.record(seed)
        var entries = try await store.loadAll()
        XCTAssertEqual(entries.count, 500)

        // Insert one new entry — total would be 501; oldest (w0) must evict.
        let newer = base.addingTimeInterval(10_000)
        try await store.record([
            CorrectionCandidate(wrong: "wNew", right: "rNew",
                                count: 1, lastSeen: newer)
        ])
        entries = try await store.loadAll()
        XCTAssertEqual(entries.count, 500, "must not exceed cap")

        let kept = Set(entries.map(\.wrong))
        XCTAssertTrue(kept.contains("wNew"))
        XCTAssertFalse(kept.contains("w0"), "oldest entry must be evicted first")
        XCTAssertTrue(kept.contains("w1"), "second-oldest survives one overflow")
    }
}
