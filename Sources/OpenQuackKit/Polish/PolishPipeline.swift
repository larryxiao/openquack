import Foundation

/// Helpers that wire `TextPolishEngine` into the dictation pipeline.
///
/// PR #3 of SPEC-007. Keeps the AppDelegate integration thin: a factory
/// that resolves user settings into an engine instance, and a single-call
/// "apply polish, fall back on failure" wrapper. Both are pure functions
/// over their inputs so they can be unit-tested without an app.
public enum PolishPipeline {

    /// Build a `TextPolishEngine` from user settings, or return `nil` if
    /// polish is off / not yet configured. The caller treats `nil` exactly
    /// like an engine that throws — the dictation pipeline still runs the
    /// regex `TextPolisher` afterward.
    ///
    /// Returning `nil` (instead of an `OffEngine` instance) is deliberate:
    /// the caller's `if let engine = ...` short-circuit avoids the Swift
    /// Concurrency cost of an unnecessary `await` on the no-op path.
    public static func makeEngine(
        kind: PolishEngineKind,
        ollamaURL: URL,
        ollamaModel: String,
        urlSession: URLSession = .shared
    ) -> TextPolishEngine? {
        switch kind {
        case .off:
            return nil
        case .ollama:
            // Empty model = user hasn't picked one yet. Treat as off so we
            // don't issue a request the daemon will 404 on.
            guard !ollamaModel.trimmingCharacters(in: .whitespaces).isEmpty else {
                return nil
            }
            return OllamaPolishEngine(
                endpoint: ollamaURL,
                model: ollamaModel,
                urlSession: urlSession
            )
        case .mlxLM:
            // PR #5 of SPEC-007 lands MLXLMPolishEngine. Until then, treat
            // as off so a half-configured Settings pane doesn't drop the
            // user's transcript on the floor.
            return nil
        }
    }

    /// Apply LLM polish if the engine is configured. On any throw or `nil`
    /// engine, return the input unchanged so the caller's regex polish
    /// (`TextPolisher.polish`) can still run as the safety net.
    ///
    /// This wrapper is the *only* place LLM-polish errors are caught in the
    /// dictation hot path. Engines must throw on any failure (timeout,
    /// model not loaded, decode error) — they must not return a partial /
    /// broken polished string. See `PolishError` for the cases.
    public static func applyLLMPolish(
        _ raw: String,
        engine: TextPolishEngine?,
        context: PolishContext
    ) async -> String {
        guard let engine else { return raw }
        do {
            return try await engine.polish(raw, context: context)
        } catch {
            // The caller has the original `raw` text via the regex polish
            // step, so a swallowed error here is the right call. We do not
            // log because the dictation hot path is also the privacy hot
            // path — engine identity / failure mode is not for telemetry.
            return raw
        }
    }
}
