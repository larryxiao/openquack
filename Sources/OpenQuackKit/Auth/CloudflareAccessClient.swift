import Foundation

/// SPEC-045 — drives the user-installed `cloudflared` CLI for browser SSO
/// against a Cloudflare Access application. No OAuth of our own: `access
/// login` owns the whole browser round-trip; `access token` reads back the
/// freshly minted JWT. The only parameter anywhere is the app URL the user
/// typed — the code never knows which IdP sits behind it.
public enum CloudflareAccessClient {

    /// Keychain account for the Access JWT: namespaced so it can never
    /// collide with (or destroy) a Bearer/header API key saved for the
    /// same host.
    public static func credentialKey(forHost host: String) -> String {
        "cf-access:\(host)"
    }

    /// Pure-filesystem scan over $PATH plus known install dirs — fork-free,
    /// and independent of the minimal PATH a Finder-launched app gets.
    public static func cloudflaredPath() -> String? {
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        dirs += [
            "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
            NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/bin",
        ]
        let fm = FileManager.default
        for dir in dirs where !dir.isEmpty {
            let candidate = dir + "/cloudflared"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
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

    /// Thread-safe accumulator for pipe output collected via readabilityHandler.
    private final class PipeCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        func append(_ data: Data) { lock.lock(); buffer.append(data); lock.unlock() }
        var text: String {
            lock.lock(); defer { lock.unlock() }
            return String(data: buffer, encoding: .utf8) ?? ""
        }
    }

    private static func drain(_ pipe: Pipe, into collector: PipeCollector) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil   // EOF
            } else {
                collector.append(data)
            }
        }
    }

    /// Argument-array Process (no shell), output drained continuously (a full
    /// 64 KB pipe would otherwise deadlock a chatty child), hard timeout with
    /// SIGKILL escalation. The deadline uses systemUptime, which pauses during
    /// machine sleep — a closed lid mid-login doesn't burn the budget.
    private static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        let outCollector = PipeCollector()
        let errCollector = PipeCollector()
        drain(stdout, into: outCollector)
        drain(stderr, into: errCollector)
        try process.run()

        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            let killDeadline = ProcessInfo.processInfo.systemUptime + 2
            while process.isRunning && ProcessInfo.processInfo.systemUptime < killDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw EngineError.runtimeFailed("cloudflared \(args.prefix(2).joined(separator: " ")) timed out")
        }
        guard process.terminationStatus == 0 else {
            let detail = errCollector.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
            throw EngineError.runtimeFailed("cloudflared failed (exit \(process.terminationStatus))"
                                            + (detail.isEmpty ? "" : ":\n\(detail)"))
        }
        return outCollector.text
    }
}
