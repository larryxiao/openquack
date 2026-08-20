import Foundation

/// SPEC-044 — where a remote transcription request goes and how it proves
/// identity. The secret itself never lives here: engines fetch it from a
/// `CredentialStore` keyed by the endpoint's host, so a profile whose URL is
/// later edited can never carry the old host's credential to the new one.
public struct RemoteProfile: Sendable, Equatable {
    /// Sent when `userAgent` is empty. Deliberately neutral: the endpoint
    /// learns nothing about which app is calling.
    public static let defaultUserAgent = "transcription-client/1.0"

    public var baseURL: URL
    public var model: String
    public var auth: RemoteAuth
    public var userAgent: String

    public init(baseURL: URL, model: String, auth: RemoteAuth, userAgent: String = "") {
        self.baseURL = baseURL
        self.model = model
        self.auth = auth
        self.userAgent = userAgent
    }

    /// The `User-Agent` value to send: the configured one (folded to a single
    /// header line), or the neutral default when unset.
    public var resolvedUserAgent: String {
        let folded = userAgent
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return folded.isEmpty ? Self.defaultUserAgent : folded
    }

    /// POST target: `{base}/audio/transcriptions` (OpenAI-compatible), unless
    /// the user already pasted the full path (with or without trailing slash).
    public var requestURL: URL {
        // URLComponents, not URL.path — the latter silently drops a trailing
        // slash, which would defeat both the suffix check and the rebuild.
        if var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
            var path = comps.path
            while path.hasSuffix("/") { path.removeLast() }
            if path.hasSuffix("/audio/transcriptions") {
                comps.path = path
                return comps.url ?? baseURL
            }
        }
        return baseURL
            .appendingPathComponent("audio")
            .appendingPathComponent("transcriptions")
    }
}

public enum RemoteAuth: Sendable, Equatable {
    case none
    case bearer                 // Authorization: Bearer <secret>
    case header(name: String)   // <name>: <secret>
    case cloudflareAccess       // cf-access-token: <jwt via browser SSO> (SPEC-045)
}
