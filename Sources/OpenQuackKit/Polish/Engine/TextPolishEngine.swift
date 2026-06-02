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

    public init(language: String?, timestamp: Date) {
        self.language = language
        self.timestamp = timestamp
    }
}

/// Which polish engine runs. `llamaCppEmbed` / `mlxLM` are future cases that
/// will implement `TextPolishEngine`; this slice ships only `.ollama`.
public enum PolishEngineKind: String, CaseIterable, Sendable {
    case off
    case ollama
}
