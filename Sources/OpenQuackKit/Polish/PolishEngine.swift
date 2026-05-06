import Foundation

/// A pluggable text-polish backend that runs *after* WhisperKit produces a
/// raw transcript and *before* the regex-based `TextPolisher` fallback.
///
/// Implementers wrap a local LLM (Ollama HTTP, MLX-LM in-process, or a
/// future engine) and clean up multi-clause runs, restructure into bullets
/// where appropriate, and disambiguate proper nouns Whisper guessed wrong
/// ("cloud code" → "Claude Code"). The full contract lives in
/// `docs/SPECS/SPEC-007-llm-polish.md`.
///
/// Failure mode: throw. The caller catches and falls back to the regex
/// pipeline, so partial / broken polish never reaches the user.
public protocol TextPolishEngine: AnyObject, Sendable {
    /// Stable identifier for logging / settings round-trip. Lowercase, no
    /// spaces. Matches `PolishEngineKind.rawValue` for the corresponding
    /// kind.
    static var engineName: String { get }

    /// Whether running this engine sends bytes off the host. Loopback
    /// (Ollama at `localhost`) and in-process (MLX-LM) both report `false`.
    /// The recording overlay reads this to decide whether to render the
    /// network indicator.
    var requiresNetwork: Bool { get }

    /// Display label for the status row in Settings. e.g. "gemma3:1b
    /// (Ollama)" or "Qwen2.5-1.5B-Instruct-4bit (MLX-LM)".
    var modelLabel: String { get }

    /// Polish the given raw transcript.
    ///
    /// Implementations should:
    /// - Be idempotent on already-clean input (`polish(clean) ≈ clean`).
    /// - Preserve the input language (no translation).
    /// - Preserve technical terms / proper nouns / names exactly.
    /// - Throw on any failure (timeout, OOM, model not loaded, decode
    ///   error). The caller catches and falls back.
    func polish(_ raw: String, context: PolishContext) async throws -> String
}

/// Per-call hints that engines may use (or ignore). Engines must tolerate
/// `nil` for every optional field — context is best-effort.
public struct PolishContext: Sendable, Equatable {
    /// BCP-47-ish language tag, e.g. "en", "zh", "ja". `nil` means
    /// "engine should infer or use its default."
    public let language: String?

    /// User-visible name of the foreground app at capture time, if known.
    /// e.g. "Cursor", "Slack". Used by future per-app polish profiles
    /// (SPEC-008); current engines ignore it.
    public let foregroundApp: String?

    /// When the audio was captured (not when polish was invoked). Engines
    /// generally don't read this; carried for telemetry-free diagnostics.
    public let timestamp: Date

    public init(
        language: String? = nil,
        foregroundApp: String? = nil,
        timestamp: Date = Date()
    ) {
        self.language = language
        self.foregroundApp = foregroundApp
        self.timestamp = timestamp
    }
}

/// User-selected polish backend. `off` skips the LLM step entirely and the
/// pipeline runs the regex `TextPolisher` only — same behaviour as today.
public enum PolishEngineKind: String, CaseIterable, Sendable {
    case off
    case ollama
    case mlxLM = "mlx-lm"
}

/// Errors a polish engine can raise. Conforms to `LocalizedError` so a
/// future Settings pane can surface a one-line user-readable description
/// without each call site duplicating the switch.
public enum PolishError: Error, LocalizedError, Equatable {
    /// The engine has no model configured (Ollama URL unreachable, MLX-LM
    /// model not downloaded). The user needs to fix it in Settings.
    case notConfigured

    /// The engine started but the model is not loaded yet. Caller may retry
    /// after a short delay; for now we just fall back.
    case modelNotLoaded(String)

    /// Engine took longer than its timeout. Default budget is 8 s for the
    /// first byte; tunable per engine.
    case timeout

    /// The backend (Ollama daemon, MLX-LM runtime) returned an error or is
    /// unreachable. The associated string is the underlying message,
    /// surfaced verbatim for diagnostics.
    case backendUnavailable(String)

    /// The backend returned a response we couldn't parse as text. Almost
    /// always indicates an API-shape mismatch with our request.
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Polish engine isn't configured. Open Settings → Polish to pick one."
        case .modelNotLoaded(let label):
            return "Polish model isn't loaded yet (\(label))."
        case .timeout:
            return "Polish step timed out."
        case .backendUnavailable(let detail):
            return "Polish backend unavailable: \(detail)"
        case .decodingFailed:
            return "Polish backend returned an unexpected response."
        }
    }
}
