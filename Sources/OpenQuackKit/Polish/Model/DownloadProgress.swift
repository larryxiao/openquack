import Foundation

/// Progress for a model download. Replaces the bare `Double` fraction so the
/// UI layer can compute speed/ETA from byte counts.
public struct DownloadProgress: Sendable, Equatable {
    public let completed: Int64
    public let total: Int64

    public init(completed: Int64, total: Int64) {
        self.completed = completed
        self.total = total
    }

    /// 0…1, clamped. Zero when `total` is non-positive.
    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(completed) / Double(total))
    }
}
