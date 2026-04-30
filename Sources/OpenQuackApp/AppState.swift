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

    @Published public var phase: Phase = .warming(modelLabel: "medium")
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
    @Published public var accessibilityTrusted: Bool = false
    @Published public var modelLabel: String = "medium"
    @Published public var availableUpdate: UpdateChecker.ReleaseInfo? = nil
    @Published public var lastUpdateCheckError: String? = nil
    @Published public var installMethod: InstallMethod = .manual

    public init() {}
}
