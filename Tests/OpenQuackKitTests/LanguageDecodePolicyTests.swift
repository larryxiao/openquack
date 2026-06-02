import XCTest
@testable import OpenQuackPlatform

/// Unit tests for the pinned / locked / auto decision that drives WhisperKit
/// language handling on both transcription paths (SPEC-021). This is the
/// regression-prone part of the auto-detect fix; the integration paths that use
/// it require a loaded model, so the decision itself is covered here in
/// isolation.
final class LanguageDecodePolicyTests: XCTestCase {
    func testPinnedLanguageForcesAndDisablesDetection() {
        let d = LanguageDecodePolicy.decide(pinned: "zh")
        XCTAssertEqual(d.language, "zh")
        XCTAssertFalse(d.detectLanguage)
    }

    func testPinnedWinsOverLocked() {
        let d = LanguageDecodePolicy.decide(pinned: "en", locked: "zh")
        XCTAssertEqual(d.language, "en")
        XCTAssertFalse(d.detectLanguage)
    }

    func testLockedReusedWhenNotPinned() {
        // Streaming: a language detected on an earlier chunk is reused without
        // re-detecting, so the utterance can't flip language mid-stream.
        let d = LanguageDecodePolicy.decide(pinned: nil, locked: "zh")
        XCTAssertEqual(d.language, "zh")
        XCTAssertFalse(d.detectLanguage)
    }

    func testNeitherEnablesDetection() {
        // The core fix: auto + nothing locked ⇒ detection on (the case that was
        // silently off and caused English translation of non-English speech).
        let d = LanguageDecodePolicy.decide(pinned: nil, locked: nil)
        XCTAssertNil(d.language)
        XCTAssertTrue(d.detectLanguage)
    }

    func testOfflineDefaultLockedIsNil() {
        // The offline path calls decide(pinned:) with `locked` defaulting nil.
        XCTAssertEqual(
            LanguageDecodePolicy.decide(pinned: nil),
            LanguageDecodePolicy.decide(pinned: nil, locked: nil)
        )
        XCTAssertEqual(
            LanguageDecodePolicy.decide(pinned: "ja"),
            LanguageDecodePolicy.decide(pinned: "ja", locked: nil)
        )
    }

    func testEmptyStringsTreatedAsAbsent() {
        // An empty pinned/locked string must not be forced as a language —
        // WhisperKit would treat "" as a real (invalid) code instead of auto.
        let d1 = LanguageDecodePolicy.decide(pinned: "")
        XCTAssertNil(d1.language)
        XCTAssertTrue(d1.detectLanguage)

        let d2 = LanguageDecodePolicy.decide(pinned: nil, locked: "")
        XCTAssertNil(d2.language)
        XCTAssertTrue(d2.detectLanguage)
    }

    func testOfflineParityWithPriorOneLiner() {
        // The offline path previously did `detectLanguage = (language == nil)`.
        // The policy must produce the identical detectLanguage for both cases.
        XCTAssertFalse(LanguageDecodePolicy.decide(pinned: "en").detectLanguage)
        XCTAssertTrue(LanguageDecodePolicy.decide(pinned: nil).detectLanguage)
    }

    // MARK: - decideStreamingChunk (SPEC-035 mixed-language)

    func testStreamingPinnedForcesEvenOnShortChunk() {
        // A user-pinned language always wins, regardless of chunk size / running.
        let d = LanguageDecodePolicy.decideStreamingChunk(
            pinned: "en", running: "zh", chunkSeconds: 2, minDetectSeconds: 10
        )
        XCTAssertEqual(d.language, "en")
        XCTAssertFalse(d.detectLanguage)
    }

    func testStreamingFullChunkReDetectsDespiteRunning() {
        // The un-locking: a full chunk re-detects even when a language is already
        // running, so the language can switch at a chunk boundary.
        let d = LanguageDecodePolicy.decideStreamingChunk(
            pinned: nil, running: "en", chunkSeconds: 20, minDetectSeconds: 10
        )
        XCTAssertNil(d.language)
        XCTAssertTrue(d.detectLanguage)
    }

    func testStreamingShortChunkInheritsRunning() {
        // A short trailing chunk inherits the running language rather than risk a
        // weak-detection flip to the "en" fallback.
        let d = LanguageDecodePolicy.decideStreamingChunk(
            pinned: nil, running: "zh", chunkSeconds: 3, minDetectSeconds: 10
        )
        XCTAssertEqual(d.language, "zh")
        XCTAssertFalse(d.detectLanguage)
    }

    func testStreamingShortChunkWithNoRunningDetects() {
        // Nothing to inherit (e.g. a short first chunk) → detect anyway.
        let d = LanguageDecodePolicy.decideStreamingChunk(
            pinned: nil, running: nil, chunkSeconds: 3, minDetectSeconds: 10
        )
        XCTAssertNil(d.language)
        XCTAssertTrue(d.detectLanguage)
    }

    func testStreamingEmptyRunningTreatedAsAbsent() {
        let d = LanguageDecodePolicy.decideStreamingChunk(
            pinned: "", running: "", chunkSeconds: 3, minDetectSeconds: 10
        )
        XCTAssertNil(d.language)
        XCTAssertTrue(d.detectLanguage)
    }

    func testStreamingThresholdIsInclusive() {
        // chunkSeconds == minDetectSeconds re-detects (the boundary is reliable).
        let d = LanguageDecodePolicy.decideStreamingChunk(
            pinned: nil, running: "en", chunkSeconds: 10, minDetectSeconds: 10
        )
        XCTAssertTrue(d.detectLanguage)
    }
}
