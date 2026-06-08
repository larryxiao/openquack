import Foundation

/// Outcome of a polish run. `text` is what to paste; the rest is diagnostic
/// (drives the debug panel — never affects paste).
public struct PolishResult: Sendable {
    public let text: String
    public let llmRan: Bool        // an engine was attempted (engine != nil)
    public let llmSucceeded: Bool  // engine returned; false ⇒ fell back to raw
    public let llmMillis: Int?     // engine-call duration; nil when no engine ran
}

/// Orchestrates the optional LLM step then the regex `TextPolisher`. Order:
/// LLM first (better structure), regex second (whitespace/casing leftovers).
/// LLM failure is swallowed — paste must never block on polish.
public enum PolishPipeline {
    public static func polish(
        _ raw: String,
        engine: TextPolishEngine?,
        regexEnabled: Bool,
        context: PolishContext
    ) async -> PolishResult {
        var text = raw
        var llmRan = false
        var llmSucceeded = false
        var llmMillis: Int?
        if let engine {
            llmRan = true
            let start = Date()
            do {
                text = try await engine.polish(raw, context: context)
                llmSucceeded = true
            } catch {
                text = raw
            }
            llmMillis = Int(Date().timeIntervalSince(start) * 1000)
        }
        let cleaned = regexEnabled ? TextPolisher.polish(text) : text
        let final = joinToSingleLine(cleaned)
        return PolishResult(text: final, llmRan: llmRan, llmSucceeded: llmSucceeded, llmMillis: llmMillis)
    }

    /// Backstop: the pasted transcript is always one line. The LLM may add
    /// paragraph/line breaks, and the regex pass only collapses runs of 2+
    /// whitespace — a lone `\n` survives both — so flatten unconditionally.
    private static func joinToSingleLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
