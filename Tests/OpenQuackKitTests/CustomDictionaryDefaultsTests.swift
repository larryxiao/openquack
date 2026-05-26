import XCTest
@testable import OpenQuackKit

final class CustomDictionaryDefaultsTests: XCTestCase {
    func testSeedListContainsLoadBearingEntries() {
        // These are the entries we specifically curated for the
        // target user group. If one is missing, the seed has been
        // accidentally weakened.
        let required: [String] = [
            "Claude",
            "Claude Code",
            "Anthropic",
            "OpenQuack",
            "WhisperKit",
            "macOS",
            "AppleScript",
            "Xcode",
        ]
        for entry in required {
            XCTAssertTrue(
                CustomDictionaryDefaults.seedEntries.contains(entry),
                "seed list missing required entry: \(entry)"
            )
        }
    }

    func testSeedListNewlineJoined() {
        let joined = CustomDictionaryDefaults.seedList
        let split = joined.split(separator: "\n").map(String.init)
        XCTAssertEqual(split, CustomDictionaryDefaults.seedEntries)
    }

    func testSeedListIsConservativeInSize() {
        // Whisper bias has diminishing returns past ~10-20 entries.
        // Guard against drift toward a dumping ground.
        XCTAssertLessThanOrEqual(
            CustomDictionaryDefaults.seedEntries.count, 20,
            "seed list drifting toward a generic word dump — trim it back"
        )
    }

    func testSeedEntriesHaveNoLeadingTrailingWhitespace() {
        for entry in CustomDictionaryDefaults.seedEntries {
            XCTAssertEqual(
                entry,
                entry.trimmingCharacters(in: .whitespacesAndNewlines),
                "seed entry has stray whitespace: \(entry.debugDescription)"
            )
        }
    }
}
