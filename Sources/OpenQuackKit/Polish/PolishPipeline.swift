import Foundation

/// Orchestrates the optional LLM step then the regex `TextPolisher`. Order:
/// LLM first (better structure), regex second (whitespace/casing leftovers).
/// LLM failure is swallowed — paste must never block on polish.
public enum PolishPipeline {
    public static func polish(
        _ raw: String,
        engine: TextPolishEngine?,
        regexEnabled: Bool,
        context: PolishContext
    ) async -> String {
        var text = raw
        if let engine {
            do {
                text = try await engine.polish(raw, context: context)
            } catch {
                text = raw
            }
        }
        return regexEnabled ? TextPolisher.polish(text) : text
    }
}
