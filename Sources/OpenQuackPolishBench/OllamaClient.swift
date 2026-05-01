import Foundation

public struct OllamaChatResponse: Decodable, Sendable {
    public let model: String
    public let message: Message
    public let done: Bool
    public let totalDuration: Int64?
    public let loadDuration: Int64?
    public let promptEvalCount: Int?
    public let promptEvalDuration: Int64?
    public let evalCount: Int?
    public let evalDuration: Int64?

    public struct Message: Decodable, Sendable {
        public let role: String
        public let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model, message, done
        case totalDuration      = "total_duration"
        case loadDuration       = "load_duration"
        case promptEvalCount    = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount          = "eval_count"
        case evalDuration       = "eval_duration"
    }
}

public struct OllamaClient: Sendable {
    public let baseURL: URL
    public let timeout: TimeInterval

    public init(baseURL: URL = URL(string: "http://localhost:11434")!,
                timeout: TimeInterval = 90) {
        self.baseURL = baseURL
        self.timeout = timeout
    }

    /// Hit /api/chat with stream=false. Returns the full response including
    /// timing fields the bench needs. Throws on transport / decode failure.
    public func chat(
        model: String,
        system: String,
        user: String,
        temperature: Double,
        numPredict: Int,
        keepAlive: String = "-1"
    ) async throws -> OllamaChatResponse {
        let url = baseURL.appendingPathComponent("api/chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user],
            ],
            "stream": false,
            "think": false,
            "keep_alive": keepAlive,
            "options": [
                "temperature": temperature,
                "num_predict": numPredict,
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout * 2
        let session = URLSession(configuration: cfg)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            throw NSError(domain: "OllamaClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Ollama HTTP error: \(resp). Body: \(snippet)"
            ])
        }
        return try JSONDecoder().decode(OllamaChatResponse.self, from: data)
    }

    /// Pre-load the model into memory without generating output. Useful to
    /// separate cold-start latency from the first real call's wall time.
    public func warm(model: String) async throws {
        let url = baseURL.appendingPathComponent("api/chat")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout

        let body: [String: Any] = [
            "model": model,
            "messages": [],
            "keep_alive": "-1",
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "OllamaClient", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "warm() failed: \(resp)"
            ])
        }
    }

    /// Tear down a held model so the next bench run starts cold.
    public func unload(model: String) async throws {
        let url = baseURL.appendingPathComponent("api/generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body: [String: Any] = [
            "model": model,
            "keep_alive": 0,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: req)
    }

    public func listModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "OllamaClient", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "list failed: \(resp)"
            ])
        }
        struct TagsResponse: Decodable { let models: [Model]; struct Model: Decodable { let name: String } }
        return try JSONDecoder().decode(TagsResponse.self, from: data).models.map(\.name)
    }
}
