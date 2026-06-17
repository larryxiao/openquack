import XCTest
@testable import OpenQuackKit

/// SPEC-041 — the "money saved" calculator.
final class MoneySavedTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private let day = 24.0 * 60 * 60
    private let month = 30.4375 * 24 * 60 * 60

    // MARK: per audio minute

    func testPerMinute_oneHour() {
        // 3600 s = 60 min × $0.006 = $0.36
        let v = MoneySaved.savedUSD(audioSeconds: 3600, firstRecordedAt: nil, now: now,
                                    basis: .perAudioMinute(usd: 0.006))
        XCTAssertEqual(v, 0.36, accuracy: 1e-9)
    }

    func testPerMinute_zeroAudio_isZero() {
        XCTAssertEqual(MoneySaved.savedUSD(audioSeconds: 0, firstRecordedAt: nil, now: now,
                                           basis: .perAudioMinute(usd: 0.006)), 0)
    }

    func testPerMinute_ignoresStartDate() {
        let withDate = MoneySaved.savedUSD(audioSeconds: 600, firstRecordedAt: now.addingTimeInterval(-month), now: now,
                                           basis: .perAudioMinute(usd: 0.003))
        let withoutDate = MoneySaved.savedUSD(audioSeconds: 600, firstRecordedAt: nil, now: now,
                                              basis: .perAudioMinute(usd: 0.003))
        XCTAssertEqual(withDate, withoutDate, accuracy: 1e-12)
        XCTAssertEqual(withDate, 10.0 * 0.003, accuracy: 1e-12)  // 10 min × $0.003
    }

    // MARK: per month

    func testPerMonth_threeMonths() {
        let first = now.addingTimeInterval(-3 * month)
        let v = MoneySaved.savedUSD(audioSeconds: 1234, firstRecordedAt: first, now: now,
                                    basis: .perMonth(usd: 15))
        XCTAssertEqual(v, 45.0, accuracy: 1e-6)  // 3 × $15
    }

    func testPerMonth_flooredAtOneMonth() {
        let first = now.addingTimeInterval(-5 * day)   // < 1 month
        let v = MoneySaved.savedUSD(audioSeconds: 100, firstRecordedAt: first, now: now,
                                    basis: .perMonth(usd: 15))
        XCTAssertEqual(v, 15.0, accuracy: 1e-9)        // not a fraction
    }

    func testPerMonth_noStartDate_isZero() {
        XCTAssertEqual(MoneySaved.savedUSD(audioSeconds: 999, firstRecordedAt: nil, now: now,
                                           basis: .perMonth(usd: 15)), 0)
    }

    func testMonthsActive() {
        XCTAssertNil(MoneySaved.monthsActive(firstRecordedAt: nil, now: now))
        XCTAssertEqual(MoneySaved.monthsActive(firstRecordedAt: now.addingTimeInterval(-2 * month), now: now)!,
                       2.0, accuracy: 1e-6)
        // future start date → nil
        XCTAssertNil(MoneySaved.monthsActive(firstRecordedAt: now.addingTimeInterval(day), now: now))
    }

    func testBuiltInsPresentAndTagged() {
        let ids = Set(MoneySaved.builtIns.map(\.id))
        XCTAssertTrue(ids.contains("openai-4o-transcribe"))
        XCTAssertTrue(ids.contains("wispr-flow"))
        XCTAssertEqual(ids.count, MoneySaved.builtIns.count)  // ids unique
    }
}
