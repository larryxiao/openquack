import Foundation

/// SPEC-045 — drives the user-installed `cloudflared` CLI for browser SSO
/// against a Cloudflare Access application. No OAuth of our own: `access
/// login` owns the whole browser round-trip; `access token` reads back the
/// freshly minted JWT. The only parameter anywhere is the app URL the user
/// typed — the code never knows which IdP sits behind it.
public enum CloudflareAccessClient {

    /// Well-known install locations first, then $PATH (Settings may run
    /// outside a login shell, so `which` alone isn't enough).
    public static func cloudflaredPath() -> String? {
        let known = ["/opt/homebrew/bin/cloudflared", "/usr/local/bin/cloudflared"]
        if let hit = known.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        let out = try? run("/usr/bin/env", ["which", "cloudflared"], timeout: 5)
        let path = out?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    /// Opens the browser and blocks until the user completes the IdP flow
    /// (or the timeout fires — abandoning the browser must not hang Settings).
    public static func login(appURL: URL) async throws {
        let bin = try requireCloudflared()
        _ = try await runAsync(bin, ["access", "login", appURL.absoluteString], timeout: 300)
    }

    /// Reads the JWT `access login` minted for this app from cloudflared's
    /// local cache.
    public static func fetchToken(appURL: URL) async throws -> String {
        let bin = try requireCloudflared()
        let out = try await runAsync(bin, ["access", "token", "--app", appURL.absoluteString], timeout: 15)
        let token = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isJWTShaped(token) else {
            throw EngineError.runtimeFailed("cloudflared returned an unexpected token")
        }
        return token
    }

    /// A JWT is three dot-separated base64url segments; Access tokens are
    /// JSON-header JWTs, so they start with "ey".
    static func isJWTShaped(_ s: String) -> Bool {
        s.hasPrefix("ey") && s.split(separator: ".").count == 3
    }

    /// Decodes the payload's `exp`. Nil for anything malformed.
    public static func expiry(of jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// Usable = well-formed and not within `leeway` of expiry. Access treats
    /// an expired token as a *failed* authentication — worse than sending
    /// none — so near-expiry tokens are refused too.
    public static func isUsable(_ jwt: String, leeway: TimeInterval = 60) -> Bool {
        guard let exp = expiry(of: jwt) else { return false }
        return exp.timeIntervalSinceNow > leeway
    }

    // MARK: - process plumbing

    private static func requireCloudflared() throws -> String {
        guard let bin = cloudflaredPath() else {
            throw EngineError.runtimeFailed("cloudflared is not installed — brew install cloudflared")
        }
        return bin
    }

    private static func runAsync(_ launchPath: String, _ args: [String], timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try run(launchPath, args, timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Argument-array Process (no shell), stdout captured, hard timeout.
    private static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            throw EngineError.runtimeFailed("cloudflared \(args.prefix(2).joined(separator: " ")) timed out")
        }
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let detail = err.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
            throw EngineError.runtimeFailed("cloudflared failed (exit \(process.terminationStatus))"
                                            + (detail.isEmpty ? "" : ":\n\(detail)"))
        }
        return out
    }
}
