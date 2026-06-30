import XCTest
import Foundation
@testable import OpenQuackKit

final class HistoryStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenQuackHistoryTests-\(UUID().uuidString)",
                                    isDirectory: true)
    }

    override func tearDown() async throws {
        if let r = tempRoot, FileManager.default.fileExists(atPath: r.path) {
            try? FileManager.default.removeItem(at: r)
        }
        try await super.tearDown()
    }

    private func makeStore(policy: RetentionPolicy = .default) -> HistoryStore {
        HistoryStore(rootURL: tempRoot, policy: policy)
    }

    // MARK: - save

    func testSaveTranscriptOnly_writesMetaAndTranscript_butNoAudio() async throws {
        let store = makeStore()
        let entry = try await store.save(audio: nil,
                                         transcript: "hello world",
                                         language: "en",
                                         modelID: "medium",
                                         durationSeconds: 1.5)
        XCTAssertEqual(entry.transcript, "hello world")
        XCTAssertNil(entry.audioURL)
        XCTAssertNotNil(entry.transcribedAt)

        let dir = tempRoot.appendingPathComponent(entry.id.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("meta.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("transcript.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("audio.caf").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("audio.m4a").path))
    }

    func testSaveAudio_thenMarkTranscribed_movesEntryFromRecoverableToList() async throws {
        let store = makeStore()
        let samples = [Float](repeating: 0.1, count: 16_000) // 1 s at 16 kHz
        let entry = try await store.save(audio: samples,
                                         transcript: "",
                                         language: "en",
                                         modelID: "medium",
                                         durationSeconds: 1.0)
        XCTAssertNotNil(entry.audioURL)
        XCTAssertNil(entry.transcribedAt)
        XCTAssertNil(entry.transcript)

        let recoverableBefore = await store.recoverable()
        XCTAssertEqual(recoverableBefore.count, 1)
        XCTAssertEqual(recoverableBefore.first?.id, entry.id)

        try await store.markTranscribed(entry.id, transcript: "later")

        let recoverableAfter = await store.recoverable()
        XCTAssertEqual(recoverableAfter.count, 0)

        let listed = await store.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.transcript, "later")
        XCTAssertNotNil(listed.first?.transcribedAt)
    }

    func testSaveWithAudio_writesAudioFile() async throws {
        let store = makeStore()
        var samples = [Float](repeating: 0, count: 16_000)
        for i in 0..<samples.count {
            samples[i] = 0.1 * sin(2 * .pi * 440 * Float(i) / 16_000)
        }
        let entry = try await store.save(audio: samples,
                                         transcript: "tone",
                                         language: nil,
                                         modelID: "medium",
                                         durationSeconds: 1.0)
        guard let url = entry.audioURL else {
            XCTFail("expected audioURL after save with audio")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 0, "encoded audio file should be non-empty")
    }

    // Opus only supports 8/12/16/24/48 kHz; at 44.1 kHz the Opus encoder's
    // settings are rejected. The rejection surfaces inside
    // `AVAssetWriterInput.init(mediaType:outputSettings:)` as an Objective-C
    // exception, which previously aborted the process (SIGABRT) instead of
    // falling back to AAC. This guards the fallback path: the save must succeed
    // and produce a non-empty AAC file rather than crash.
    func testSaveWithAudio_atOpusUnsupportedRate_fallsBackToAAC() async throws {
        let store = makeStore()
        let sampleRate = 44_100.0
        var samples = [Float](repeating: 0, count: 44_100)
        for i in 0..<samples.count {
            samples[i] = 0.1 * sin(2 * .pi * 440 * Float(i) / Float(sampleRate))
        }
        let entry = try await store.save(audio: samples,
                                         audioSampleRate: sampleRate,
                                         transcript: "tone",
                                         language: nil,
                                         modelID: "medium",
                                         durationSeconds: 1.0)
        guard let url = entry.audioURL else {
            XCTFail("expected audioURL after save with audio")
            return
        }
        XCTAssertEqual(url.pathExtension, "m4a", "should fall back to the AAC/m4a encoder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 0, "encoded audio file should be non-empty")
    }

    // MARK: - markTranscribed (errors)

    func testMarkTranscribed_throwsOnUnknownID() async throws {
        let store = makeStore()
        do {
            try await store.markTranscribed(UUID(), transcript: "x")
            XCTFail("expected notFound")
        } catch let HistoryError.notFound(_) {
            // ok
        } catch {
            XCTFail("expected HistoryError.notFound, got \(error)")
        }
    }

    // MARK: - queries

    func testRecoverable_filtersOnlyAudioWithoutTranscribedAt() async throws {
        let store = makeStore()
        // Transcript-only — not recoverable (no audio).
        _ = try await store.save(audio: nil,
                                 transcript: "a",
                                 language: nil,
                                 modelID: "m",
                                 durationSeconds: 1)
        // Audio + transcript — not recoverable (transcribedAt set).
        _ = try await store.save(audio: [Float](repeating: 0, count: 1600),
                                 transcript: "b",
                                 language: nil,
                                 modelID: "m",
                                 durationSeconds: 1)
        // Audio only — recoverable.
        let pending = try await store.save(audio: [Float](repeating: 0, count: 1600),
                                           transcript: "",
                                           language: nil,
                                           modelID: "m",
                                           durationSeconds: 1)

        let recov = await store.recoverable()
        XCTAssertEqual(recov.map(\.id), [pending.id])
    }

    func testList_returnsNewestFirst_capsAtLimit() async throws {
        let store = makeStore()
        var ids: [UUID] = []
        for i in 0..<5 {
            let e = try await store.save(audio: nil,
                                         transcript: "t\(i)",
                                         language: nil,
                                         modelID: "m",
                                         durationSeconds: 1)
            ids.append(e.id)
            // Tiny gap so recordedAt orders monotonically.
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let listed = await store.list(limit: 3)
        XCTAssertEqual(listed.count, 3)
        XCTAssertEqual(listed.map(\.id), Array(ids.reversed().prefix(3)))
    }

    func testList_limitZeroReturnsEmpty() async throws {
        let store = makeStore()
        _ = try await store.save(audio: nil,
                                 transcript: "x",
                                 language: nil,
                                 modelID: "m",
                                 durationSeconds: 1)
        let listed = await store.list(limit: 0)
        XCTAssertEqual(listed.count, 0)
    }

    // MARK: - mutations

    func testDelete_removesDirectory() async throws {
        let store = makeStore()
        let e = try await store.save(audio: nil,
                                     transcript: "x",
                                     language: nil,
                                     modelID: "m",
                                     durationSeconds: 1)
        let dir = tempRoot.appendingPathComponent(e.id.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        try await store.delete(e.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        let listed = await store.list()
        XCTAssertEqual(listed.count, 0)
    }

    func testDelete_throwsOnUnknownID() async throws {
        let store = makeStore()
        do {
            try await store.delete(UUID())
            XCTFail("expected notFound")
        } catch let HistoryError.notFound(_) {
            // ok
        } catch {
            XCTFail("expected HistoryError.notFound, got \(error)")
        }
    }

    func testPurgeAll_removesEverything() async throws {
        let store = makeStore()
        for i in 0..<3 {
            _ = try await store.save(audio: nil,
                                     transcript: "t\(i)",
                                     language: nil,
                                     modelID: "m",
                                     durationSeconds: 1)
        }
        try await store.purgeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.path))
        let listed = await store.list()
        XCTAssertEqual(listed.count, 0)
    }

    // MARK: - retention

    func testEnforceRetention_evictsOldestWhenCountExceeded() async throws {
        let policy = RetentionPolicy(maxEntries: 2,
                                     maxAge: 60 * 60 * 24 * 365,
                                     maxBytesOnDisk: Int64.max / 2)
        let store = makeStore(policy: policy)
        var ids: [UUID] = []
        for i in 0..<3 {
            let e = try await store.save(audio: nil,
                                         transcript: "t\(i)",
                                         language: nil,
                                         modelID: "m",
                                         durationSeconds: 1)
            ids.append(e.id)
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        // save() runs enforceRetention; oldest (ids[0]) should be evicted.
        let listed = await store.list()
        XCTAssertEqual(listed.count, 2)
        XCTAssertFalse(listed.contains { $0.id == ids[0] })
        XCTAssertTrue(listed.contains { $0.id == ids[1] })
        XCTAssertTrue(listed.contains { $0.id == ids[2] })
    }

    func testEnforceRetention_evictsAgedEntries() async throws {
        let policy = RetentionPolicy(maxEntries: 1000,
                                     maxAge: 0.5,
                                     maxBytesOnDisk: Int64.max / 2)
        let store = makeStore(policy: policy)
        let e = try await store.save(audio: nil,
                                     transcript: "old",
                                     language: nil,
                                     modelID: "m",
                                     durationSeconds: 1)
        try await Task.sleep(nanoseconds: 700_000_000) // 0.7 s
        await store.enforceRetention()
        let listed = await store.list()
        XCTAssertFalse(listed.contains { $0.id == e.id })
    }

    // Regression: crash-recovery entries (audio saved, not yet transcribed) must
    // survive retention even at maxEntries=0 ("None"), or the launch
    // enforceRetention would delete the recording before the recovery prompt.
    func testEnforceRetention_keepsPendingRecoveryEntryAtZeroCap() async throws {
        let store = makeStore(policy: .userConfigured(maxEntries: 0))
        let samples = [Float](repeating: 0.1, count: 16_000) // 1 s at 16 kHz
        let entry = try await store.save(audio: samples,
                                         transcript: "",      // not yet transcribed
                                         language: nil,
                                         modelID: "m",
                                         durationSeconds: 1.0)
        await store.enforceRetention()
        let recoverable = await store.recoverable()
        XCTAssertTrue(recoverable.contains { $0.id == entry.id },
                      "pending-recovery entry must not be evicted at maxEntries=0")
    }

    // A transcribed entry IS subject to the count cap — maxEntries=0 evicts it.
    func testEnforceRetention_evictsTranscribedEntryAtZeroCap() async throws {
        let store = makeStore(policy: .userConfigured(maxEntries: 0))
        let entry = try await store.save(audio: nil,
                                         transcript: "done",
                                         language: nil,
                                         modelID: "m",
                                         durationSeconds: 1.0)
        await store.enforceRetention()
        let listed = await store.list()
        XCTAssertFalse(listed.contains { $0.id == entry.id })
    }

    func testEnforceRetention_emptyStoreIsNoOp() async throws {
        let store = makeStore()
        await store.enforceRetention()  // must not throw / crash on missing dir
        let listed = await store.list()
        XCTAssertEqual(listed.count, 0)
    }

    // MARK: - Codable round-trip

    func testHistoryEntry_codableRoundTrip() throws {
        let original = HistoryEntry(
            id: UUID(),
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            transcribedAt: Date(timeIntervalSince1970: 1_700_000_010),
            durationSeconds: 12.5,
            transcript: "hello",
            language: "en",
            modelID: "medium",
            audioURL: URL(fileURLWithPath: "/tmp/foo/audio.caf")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.recordedAt.timeIntervalSince1970,
                       original.recordedAt.timeIntervalSince1970,
                       accuracy: 0.01)
        XCTAssertEqual(decoded.transcribedAt?.timeIntervalSince1970,
                       original.transcribedAt?.timeIntervalSince1970)
        XCTAssertEqual(decoded.transcript, original.transcript)
        XCTAssertEqual(decoded.language, original.language)
        XCTAssertEqual(decoded.modelID, original.modelID)
        XCTAssertEqual(decoded.audioURL?.path, original.audioURL?.path)
    }

    // MARK: - retention policy defaults match spec

    func testRetentionPolicyDefault_matchesSpec() {
        let p = RetentionPolicy.default
        XCTAssertEqual(p.maxEntries, 50)
        XCTAssertEqual(p.maxAge, 14 * 24 * 60 * 60)
        XCTAssertEqual(p.maxBytesOnDisk, 500 * 1024 * 1024)
    }

    func testUserConfiguredPolicy_setsCapWithLooseAgeAndDisk() {
        let p = RetentionPolicy.userConfigured(maxEntries: 100)
        XCTAssertEqual(p.maxEntries, 100)
        XCTAssertEqual(p.maxAge, 365 * 24 * 60 * 60)
        XCTAssertEqual(p.maxBytesOnDisk, 5 * 1024 * 1024 * 1024)
    }

    // Regression: a saved cap above .default's 50 must actually govern retention.
    // Previously the launch store used .default, silently capping history at 50.
    func testUserConfiguredPolicy_honorsCapAboveDefault() async throws {
        let store = makeStore(policy: .userConfigured(maxEntries: 60))
        for i in 0..<55 {
            _ = try await store.save(audio: nil,
                                     transcript: "t\(i)",
                                     language: nil,
                                     modelID: "m",
                                     durationSeconds: 1)
        }
        let listed = await store.list(limit: 1000)
        XCTAssertEqual(listed.count, 55)  // all kept; not pruned down to 50
    }
}
