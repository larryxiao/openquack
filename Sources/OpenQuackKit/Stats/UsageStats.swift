import Foundation

/// SPEC-013 — Local-only usage statistics.
///
/// Aggregate counters (words dictated, audio seconds processed, dictation
/// count, first-recorded timestamp) persisted in UserDefaults. No transcript
/// text is stored; no network IO; tracking honours a single toggle. Display
/// gating lives in the app layer — this actor only controls whether new
/// dictations contribute to the counters.
public actor UsageStats {
    private let store: UserDefaults

    public init(store: UserDefaults = .standard) {
        self.store = store
    }

    // MARK: - Tracking toggle

    /// Tracking is ON by default. A missing key means "never set" → default ON,
    /// so a fresh install records from the first dictation.
    public var trackingEnabled: Bool {
        if let v = store.object(forKey: Keys.trackingEnabled) as? Bool { return v }
        return true
    }

    public func setTrackingEnabled(_ enabled: Bool) {
        store.set(enabled, forKey: Keys.trackingEnabled)
    }

    // MARK: - Record / snapshot / reset

    public func record(transcript: String, audioSeconds: TimeInterval) {
        guard trackingEnabled else { return }
        let words = Self.wordCount(transcript)
        store.set(currentWords + words, forKey: Keys.wordsDictated)
        store.set(currentAudio + audioSeconds, forKey: Keys.audioSeconds)
        store.set(currentCount + 1, forKey: Keys.dictationCount)
        if currentFirstRecordedAt == 0 {
            store.set(Date().timeIntervalSince1970, forKey: Keys.firstRecordedAt)
        }
    }

    public func snapshot() -> UsageStatsSnapshot {
        UsageStatsSnapshot(
            wordsDictated: currentWords,
            audioSeconds: currentAudio,
            dictationCount: currentCount,
            firstRecordedAt: currentFirstRecordedAt > 0
                ? Date(timeIntervalSince1970: currentFirstRecordedAt)
                : nil
        )
    }

    public func reset() {
        store.removeObject(forKey: Keys.wordsDictated)
        store.removeObject(forKey: Keys.audioSeconds)
        store.removeObject(forKey: Keys.dictationCount)
        store.removeObject(forKey: Keys.firstRecordedAt)
    }

    public func exportJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(snapshot())
    }

    // MARK: - UserDefaults accessors

    private var currentWords: Int { store.integer(forKey: Keys.wordsDictated) }
    private var currentAudio: TimeInterval { store.double(forKey: Keys.audioSeconds) }
    private var currentCount: Int { store.integer(forKey: Keys.dictationCount) }
    private var currentFirstRecordedAt: TimeInterval { store.double(forKey: Keys.firstRecordedAt) }

    private enum Keys {
        static let wordsDictated   = "com.openquack.stats.wordsDictated"
        static let audioSeconds    = "com.openquack.stats.audioSeconds"
        static let dictationCount  = "com.openquack.stats.dictationCount"
        static let firstRecordedAt = "com.openquack.stats.firstRecordedAt"
        static let trackingEnabled = "com.openquack.stats.trackingEnabled"
    }

    // MARK: - Word counting (script-aware)

    /// Whitespace-split for Latin / Cyrillic / Arabic / etc.; character count
    /// for CJK ranges (Unified `0x4E00..0x9FFF`, Japanese kana
    /// `0x3040..0x30FF`, Hangul syllables `0xAC00..0xD7AF`). Mixed strings sum
    /// both methods on disjoint runs of like-classed graphemes.
    ///
    /// SPEC-013 / SPEC-007: this duplicates the heuristic SPEC-007's polish
    /// pipeline will eventually centralise. Pick one home when SPEC-007 lands.
    internal static func wordCount(_ text: String) -> Int {
        var total = 0
        var run = ""
        var runIsCJK: Bool? = nil

        for ch in text {
            let cjk = isCJKLike(ch)
            if runIsCJK == nil {
                runIsCJK = cjk
                run.append(ch)
            } else if cjk == runIsCJK {
                run.append(ch)
            } else {
                total += countRun(run, isCJK: runIsCJK!)
                run = String(ch)
                runIsCJK = cjk
            }
        }
        if let isCJK = runIsCJK {
            total += countRun(run, isCJK: isCJK)
        }
        return total
    }

    private static func countRun(_ run: String, isCJK: Bool) -> Int {
        if isCJK {
            return run.count
        }
        // Whitespace-split, drop empty tokens (handles leading/trailing/multiple spaces).
        return run.split(whereSeparator: \.isWhitespace).count
    }

    private static func isCJKLike(_ c: Character) -> Bool {
        for scalar in c.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v)        // CJK Unified
                || (0x3040...0x30FF).contains(v)    // Hiragana + Katakana
                || (0xAC00...0xD7AF).contains(v)    // Hangul Syllables
            {
                return true
            }
        }
        return false
    }
}

/// Snapshot of the current counter state. Codable so the "Export…" button
/// can write a self-contained JSON file the user owns.
public struct UsageStatsSnapshot: Sendable, Codable {
    public let wordsDictated: Int
    public let audioSeconds: TimeInterval
    public let dictationCount: Int
    public let firstRecordedAt: Date?

    public init(
        wordsDictated: Int,
        audioSeconds: TimeInterval,
        dictationCount: Int,
        firstRecordedAt: Date?
    ) {
        self.wordsDictated = wordsDictated
        self.audioSeconds = audioSeconds
        self.dictationCount = dictationCount
        self.firstRecordedAt = firstRecordedAt
    }

    /// `time_saved = words / typing_wpm × 60 − audio_seconds`, floored at 0.
    /// Caller supplies the WPM so power typists aren't lied to and slow
    /// typists aren't underwhelmed (Settings exposes a stepper).
    public func timeSaved(typingWordsPerMinute: Int) -> TimeInterval {
        let typingSeconds = Double(wordsDictated) / Double(typingWordsPerMinute) * 60
        return max(0, typingSeconds - audioSeconds)
    }
}
