import Foundation

/// SPEC-044 — turns a thrown error into the single line the overlay and the
/// menu-bar popover show. Engines already phrase `runtimeFailed` payloads for
/// the user ("Access session expired — sign in again in Settings → General.");
/// this strips the machinery around them so the user reads the instruction,
/// not the plumbing.
public enum DictationFailure {
    private static let prefixes = [
        "Engine runtime failed: ",
        "Engine load failed: ",
    ]

    public static func message(for error: Error) -> String {
        // Only the first line: a server's error body rides on the second one
        // and may be long, unreadable, or echo a credential.
        var line = "\(error)".components(separatedBy: "\n")[0]
            .trimmingCharacters(in: .whitespaces)
        for prefix in prefixes where line.hasPrefix(prefix) {
            line.removeFirst(prefix.count)
        }
        return line.isEmpty ? "Transcription failed." : line
    }

    /// Why a remote profile cannot be used *before* the user speaks, or nil when
    /// it looks usable. Catching this at recording start turns a lost dictation
    /// into an instruction; the transcribe path still validates for real.
    public static func remotePreflightMessage(
        profile: RemoteProfile,
        credentials: any CredentialStore
    ) -> String? {
        guard let host = profile.requestURL.host else {
            return "Remote endpoint URL has no host — check Settings → General."
        }
        switch profile.auth {
        case .none:
            return nil
        case .bearer, .header:
            let secret = credentials.secret(forHost: host)
            return (secret?.isEmpty ?? true)
                ? "No API key saved for \(host) — enter it in Settings → General."
                : nil
        case .cloudflareAccess:
            guard let jwt = CloudflareAccessClient.accessToken(forHost: host, in: credentials),
                  !jwt.isEmpty, CloudflareAccessClient.expiry(of: jwt) != nil
            else { return "Not signed in to \(host) — sign in in Settings → General." }
            return CloudflareAccessClient.isUsable(jwt)
                ? nil
                : "Access session for \(host) expired — sign in again in Settings → General."
        }
    }
}
