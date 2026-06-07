import Foundation
import Combine
import OpenQuackKit

public final class AppState: ObservableObject {
    public enum Phase: Equatable {
        case warming(modelLabel: String)
        case idle
        case starting
        case recording
        case transcribing
        case ready
        case error(String)
    }

    /// SPEC-031 — which output path the *current* recording is bound for.
    /// Set when recording starts (by which hotkey fired); read at the
    /// post-transcribe dispatch fork to choose paste-at-cursor vs
    /// agent kickoff. Orthogonal to `phase`.
    public enum RecordingMode: Equatable {
        case dictation
        case agentKickoff
    }

    @Published public var phase: Phase = .warming(modelLabel: "medium")
    @Published public var recordingMode: RecordingMode = .dictation
    @Published public var elapsedSeconds: Double = 0
    @Published public var currentLevel: Float = 0  // 0…1 RMS, for the level meter
    /// Sliding window of recent RMS samples (newest on the right). Drives the
    /// bigger waveform-style level meter in the recording overlay.
    @Published public var levelHistory: [Float] = Array(repeating: 0, count: AppState.barCount)
    @Published public var transcriptionProgress: Double = 0  // 0…1, observed from WhisperKit.progress

    public static let barCount = 11

    public func pushLevel(_ level: Float) {
        currentLevel = level
        var h = levelHistory
        h.removeFirst()
        h.append(level)
        levelHistory = h
    }

    public func resetLevels() {
        currentLevel = 0
        levelHistory = Array(repeating: 0, count: Self.barCount)
    }
    @Published public var lastTranscript: String?
    @Published public var lastAudioSeconds: Double?
    @Published public var lastWallSeconds: Double?
    @Published public var lastRecordingURL: URL?
    @Published public var lastPasted: Bool = false
    /// SPEC-031 — whether the most-recent kickoff dispatch reached
    /// Terminal/`claude` successfully. Only meaningful when
    /// `recordingMode == .agentKickoff` was set during the recording.
    @Published public var lastKickoffSucceeded: Bool = false
    /// SPEC-031 — short error label for failed kickoffs, shown in the
    /// "ready" overlay state.
    @Published public var lastKickoffError: String?
    /// SPEC-036 — a transient notice shown in the "ready" overlay subline,
    /// e.g. "Recording interrupted by an audio device change". Takes priority
    /// over the transcript preview when set; cleared at the next recording.
    @Published public var lastNotice: String?
    @Published public var accessibilityTrusted: Bool = false
    @Published public var modelLabel: String = "medium"
    /// Lifecycle of an update check — drives both the menu-bar 🦆⬆
    /// indicator and the Settings → About status line. Single source of
    /// truth so a manual "Check for updates" click can flip from
    /// `.checking` to a terminal state and back to `.unknown` after a
    /// while if needed.
    @Published public var updateStatus: UpdateCheckStatus = .unknown
    @Published public var installMethod: InstallMethod = .manual

    /// Convenience for the popover banner — only present when the
    /// status terminal-states into `.available`.
    public var availableUpdate: UpdateChecker.ReleaseInfo? {
        if case .available(let release) = updateStatus { return release }
        return nil
    }

    public init() {}
}

public enum UpdateCheckStatus: Equatable {
    /// No check has run yet this launch.
    case unknown
    /// A check is in flight.
    case checking
    /// Latest reachable release is the running build.
    case upToDate(version: String, at: Date)
    /// Newer release found.
    case available(UpdateChecker.ReleaseInfo)
    /// Silent brew upgrade script is running; this instance is about to quit.
    case upgrading
    /// Last check failed (network, parse, etc).
    case failed(String)

    public var hasAvailableUpdate: Bool {
        if case .available = self { return true }
        return false
    }
}
