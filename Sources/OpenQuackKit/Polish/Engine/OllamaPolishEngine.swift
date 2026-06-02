import Foundation

/// In-process polish via a local Ollama daemon over loopback HTTP. Not a
/// network engine in the privacy sense — `localhost` only. Any failure
/// (unreachable, non-2xx, timeout, empty output) throws so the caller falls
/// back to the regex pipeline.
public struct OllamaPolishEngine: TextPolishEngine {
    public let model: String
    let baseURL: URL
    let session: URLSession

    public var modelLabel: String { model }

    public init(
        model: String = "gemma4-textonly:Q4_K_M",
        baseURL: URL = URL(string: "http://localhost:11434")!,
        session: URLSession = .shared
    ) {
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Wire types

    struct ChatRequest: Encodable {
        let model: String
        let stream: Bool
        let think: Bool
        let keep_alive: Int
        let messages: [Message]
        let options: Options

        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct Options: Encodable {
            let temperature: Double
            let num_predict: Int
        }
    }

    struct ChatResponse: Decodable {
        let message: Message
        struct Message: Decodable { let content: String }
    }

    enum PolishError: Error {
        case badStatus(Int)
        case emptyOutput
    }

    /// Pure builder — no I/O — so the critical flags are unit-testable.
    static func makeRequest(model: String, raw: String) -> ChatRequest {
        ChatRequest(
            model: model,
            stream: false,
            think: false,
            keep_alive: -1,
            messages: [
                .init(role: "system", content: PolishPrompt.system),
                .init(role: "user", content: PolishPrompt.userMessage(raw)),
            ],
            options: .init(temperature: PolishPrompt.temperature, num_predict: PolishPrompt.numPredict(raw))
        )
    }

    public func polish(_ raw: String, context: PolishContext) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Self.makeRequest(model: model, raw: raw))

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PolishError.badStatus(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let out = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { throw PolishError.emptyOutput }
        return out
    }
}
