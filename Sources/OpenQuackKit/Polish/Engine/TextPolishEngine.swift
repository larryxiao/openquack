import Foundation

/// A pluggable LLM cleanup step that runs before the regex `TextPolisher`.
/// Implementations throw on any failure; the caller falls back to regex.
public protocol TextPolishEngine: Sendable {
    var modelLabel: String { get }
    func polish(_ raw: String, context: PolishContext) async throws -> String
}

public struct PolishContext: Sendable {
    public let language: String?
    public let timestamp: Date
    /// Custom LLM instruction body, or nil to use `PolishPrompt.defaultInstructions`.
    /// Read fresh per dictation so Settings edits take effect without a reload.
    public let systemInstructions: String?

    public init(language: String?, timestamp: Date, systemInstructions: String? = nil) {
        self.language = language
        self.timestamp = timestamp
        self.systemInstructions = systemInstructions
    }
}

/// Which polish engine runs. `mlxLM` is a future case that will implement
/// `TextPolishEngine` once MLX supports Gemma 4.
public enum PolishEngineKind: String, CaseIterable, Sendable {
    case off
    case llamaCpp
}
