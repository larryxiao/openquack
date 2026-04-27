import Foundation

/// One transcription run's measured output. Engines fill what they know;
/// fields they don't measure are nil.
public struct EngineTranscription: Sendable {
    public var text: String
    public var detectedLanguage: String?
    public var audioSeconds: TimeInterval     // length of input
    public var wallSeconds: TimeInterval      // wall-clock spent inside transcribe()
    public var timeToFirstToken: TimeInterval?

    public init(
        text: String,
        detectedLanguage: String? = nil,
        audioSeconds: TimeInterval,
        wallSeconds: TimeInterval,
        timeToFirstToken: TimeInterval? = nil
    ) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.audioSeconds = audioSeconds
        self.wallSeconds = wallSeconds
        self.timeToFirstToken = timeToFirstToken
    }
}

public enum EngineError: Error, CustomStringConvertible {
    case modelNotSupported(String)
    case loadFailed(String)
    case runtimeFailed(String)

    public var description: String {
        switch self {
        case .modelNotSupported(let m): return "Model not supported: \(m)"
        case .loadFailed(let s):        return "Engine load failed: \(s)"
        case .runtimeFailed(let s):     return "Engine runtime failed: \(s)"
        }
    }
}

public protocol TranscriptionEngine: AnyObject {
    static var engineName: String { get }
    /// Suggested models — engines may accept other identifiers; this is a hint for `--help`.
    static var suggestedModels: [String] { get }

    var modelID: String { get }

    func transcribe(audioFile url: URL, language: String?) async throws -> EngineTranscription
}

public enum EngineKind: String, CaseIterable, Sendable {
    case whisperkit
    case lightning

    public static func parse(_ s: String) throws -> EngineKind {
        guard let k = EngineKind(rawValue: s.lowercased()) else {
            let known = allCases.map(\.rawValue).joined(separator: ", ")
            throw EngineError.runtimeFailed("Unknown engine: \(s) (known: \(known))")
        }
        return k
    }

    public var suggestedModels: [String] {
        switch self {
        case .whisperkit: return WhisperKitEngine.suggestedModels
        case .lightning:  return LightningEngine.suggestedModels
        }
    }

    /// Build the engine and return both it and the cold-start time (wall-clock from
    /// "factory call" to "ready to transcribe"). Cold-start includes model download
    /// on first run; subsequent runs read from disk cache.
    public func makeEngine(model: String) async throws -> (engine: any TranscriptionEngine, coldStart: TimeInterval) {
        let t0 = Date()
        let engine: any TranscriptionEngine
        switch self {
        case .whisperkit: engine = try await WhisperKitEngine(model: model)
        case .lightning:  engine = try await LightningEngine(model: model)
        }
        return (engine, Date().timeIntervalSince(t0))
    }
}
