import Foundation

/// SPEC-028 — per-entry derivations the Stats pane (and any future export
/// surface) reads to render personal performance numbers. Pure: no IO, no
/// state — just arithmetic on the three timestamps `HistoryStore` already
/// records.

extension HistoryEntry {
    /// Wall-clock seconds from end-of-recording to end-of-transcription.
    /// Returns nil when the entry is still mid-transcription (no
    /// `transcribedAt`) or — defensively — when the timestamps imply a
    /// non-positive elapsed (clock skew, restored-from-backup, the
    /// recovery flow stamping `transcribedAt` before the recording's
    /// nominal end). The Stats UI treats nil here as "no row tail."
    public var processSeconds: TimeInterval? {
        guard let transcribedAt else { return nil }
        let recordingEndedAt = recordedAt.addingTimeInterval(durationSeconds)
        let elapsed = transcribedAt.timeIntervalSince(recordingEndedAt)
        return elapsed > 0 ? elapsed : nil
    }

    /// `durationSeconds / processSeconds`. e.g. 300 s of audio processed
    /// in 3 s → 100. Nil when `processSeconds` is nil or zero.
    public var realtimeMultiple: Double? {
        guard let processSeconds, processSeconds > 0 else { return nil }
        return durationSeconds / processSeconds
    }
}
