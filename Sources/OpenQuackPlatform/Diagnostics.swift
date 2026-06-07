import Foundation
import os

/// SPEC-036 — central diagnostics.
///
/// Two sinks for every event:
///   1. `os.Logger` (unified log) — persistent + queryable via Console.app or
///      `log show --predicate 'subsystem == "org.openquack.OpenQuack"'`.
///   2. a bounded in-memory ring — so the bug-report flow can dump recent events
///      to an attachable `.txt`; users filing a bug won't run `log show`.
///
/// Lives in `OpenQuackPlatform` so both `AudioRecorder` (OpenQuackKit) and
/// `StreamingTranscriber` (OpenQuackStreaming) can log through one place.
public enum DiagCategory: String, Sendable, CaseIterable {
    case recording
    case streaming
    case transcription
    case app
}

/// Severity, kept independent of `OSLogType` so the renderer and tests don't
/// pull in `os`.
public enum DiagLevel: String, Sendable {
    case info
    case warn
    case error

    var osLogType: OSLogType {
        switch self {
        case .info:  return .info
        case .warn:  return .error   // unified log has no "warn"; .error surfaces it
        case .error: return .fault
        }
    }

    /// Single-char marker for the text dump.
    public var marker: String {
        switch self {
        case .info:  return " "
        case .warn:  return "⚠"
        case .error: return "✗"
        }
    }
}

public struct DiagEvent: Sendable, Equatable {
    public let time: Date
    public let category: DiagCategory
    public let level: DiagLevel
    public let message: String

    public init(time: Date, category: DiagCategory, level: DiagLevel, message: String) {
        self.time = time
        self.category = category
        self.level = level
        self.message = message
    }
}

public final class Diagnostics: @unchecked Sendable {
    public static let shared = Diagnostics()

    private static let subsystem = "org.openquack.OpenQuack"
    private let loggers: [DiagCategory: Logger]
    private let lock = NSLock()
    private var ring: [DiagEvent] = []

    /// Cap on retained events. ~300 covers many minutes of lifecycle + per-chunk
    /// events (chunks are ~20 s apart) without unbounded growth.
    public let capacity: Int

    public init(capacity: Int = 300) {
        self.capacity = capacity
        var m: [DiagCategory: Logger] = [:]
        for c in DiagCategory.allCases {
            m[c] = Logger(subsystem: Self.subsystem, category: c.rawValue)
        }
        loggers = m
    }

    public func log(_ category: DiagCategory, _ level: DiagLevel = .info, _ message: String) {
        loggers[category]?.log(level: level.osLogType, "\(message, privacy: .public)")
        let e = DiagEvent(time: Date(), category: category, level: level, message: message)
        lock.lock()
        ring.append(e)
        if ring.count > capacity { ring.removeFirst(ring.count - capacity) }
        lock.unlock()
    }

    /// Snapshot of retained events, oldest-first.
    public func recentEvents() -> [DiagEvent] {
        lock.lock(); defer { lock.unlock() }
        return ring
    }

    /// Test/maintenance hook.
    public func clear() {
        lock.lock(); ring.removeAll(keepingCapacity: true); lock.unlock()
    }
}
