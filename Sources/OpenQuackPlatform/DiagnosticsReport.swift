import Foundation

/// SPEC-036 — pure renderer for the attachable diagnostics `.txt`.
///
/// Kept free of IO (file writing, `ProcessInfo`, `Date()` "now") so it can be
/// unit-tested deterministically; the app gathers the live values and writes the
/// returned string to `~/Library/Logs/OpenQuack/`.
public enum DiagnosticsReport {
    /// Summary of the most recent recording + transcription.
    public struct LastRecording: Sendable, Equatable {
        public let wallSeconds: Double
        public let capturedSeconds: Double
        public let health: RecordingHealth
        /// "streaming" or "offline".
        public let path: String
        public let chunkCount: Int?
        public let chunkFailures: Int?
        public let transcribeWallSeconds: Double?
        public let audioSeconds: Double?
        public let detectedLanguage: String?
        public let interrupted: Bool

        public init(
            wallSeconds: Double,
            capturedSeconds: Double,
            health: RecordingHealth,
            path: String,
            chunkCount: Int? = nil,
            chunkFailures: Int? = nil,
            transcribeWallSeconds: Double? = nil,
            audioSeconds: Double? = nil,
            detectedLanguage: String? = nil,
            interrupted: Bool = false
        ) {
            self.wallSeconds = wallSeconds
            self.capturedSeconds = capturedSeconds
            self.health = health
            self.path = path
            self.chunkCount = chunkCount
            self.chunkFailures = chunkFailures
            self.transcribeWallSeconds = transcribeWallSeconds
            self.audioSeconds = audioSeconds
            self.detectedLanguage = detectedLanguage
            self.interrupted = interrupted
        }
    }

    public static func render(
        appVersion: String,
        osVersion: String,
        chip: String,
        model: String?,
        lastRecording: LastRecording?,
        events: [DiagEvent],
        generatedAt: Date
    ) -> String {
        var lines: [String] = []
        lines.append("OpenQuack diagnostics")
        lines.append("app \(appVersion) · macOS \(osVersion) · \(chip)")
        if let model { lines.append("model: \(model)") }
        lines.append("")

        if let r = lastRecording {
            let flag = r.health.isIncomplete ? "  ⚠ INCOMPLETE CAPTURE" : ""
            lines.append("last recording:")
            lines.append(String(format: "  wall %.1fs / captured %.1fs%@", r.wallSeconds, r.capturedSeconds, flag))
            if case let .incompleteCapture(_, _, shortfall) = r.health {
                lines.append(String(format: "  shortfall %.1fs — the tap stopped feeding audio mid-recording", shortfall))
            }
            if r.interrupted {
                lines.append("  interrupted by an audio device/route change")
            }
            var t = "  \(r.path)"
            if let c = r.chunkCount { t += " · \(c) chunk\(c == 1 ? "" : "s")" }
            if let f = r.chunkFailures { t += " · \(f) failure\(f == 1 ? "" : "s")" }
            if let rtf = rtf(transcribe: r.transcribeWallSeconds, audio: r.audioSeconds) {
                t += String(format: " · RTF %.2f", rtf)
            }
            if let lang = r.detectedLanguage { t += " · lang=\(lang)" }
            lines.append(t)
        } else {
            lines.append("last recording: (none this session)")
        }
        lines.append("")

        lines.append("recent events (\(events.count)):")
        for e in events {
            let dt = e.time.timeIntervalSince(generatedAt)   // negative = in the past
            let stamp = String(format: "T%+.1fs", dt)
            lines.append("  \(stamp) \(e.level.marker) [\(e.category.rawValue)] \(e.message)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Real-time factor: transcription wall over audio length. < 1 is
    /// faster-than-realtime. nil when inputs are missing/zero.
    public static func rtf(transcribe: Double?, audio: Double?) -> Double? {
        guard let t = transcribe, let a = audio, a > 0, t > 0 else { return nil }
        return t / a
    }
}
