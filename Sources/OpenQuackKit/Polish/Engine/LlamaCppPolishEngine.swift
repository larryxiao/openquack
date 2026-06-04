import Foundation
import LlamaSwift

/// In-process polish via an embedded llama.cpp model (GGUF) loaded from a local
/// file. An actor because the loaded model/context are stateful C handles kept
/// warm across dictations — load is seconds + GBs, paid once. Any failure
/// throws so the caller falls back to the regex pipeline — same contract as
/// OllamaPolishEngine.
public actor LlamaCppPolishEngine: TextPolishEngine {
    private let modelPath: URL
    private var model: OpaquePointer?    // llama_model *
    private var ctx: OpaquePointer?      // llama_context *

    public nonisolated var modelLabel: String { modelPath.lastPathComponent }

    public init(modelPath: URL) {
        self.modelPath = modelPath
    }

    deinit {
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
    }

    enum PolishError: Error {
        case modelNotFound(URL)
        case loadFailed
        case emptyOutput
    }

    public func polish(_ raw: String, context: PolishContext) async throws -> String {
        try ensureLoaded()
        let prompt = Self.gemmaPrompt(system: PolishPrompt.system,
                                      user: PolishPrompt.userMessage(raw))
        let out = try generate(prompt: prompt, maxTokens: PolishPrompt.numPredict(raw))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { throw PolishError.emptyOutput }
        return out
    }

    /// Warm-on-record entry point; idempotent (ensureLoaded() returns early if warm).
    public func warm() throws {
        try ensureLoaded()
    }

    /// Free model + context so the ~3 GB is reclaimed; the next warm()/polish()
    /// reloads. Leaves the process-global llama backend alone (owned by backendInitOnce).
    public func unload() {
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
        ctx = nil
        model = nil
    }

    /// This Gemma 4 build's chat tokens are `<|turn>{role}` / `<turn|>` — NOT the
    /// Gemma 2/3 `<start_of_turn>`/`<end_of_turn>`. parse_special maps these to the
    /// real control tokens; the wrong markers tokenise as junk text and the model
    /// emits boilerplate. Hardcoded to this model — deriving the format from the
    /// model is a SPEC-007 follow-up.
    private static func gemmaPrompt(system: String, user: String) -> String {
        "<|turn>system\n\(system)<turn|>\n<|turn>user\n\(user)<turn|>\n<|turn>model\n"
    }

    /// Lazily load + cache model and context. Throws before any C call if the
    /// GGUF is absent — this is the path the model-free tests exercise.
    private func ensureLoaded() throws {
        if model != nil { return }
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw PolishError.modelNotFound(modelPath)
        }
        _ = Self.backendInitOnce
        let mparams = llama_model_default_params()
        guard let m = llama_model_load_from_file(modelPath.path, mparams) else {
            throw PolishError.loadFailed
        }
        var cparams = llama_context_default_params()
        cparams.n_ctx = 4096
        cparams.n_batch = 512
        guard let c = llama_init_from_model(m, cparams) else {
            llama_model_free(m)
            throw PolishError.loadFailed
        }
        model = m
        ctx = c
    }

    /// `llama_backend_init()` must run exactly once per process.
    private static let backendInitOnce: Void = { llama_backend_init() }()

    private func generate(prompt: String, maxTokens: Int) throws -> String {
        guard let model, let ctx else { throw PolishError.loadFailed }
        let vocab = llama_model_get_vocab(model)

        // Reset KV state so each dictation starts from an empty sequence (ctx is kept warm).
        llama_memory_clear(llama_get_memory(ctx), true)

        // Tokenise: first call with n_tokens_max=0 returns the negative count needed.
        let textLen = Int32(prompt.utf8.count)
        let needed = -llama_tokenize(vocab, prompt, textLen, nil, 0, true, true)
        guard needed > 0 else { throw PolishError.loadFailed }
        var tokens = [llama_token](repeating: 0, count: Int(needed))
        let count = llama_tokenize(vocab, prompt, textLen, &tokens, needed, true, true)
        guard count > 0 else { throw PolishError.loadFailed }

        // Prefill the prompt.
        let decodeResult = tokens.withUnsafeMutableBufferPointer {
            llama_decode(ctx, llama_batch_get_one($0.baseAddress, count))
        }
        guard decodeResult == 0 else { throw PolishError.loadFailed }

        // Greedy decode loop.
        let smpl = llama_sampler_init_greedy()
        defer { llama_sampler_free(smpl) }

        var outputBytes = [UInt8]()
        outputBytes.reserveCapacity(maxTokens * 4)

        for _ in 0..<maxTokens {
            let tok = llama_sampler_sample(smpl, ctx, -1)
            if llama_vocab_is_eog(vocab, tok) { break }

            // Decode token to bytes; grow buffer if needed.
            var piece = [CChar](repeating: 0, count: 16)
            var byteCount = llama_token_to_piece(vocab, tok, &piece, Int32(piece.count), 0, false)
            if byteCount < 0 {
                piece = [CChar](repeating: 0, count: Int(-byteCount))
                byteCount = llama_token_to_piece(vocab, tok, &piece, Int32(piece.count), 0, false)
            }
            if byteCount > 0 {
                piece.prefix(Int(byteCount)).forEach { outputBytes.append(UInt8(bitPattern: $0)) }
            }

            var next = tok
            let stepResult = withUnsafeMutablePointer(to: &next) {
                llama_decode(ctx, llama_batch_get_one($0, 1))
            }
            guard stepResult == 0 else { throw PolishError.loadFailed }
        }

        return String(bytes: outputBytes, encoding: .utf8) ?? String(outputBytes.map { Character(UnicodeScalar($0)) })
    }
}
