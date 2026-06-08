import Foundation

/// Rolling-window download-rate estimator. Pure and `Date`-free — the caller
/// supplies monotonically increasing timestamps (seconds) and cumulative byte
/// counts; this type smooths over a trailing window so the speed/ETA shown to
/// the user doesn't jitter chunk-to-chunk.
public struct DownloadRateEstimator {
    private struct Sample { let t: TimeInterval; let completed: Int64 }
    private var samples: [Sample] = []
    private let window: TimeInterval

    public init(window: TimeInterval = 4) { self.window = window }

    /// Record a cumulative byte count at time `t`; evict samples older than the window.
    public mutating func add(completed: Int64, at t: TimeInterval) {
        samples.append(Sample(t: t, completed: completed))
        let cutoff = t - window
        samples.removeAll { $0.t < cutoff }
    }

    /// Smoothed bytes/sec across the window, or nil when there aren't enough
    /// samples / no forward progress / no time span.
    public var bytesPerSecond: Double? {
        guard samples.count >= 2, let first = samples.first, let last = samples.last else { return nil }
        let dt = last.t - first.t
        let db = last.completed - first.completed
        guard dt > 0, db > 0 else { return nil }
        return Double(db) / dt
    }

    /// Seconds to download the remaining `total - completed` bytes at the
    /// current smoothed rate, or nil when the rate is unknown.
    public func eta(completed: Int64, total: Int64) -> TimeInterval? {
        guard let bps = bytesPerSecond, bps > 0 else { return nil }
        return Double(max(0, total - completed)) / bps
    }
}
