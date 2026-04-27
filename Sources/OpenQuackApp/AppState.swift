import Foundation
import Combine

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
    @Published public var lastTranscript: String?
    @Published public var lastAudioSeconds: Double?
    @Published public var lastWallSeconds: Double?
    @Published public var lastRecordingURL: URL?
    @Published public var modelLabel: String = "whisperkit medium · en"

    public init() {}
}
