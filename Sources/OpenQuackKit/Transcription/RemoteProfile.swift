import Foundation

/// SPEC-044 — where a remote transcription request goes and how it proves
/// identity. The secret itself never lives here: engines fetch it from a
/// `CredentialStore` keyed by the endpoint's host, so a profile whose URL is
/// later edited can never carry the old host's credential to the new one.
public struct RemoteProfile: Sendable, Equatable {
    public var baseURL: URL
    public var model: String
    public var auth: RemoteAuth

    public init(baseURL: URL, model: String, auth: RemoteAuth) {
        self.baseURL = baseURL
        self.model = model
        self.auth = auth
    }

    /// POST target: `{base}/audio/transcriptions` (OpenAI-compatible), unless
    /// the user already pasted the full path.
    public var requestURL: URL {
        if baseURL.path.hasSuffix("/audio/transcriptions") { return baseURL }
        return baseURL
            .appendingPathComponent("audio")
            .appendingPathComponent("transcriptions")
    }
}

public enum RemoteAuth: Sendable, Equatable {
    case none
    case bearer                 // Authorization: Bearer <secret>
    case header(name: String)   // <name>: <secret>
}
