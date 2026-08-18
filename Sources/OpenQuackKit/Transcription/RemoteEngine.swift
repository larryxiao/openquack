import Foundation

/// SPEC-044 — transcription over an OpenAI-compatible HTTP endpoint
/// (`POST {base}/audio/transcriptions`, multipart WAV upload). Strictly
/// opt-in: nothing in the default dictation path constructs this engine.
public final class RemoteEngine: TranscriptionEngine {
    public static let engineName = "Remote"
    public static let suggestedModels = ["whisper-1"]

    public let modelID: String

    private let profile: RemoteProfile
    private let credentials: any CredentialStore
    private let session: URLSession

    public init(
        profile: RemoteProfile,
        credentials: any CredentialStore = KeychainCredentialStore(),
        session: URLSession? = nil
    ) {
        self.profile = profile
        self.credentials = credentials
        self.modelID = profile.model
        // Ephemeral: a transcript response must never land in URLCache on disk.
        self.session = session ?? {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 60
            cfg.timeoutIntervalForResource = 300
            return URLSession(configuration: cfg)
        }()
    }

    public func transcribe(audioFile url: URL, language: String?) async throws -> EngineTranscription {
        let start = Date()
        let target = profile.requestURL
        try Self.validate(endpoint: target)

        let upload = try AudioResampler.wav16kMono(from: url)
        defer { try? FileManager.default.removeItem(at: upload.url) }
        let audio = try Data(contentsOf: upload.url)

        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        try attachAuth(to: &request, target: target)
        let boundary = "openquack-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            audio: audio,
            model: profile.model,
            language: language
        )

        // Redirects are refused: audio + credential go only to the host the
        // user configured, never wherever a 3xx points.
        let (data, response) = try await session.data(for: request, delegate: RedirectRefusal.shared)
        guard let http = response as? HTTPURLResponse else {
            throw EngineError.runtimeFailed("Remote endpoint returned a non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data.prefix(300), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Detail goes on its own line: callers that persist diagnostics keep
            // only the first line, since a server's error body may echo secrets.
            throw EngineError.runtimeFailed(
                "Remote endpoint returned HTTP \(http.statusCode)"
                + (detail.isEmpty ? "" : ":\n\(detail)")
            )
        }

        return EngineTranscription(
            text: try Self.parseText(from: data),
            detectedLanguage: nil,
            audioSeconds: upload.seconds,
            wallSeconds: Date().timeIntervalSince(start),
            timeToFirstToken: nil
        )
    }

    private final class RedirectRefusal: NSObject, URLSessionTaskDelegate {
        static let shared = RedirectRefusal()
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? { nil }
    }

    /// Plain HTTP is allowed only for loopback (local whisper.cpp/Ollama-style
    /// servers); anything else must be HTTPS.
    static func validate(endpoint: URL) throws {
        guard let host = endpoint.host, !host.isEmpty else {
            throw EngineError.runtimeFailed("Remote endpoint URL has no host — check Settings → General.")
        }
        guard endpoint.user == nil, endpoint.password == nil else {
            throw EngineError.runtimeFailed("Remote endpoint URL must not embed credentials — use the API key field in Settings instead.")
        }
        let loopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard endpoint.scheme == "https" || (endpoint.scheme == "http" && loopback) else {
            throw EngineError.runtimeFailed("Remote endpoint must use https (plain http is only allowed for localhost).")
        }
    }

    private func attachAuth(to request: inout URLRequest, target: URL) throws {
        // Secrets are looked up by the *request's* host, so an edited URL can
        // never be sent a credential saved for a different host.
        func secret() throws -> String {
            guard let host = target.host,
                  let secret = credentials.secret(forHost: host), !secret.isEmpty
            else {
                throw EngineError.runtimeFailed("No API key saved for \(target.host ?? "this endpoint") — enter it in Settings → General.")
            }
            return secret
        }
        switch profile.auth {
        case .none:
            break
        case .bearer:
            request.setValue("Bearer \(try secret())", forHTTPHeaderField: "Authorization")
        case .header(let name):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                throw EngineError.runtimeFailed("Custom auth header name is empty — set it in Settings → General.")
            }
            request.setValue(try secret(), forHTTPHeaderField: trimmed)
        case .cloudflareAccess:
            // Namespaced slot: never reads (or clobbers) a Bearer/header key
            // saved for the same host. Unparseable contents = not signed in.
            guard let host = target.host,
                  let jwt = credentials.secret(forHost: CloudflareAccessClient.credentialKey(forHost: host)),
                  !jwt.isEmpty, CloudflareAccessClient.expiry(of: jwt) != nil
            else {
                throw EngineError.runtimeFailed("Not signed in to \(target.host ?? "this endpoint") — sign in in Settings → General.")
            }
            // An expired Access token reads as a *failed* authentication
            // server-side — refuse to send it rather than let it burn.
            guard CloudflareAccessClient.isUsable(jwt) else {
                throw EngineError.runtimeFailed("Access session expired — sign in again in Settings → General.")
            }
            request.setValue(jwt, forHTTPHeaderField: "cf-access-token")
        }
    }

    static func multipartBody(boundary: String, audio: Data, model: String, language: String?) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        if !model.isEmpty { field("model", model) }
        if let language, !language.isEmpty { field("language", language) }
        field("response_format", "json")
        body.append(Data((
            "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n"
            + "Content-Type: audio/wav\r\n\r\n"
        ).utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    /// Accepts the OpenAI `json` shape (`{"text": …}`); falls back to a plain
    /// UTF-8 body for servers that ignore `response_format`.
    static func parseText(from data: Data) throws -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = object["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let text = String(data: data, encoding: .utf8),
           !text.isEmpty, text.first != "{", text.first != "[" {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw EngineError.runtimeFailed("Remote endpoint response had no \"text\" field")
    }
}
