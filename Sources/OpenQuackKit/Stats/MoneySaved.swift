import Foundation

/// SPEC-041 — "Money saved" estimate for the usage-stats pane.
///
/// OpenQuack transcribes on-device for free. This expresses the usage already
/// done as what a paid cloud alternative would have cost — on a usage-metered
/// (per audio minute) basis or a subscription (per month) basis. Pure +
/// table-driven so the numbers are auditable and unit-tested; no network, prices
/// are compiled-in constants, dated in `builtIns`.
public enum MoneySaved {
    /// How a baseline charges.
    public enum Basis: Equatable, Sendable {
        /// Metered transcription APIs (OpenAI, Deepgram, …).
        case perAudioMinute(usd: Double)
        /// Flat consumer-app subscriptions (Wispr Flow, Superwhisper, …).
        case perMonth(usd: Double)
    }

    public struct Baseline: Identifiable, Equatable, Sendable {
        public let id: String
        public let label: String      // e.g. "OpenAI gpt-4o-transcribe"
        public let priceNote: String  // e.g. "$0.006 / min"
        public let basis: Basis
        public init(id: String, label: String, priceNote: String, basis: Basis) {
            self.id = id
            self.label = label
            self.priceNote = priceNote
            self.basis = basis
        }
    }

    /// Reference baselines. Prices verified June 2026; the UI offers a custom
    /// rate for anything unlisted or out of date.
    public static let builtIns: [Baseline] = [
        Baseline(id: "openai-4o-transcribe",
                 label: "OpenAI gpt-4o-transcribe", priceNote: "$0.006 / min",
                 basis: .perAudioMinute(usd: 0.006)),
        Baseline(id: "openai-4o-mini-transcribe",
                 label: "OpenAI gpt-4o-mini-transcribe", priceNote: "$0.003 / min",
                 basis: .perAudioMinute(usd: 0.003)),
        Baseline(id: "wispr-flow",
                 label: "Wispr Flow", priceNote: "$15 / mo",
                 basis: .perMonth(usd: 15)),
        Baseline(id: "superwhisper",
                 label: "Superwhisper Pro", priceNote: "$9.99 / mo",
                 basis: .perMonth(usd: 9.99)),
    ]

    /// Average seconds per month (365.25 / 12 days), for month-fraction math.
    private static let secondsPerMonth: Double = 30.4375 * 24 * 60 * 60

    /// Estimated USD saved versus `basis`, given usage so far. `now` is passed
    /// in (not read) so the calc stays pure + deterministically testable.
    public static func savedUSD(
        audioSeconds: Double,
        firstRecordedAt: Date?,
        now: Date,
        basis: Basis
    ) -> Double {
        switch basis {
        case .perAudioMinute(let usd):
            guard audioSeconds > 0 else { return 0 }
            return (audioSeconds / 60.0) * usd
        case .perMonth(let usd):
            guard let months = monthsActive(firstRecordedAt: firstRecordedAt, now: now) else { return 0 }
            return months * usd
        }
    }

    /// Months active (≥ 1) since first use, or nil when there's no start date or
    /// `now` precedes it. Floored at 1 because a subscription bills from day one.
    public static func monthsActive(firstRecordedAt: Date?, now: Date) -> Double? {
        guard let first = firstRecordedAt, now > first else { return nil }
        return max(1.0, now.timeIntervalSince(first) / secondsPerMonth)
    }
}
