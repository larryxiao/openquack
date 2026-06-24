import XCTest
@testable import OpenQuackKit

final class CorrectionDiffTests: XCTestCase {

    // MARK: - happy path

    func testSingleSubstitution_isExtracted() {
        let result = CorrectionDiff.extractCorrections(
            rawTranscript: "I love cloud code",
            committedText: "I love Claude code"
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.wrong, "cloud")
        XCTAssertEqual(result.first?.right, "Claude")
    }

    func testMultipleSubstitutions_extractedInOrder() {
        let result = CorrectionDiff.extractCorrections(
            rawTranscript: "cloud code says hi there cloud",
            committedText: "Claude code says yo there Claude"
        )
        // Tokens 0 and 5 are non-case substitutions; token 3 "hi" → "yo"
        // is distance 2 case-insensitive. "code", "says", "there" are
        // identical and drop out. Order preserved.
        let pairs = result.map { "\($0.wrong)->\($0.right)" }
        XCTAssertEqual(pairs, ["cloud->Claude", "hi->yo", "cloud->Claude"])
    }

    // MARK: - no false positives

    func testIdenticalStrings_yieldNoCandidates() {
        let result = CorrectionDiff.extractCorrections(
            rawTranscript: "hello world",
            committedText: "hello world"
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testEmptyStrings_yieldNoCandidates() {
        XCTAssertTrue(CorrectionDiff.extractCorrections(
            rawTranscript: "", committedText: "").isEmpty)
        XCTAssertTrue(CorrectionDiff.extractCorrections(
            rawTranscript: "hello", committedText: "").isEmpty)
        XCTAssertTrue(CorrectionDiff.extractCorrections(
            rawTranscript: "", committedText: "hello").isEmpty)
    }

    // MARK: - case folding

    func testCaseOnlyDifference_isNotACandidate() {
        let result = CorrectionDiff.extractCorrections(
            rawTranscript: "i typed something",
            committedText: "I typed something"
        )
        // "i" → "I" is case-only and must be dropped before stop-word check
        // ever runs.
        XCTAssertTrue(result.isEmpty)
    }

    func testCaseFoldedEditDistance_isMeasuredOnLowercase() {
        // "WHISPERKIT" vs "WhisperKit" — both lowercase to "whisperkit",
        // case-only, must drop.
        let result = CorrectionDiff.extractCorrections(
            rawTranscript: "use WHISPERKIT today",
            committedText: "use WhisperKit today"
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - edit-distance threshold

    func testEditDistanceWithinThreshold_passes() {
        // "code" → "Code" is case-only (drop), but "writes" → "wrote"
        // is distance 2 (case-insensitive) — must pass.
        let result = CorrectionDiff.extractCorrections(
            rawTranscript: "he writes here",
            committedText: "he wrote here"
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.wrong, "writes")
        XCTAssertEqual(result.first?.right, "wrote")
    }

    func testEditDistanceAtBoundary_passes() {
        // "kitten" vs "Kitchen" is distance 3 case-insensitively → boundary.
        let result = CorrectionDiff.extractCorrections(
            rawTranscript: "the kitten ran",
            committedText: "the Kitchen ran"
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.wrong, "kitten")
        XCTAssertEqual(result.first?.right, "Kitchen")
    }

    func testEditDistanceOverThreshold_isFiltered() {
        // "Anthropic" vs "OpenQuack" is well over 3 — different word entirely,
        // not a correction. Drop.
        let result = CorrectionDiff.extractCorrections(
            rawTranscript: "Anthropic builds Claude",
            committedText: "OpenQuack builds Claude"
        )
        XCTAssertTrue(result.isEmpty,
                      "edit-distance > 3 indicates intentional rewrite, not correction")
    }

    // MARK: - stop-word filtering

    func testStopWordSubstitution_isFiltered() {
        // "a" → "an" is within edit distance but `wrong` is a stop word.
        let result = CorrectionDiff.extractCorrections(
            rawTranscript: "I saw a elephant",
            committedText: "I saw an elephant"
        )
        XCTAssertTrue(result.isEmpty,
                      "stop-word `wrong` side must filter the pair out")
    }

    func testNonStopWordWithStopWordRight_stillExtracted() {
        // "hi" → "the" — `wrong` is not a stop word, so this counts.
        // (Edit distance 3 case-insensitive, just inside the cap.)
        let result = CorrectionDiff.extractCorrections(
            rawTranscript: "hi all",
            committedText: "the all"
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.wrong, "hi")
        XCTAssertEqual(result.first?.right, "the")
    }

    // MARK: - lastSeen propagation

    func testCorrection_carriesProvidedTimestamp() {
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        let result = CorrectionDiff.extractCorrections(
            rawTranscript: "cloud code",
            committedText: "Claude code",
            now: pinned
        )
        XCTAssertEqual(result.first?.lastSeen, pinned)
    }

    // MARK: - segment extraction (PostPasteCorrectionObserver helper)

    func testAlignedEditSegments_returnsBothTailsAfterCommonPrefix() {
        let (t, f) = PostPasteCorrectionObserver.alignedEditSegments(
            transcript: "hello cloud code",
            finalValue: "hello Claude code"
        )
        XCTAssertEqual(t, "cloud code")
        XCTAssertEqual(f, "Claude code")
    }

    func testAlignedEditSegments_bothEmptyWhenIdentical() {
        let (t, f) = PostPasteCorrectionObserver.alignedEditSegments(
            transcript: "hello world",
            finalValue: "hello world"
        )
        XCTAssertTrue(t.isEmpty)
        XCTAssertTrue(f.isEmpty)
    }

    func testAlignedEditSegments_diffOfBothTailsExtractsCorrection() {
        // Realistic flow: full transcript was "use cloud code please";
        // user edited to "use Claude code please" in-place. Aligning on
        // both tails should yield exactly the cloud→Claude pair.
        let (t, f) = PostPasteCorrectionObserver.alignedEditSegments(
            transcript: "use cloud code please",
            finalValue: "use Claude code please"
        )
        let pairs = CorrectionDiff.extractCorrections(
            rawTranscript: t,
            committedText: f
        )
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.wrong, "cloud")
        XCTAssertEqual(pairs.first?.right, "Claude")
    }
}
