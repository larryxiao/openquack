import Foundation

/// SPEC-036 — pure assessment of whether capture ran to completion.
///
/// `wallSeconds` is the user-facing recording length (wall clock since `start`);
/// `capturedSeconds` is how much audio the tap actually delivered. A large
/// shortfall means the audio engine stopped feeding the tap mid-recording
/// (device/route change, interruption) — the freeze signature, where the
/// waveform stalls and only a partial transcript comes back.
public enum RecordingHealth: Equatable, Sendable {
    case ok
    /// Capture fell materially short of wall-clock; the tap likely stopped early.
    case incompleteCapture(wallSeconds: Double, capturedSeconds: Double, shortfallSeconds: Double)

    public var isIncomplete: Bool {
        if case .incompleteCapture = self { return true }
        return false
    }

    /// - Parameters:
    ///   - minShortfallSeconds: ignore gaps under this — normal teardown,
    ///     scheduling jitter, and rounding leave the captured stream a hair short.
    ///   - maxCapturedFraction: only flag when captured audio is below this
    ///     fraction of wall, so a brief sub-second hiccup on a short clip doesn't
    ///     read as a mid-recording stop.
    public static func assess(
        wallSeconds: Double,
        capturedSeconds: Double,
        minShortfallSeconds: Double = 2.0,
        maxCapturedFraction: Double = 0.85
    ) -> RecordingHealth {
        guard wallSeconds > 0 else { return .ok }
        let shortfall = wallSeconds - capturedSeconds
        if shortfall >= minShortfallSeconds, capturedSeconds < wallSeconds * maxCapturedFraction {
            return .incompleteCapture(
                wallSeconds: wallSeconds,
                capturedSeconds: capturedSeconds,
                shortfallSeconds: shortfall
            )
        }
        return .ok
    }
}
