import Foundation

/// SPEC-022 §2.4 — Persistence for `CorrectionCandidate`s.
///
/// On-disk JSON at `~/Library/Application Support/OpenQuack/correction_candidates.json`.
/// `record(_:)` dedupes by `(wrong, right)` (case-insensitive) and merges
/// counts. The store caps total entries at 500 and evicts by `lastSeen`
/// ascending (oldest first) when over the cap.
///
/// All access is serialised through the actor; the file URL is injectable so
/// tests can use a tmp directory.
public actor CorrectionCandidateStore {
    public static let maxEntries = 500

    private let fileURL: URL

    /// Default location per SPEC-022 §2.4.
    public static var defaultFileURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("OpenQuack", isDirectory: true)
            .appendingPathComponent("correction_candidates.json")
    }

    public init(fileURL: URL = CorrectionCandidateStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// Returns all stored candidates in load order (no sort applied).
    public func loadAll() throws -> [CorrectionCandidate] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CorrectionCandidate].self, from: data)
    }

    /// Merge `incoming` into the on-disk set: matching `(wrong, right)` keys
    /// have their `count` summed and `lastSeen` advanced to the newer of the
    /// two; new keys are appended. Caps at `maxEntries` by evicting the
    /// oldest-`lastSeen` entries (SPEC §2.4).
    @discardableResult
    public func record(_ incoming: [CorrectionCandidate]) throws -> [CorrectionCandidate] {
        guard !incoming.isEmpty else {
            return (try? loadAll()) ?? []
        }
        try ensureParent()
        var existing = (try? loadAll()) ?? []

        var index: [String: Int] = [:]
        for (i, c) in existing.enumerated() {
            index[c.dedupeKey] = i
        }

        for c in incoming {
            if let i = index[c.dedupeKey] {
                existing[i].count += c.count
                if c.lastSeen > existing[i].lastSeen {
                    existing[i].lastSeen = c.lastSeen
                }
                // Most recent suppression wins (latest user decision).
                if let s = c.suppressedUntil {
                    existing[i].suppressedUntil = s
                }
            } else {
                existing.append(c)
                index[c.dedupeKey] = existing.count - 1
            }
        }

        existing = evictIfNeeded(existing)
        try persist(existing)
        return existing
    }

    /// Test / debugging convenience: drop the file entirely.
    public func reset() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - private

    private func ensureParent() throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent,
                                                withIntermediateDirectories: true)
    }

    private func evictIfNeeded(_ entries: [CorrectionCandidate]) -> [CorrectionCandidate] {
        guard entries.count > Self.maxEntries else { return entries }
        // Sort ascending by lastSeen (oldest first), drop the head until we
        // fit under the cap, preserve original ordering of the survivors so
        // the file diff stays small.
        let oldest = entries
            .enumerated()
            .sorted { $0.element.lastSeen < $1.element.lastSeen }
        let dropCount = entries.count - Self.maxEntries
        let dropIndices = Set(oldest.prefix(dropCount).map(\.offset))
        return entries.enumerated()
            .filter { !dropIndices.contains($0.offset) }
            .map(\.element)
    }

    private func persist(_ entries: [CorrectionCandidate]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
