import Foundation

/// `TextPolishEngine` that talks to a locally-running Ollama daemon over
/// HTTP at `localhost:11434/api/chat` (configurable). Loopback only — the
/// engine reports `requiresNetwork = false` because the privacy contract
/// distinguishes "off-device" from "in-process / loopback."
///
/// Failure modes (network refused, daemon not running, model not pulled,
/// decode error, timeout) all throw a `PolishError` so the caller can fall
/// back to the regex polish without surfacing engine internals.
///
/// SPEC-007 PR #2 of the atomic sequence. The engine intentionally does
/// not stream: the polished text is delivered as one paste, and partial
/// polished output is worse UX than the raw transcript.
public final class OllamaPolishEngine: TextPolishEngine {
    public static let engineName = "ollama"
    public let requiresNetwork = false
    public let modelLabel: String

    private let endpoint: URL
    private let model: String
    private let systemPrompt: String
    private let urlSession: URLSession
    private let timeoutSeconds: TimeInterval

    /// - Parameters:
    ///   - endpoint: Ollama chat URL. Default `http://localhost:11434/api/chat`.
    ///   - model: Ollama model tag (e.g. `gemma3:1b`, `qwen2.5:3b-instruct`).
    ///   - systemPrompt: System message; defaults to `defaultSystemPrompt`.
    ///   - urlSession: Inject a custom session for tests (URLProtocol-mocked).
    ///   - timeoutSeconds: Request timeout; per spec, 8s for first byte.
    public init(
        endpoint: URL = OllamaPolishEngine.defaultEndpoint,
        model: String,
        systemPrompt: String = OllamaPolishEngine.defaultSystemPrompt,
        urlSession: URLSession = .shared,
        timeoutSeconds: TimeInterval = 8
    ) {
        self.endpoint = endpoint
        self.model = model
        self.systemPrompt = systemPrompt
        self.urlSession = urlSession
        self.timeoutSeconds = timeoutSeconds
        self.modelLabel = "\(model) (Ollama)"
    }

    public func polish(_ raw: String, context: PolishContext) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        let body = try Self.encodeRequest(
            model: model,
            systemPrompt: systemPrompt,
            userText: trimmed,
            wordCount: Self.wordCount(trimmed)
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw PolishError.timeout
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost
            || urlError.code == .cannotFindHost
            || urlError.code == .networkConnectionLost
            || urlError.code == .notConnectedToInternet {
            throw PolishError.backendUnavailable(urlError.localizedDescription)
        } catch {
            throw PolishError.backendUnavailable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw PolishError.decodingFailed
        }

        switch http.statusCode {
        case 200:
            break
        case 404:
            // Ollama returns 404 when the requested model isn't pulled.
            throw PolishError.modelNotLoaded(model)
        default:
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw PolishError.backendUnavailable(detail)
        }

        do {
            let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
            let polished = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            // If the model returned nothing useful, fall back rather than
            // silently overwrite with empty.
            return polished.isEmpty ? raw : polished
        } catch {
            throw PolishError.decodingFailed
        }
    }

    // MARK: - Defaults

    public static let defaultEndpoint = URL(string: "http://localhost:11434/api/chat")!

    /// Ported in spirit from v0.1 `thinker.py`. Kept at file scope so it can
    /// be diff'd / overridden cleanly without touching the engine code.
    public static let defaultSystemPrompt = """
        You reorganise raw voice transcriptions into clean, structured text.

        You MUST:
        - Respond in the SAME language as the input.
        - Add correct punctuation (。，for Chinese; periods, commas for English; etc.).
        - Remove filler words, verbal tics, false starts, and repetitions.
        - Remove garbled or nonsensical text (transcription errors / artefacts).
        - Organise multiple ideas into bullet points (use • or -).
        - Keep it concise — shorter than the input.
        - Preserve all technical terms, proper nouns, and names exactly as spoken.
        - Output ONLY the reorganised text — no commentary, labels, or markdown fences.
        """

    // MARK: - Internals (visible to tests via @testable)

    /// Word count that treats CJK characters as individual words. Mirrors the
    /// v0.1 fast-path heuristic so non-English transcripts get a sensible
    /// `num_predict` budget rather than a tiny one based on space-separated
    /// counts that aren't meaningful for CJK.
    static func wordCount(_ text: String) -> Int {
        let cjkRanges: [ClosedRange<UInt32>] = [
            0x4E00...0x9FFF,   // CJK Unified Ideographs
            0x3040...0x309F,   // Hiragana
            0x30A0...0x30FF,   // Katakana
            0xAC00...0xD7AF,   // Hangul Syllables
        ]
        var cjkCount = 0
        var stripped = ""
        for char in text {
            var isCJK = false
            for scalar in char.unicodeScalars {
                if cjkRanges.contains(where: { $0.contains(scalar.value) }) {
                    isCJK = true
                    break
                }
            }
            if isCJK {
                cjkCount += 1
            } else {
                stripped.append(char)
            }
        }
        let nonCJKWords = stripped
            .split(whereSeparator: { $0.isWhitespace })
            .filter { !$0.isEmpty }
            .count
        return cjkCount + nonCJKWords
    }

    static func numPredict(forWords wordCount: Int) -> Int {
        // SPEC-007: min(max(wordCount * 2, 80), 1024)
        return min(max(wordCount * 2, 80), 1024)
    }

    static func temperature(forWords wordCount: Int) -> Double {
        // SPEC-007: 0.3 short (≤50), 0.5 longer.
        wordCount <= 50 ? 0.3 : 0.5
    }

    /// Build the request body. Exposed for tests.
    static func encodeRequest(
        model: String,
        systemPrompt: String,
        userText: String,
        wordCount: Int
    ) throws -> Data {
        let payload = OllamaChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userText),
            ],
            stream: false,
            keepAlive: -1,
            think: false,
            options: .init(
                temperature: temperature(forWords: wordCount),
                numPredict: numPredict(forWords: wordCount)
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }
}

// MARK: - Wire types

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let keepAlive: Int
    let think: Bool
    let options: Options

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Options: Encodable {
        let temperature: Double
        let numPredict: Int

        enum CodingKeys: String, CodingKey {
            case temperature
            case numPredict = "num_predict"
        }
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, options, think
        case keepAlive = "keep_alive"
    }
}

private struct OllamaChatResponse: Decodable {
    let message: Message

    struct Message: Decodable {
        let content: String
    }
}
