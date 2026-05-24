import Foundation

/// SPEC-031 v3 — Agent kickoff (voice → background claude session).
///
/// Spawns `claude --bg <prompt>` as a short-lived `Process` that
/// asks the claude daemon to launch a background session. The
/// daemon owns the session lifetime; OpenQuack holds only the
/// short-id + workspace + prompt, watches state.json for completion,
/// and offers Terminal-based handoffs (`claude attach`, `claude
/// agents`, `claude stop`) via the `.command`-file spawn primitive
/// retained from v2.
public enum AgentKickoffService {
    public enum Error: Swift.Error, Equatable {
        case claudeCLIMissing
        case emptyPrompt
        case invalidPrompt
        case workspaceUnavailable
        case launchFailed
        /// `claude --bg` printed the disclaimer error. Caller should
        /// run `openDisclaimerTerminal()` and stash the transcript.
        case disclaimerNotAccepted
        /// Couldn't parse the short-id banner from stdout.
        case bannerParseFailed(stdout: String)
        case scriptWriteFailed
        case terminalDispatchFailed(exitCode: Int32)
    }

    public static var defaultWorkspace: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("OpenQuackAgent", isDirectory: true)
    }

    public static func isClaudeAvailable() -> Bool {
        resolveClaudePath() != nil
    }

    /// Dispatch a kickoff via `claude --bg`. Returns the session
    /// handle once the daemon has acknowledged the dispatch (the
    /// spawn process exits at that point; the agent keeps running
    /// inside a daemon-owned worker).
    public static func startClaudeKickoff(prompt: String) throws -> KickoffSession {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw Error.emptyPrompt }
        guard !cleaned.contains("\0") else { throw Error.invalidPrompt }
        guard let claudeURL = resolveClaudePath() else { throw Error.claudeCLIMissing }

        let workspace = try ensureWorkspace(at: defaultWorkspace)
        let displayName = makeDisplayName(prompt: cleaned)

        let task = Process()
        task.executableURL = claudeURL
        task.currentDirectoryURL = workspace
        task.arguments = buildClaudeArguments(prompt: cleaned, displayName: displayName)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError  = stderrPipe
        task.standardInput  = FileHandle.nullDevice

        let started = Date()
        do {
            try task.run()
        } catch {
            throw Error.launchFailed
        }
        task.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if Self.stderrIndicatesDisclaimer(stderr) || Self.stderrIndicatesDisclaimer(stdout) {
            throw Error.disclaimerNotAccepted
        }
        if task.terminationStatus != 0 {
            throw Error.launchFailed
        }

        guard let shortID = parseBackgroundedBanner(stdout) else {
            throw Error.bannerParseFailed(stdout: stdout)
        }

        return KickoffSession(
            shortID: shortID,
            workspace: workspace,
            prompt: cleaned,
            startedAt: started,
            displayName: displayName
        )
    }

    /// Open Terminal at `workspace` with `claude attach <shortID>`.
    public static func continueInTerminal(shortID: String, workspace: URL) throws {
        let cmd = "cd " + shellQuote(workspace.path)
                + " && claude attach " + shellQuote(shortID)
        try spawnCommandFile(shellCommand: cmd)
    }

    /// Open Terminal with the full `claude agents` TUI.
    public static func showAgentsTUI() throws {
        try spawnCommandFile(shellCommand: "claude agents")
    }

    /// Stop a running session via `claude stop <shortID>`.
    public static func stopSession(shortID: String) throws {
        guard let claudeURL = resolveClaudePath() else { throw Error.claudeCLIMissing }
        let task = Process()
        task.executableURL = claudeURL
        task.arguments = ["stop", shortID]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            throw Error.launchFailed
        }
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw Error.launchFailed
        }
    }

    /// Open Terminal with `claude --dangerously-skip-permissions`
    /// for the user to accept the one-time disclaimer that
    /// `--bg --permission-mode bypassPermissions` requires.
    public static func openDisclaimerTerminal() throws {
        try spawnCommandFile(shellCommand: "claude --dangerously-skip-permissions")
    }

    // MARK: - Internal helpers (exposed for tests)

    static func stderrIndicatesDisclaimer(_ s: String) -> Bool {
        let needles = [
            "requires accepting the disclaimer",
            "claude --dangerously-skip-permissions",
            "requires opting in first",
        ]
        for needle in needles where s.contains(needle) { return true }
        return false
    }

    /// argv for `claude --bg`. Stable, testable.
    static func buildClaudeArguments(prompt: String, displayName: String) -> [String] {
        [
            "--bg",
            "--permission-mode", "bypassPermissions",
            "--name", displayName,
            prompt,
        ]
    }

    static func makeDisplayName(prompt: String) -> String {
        let oneLine = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let prefix = oneLine.prefix(40)
        return "OpenQuack: \(prefix)"
    }

    /// Parse the dispatch banner. Tolerates ANSI escapes, leading
    /// whitespace, and variant parenthetical suffixes.
    static func parseBackgroundedBanner(_ stdout: String) -> String? {
        let cleaned = stripAnsi(stdout)
        // The middle-dot is the documented separator; accept also
        // bullet, hyphen, colon as defensive fallbacks for version
        // drift.
        let pattern = #"backgrounded\s*[·•:\-]\s*([0-9a-f]{6,12})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned)
              ),
              let idRange = Range(match.range(at: 1), in: cleaned)
        else { return nil }
        return String(cleaned[idRange])
    }

    static func stripAnsi(_ s: String) -> String {
        // Strip CSI sequences: ESC [ ... letter
        let pattern = "\u{001B}\\[[0-9;?]*[A-Za-z]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }

    /// Trim the response for a notification body — at most ~150 chars
    /// at a word boundary, with an ellipsis if truncated.
    public static func notificationBody(from response: String, limit: Int = 150) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let cap = trimmed.index(trimmed.startIndex, offsetBy: limit)
        let slice = trimmed[..<cap]
        if let lastSpace = slice.lastIndex(where: { $0.isWhitespace }) {
            return trimmed[..<lastSpace].trimmingCharacters(in: .whitespaces) + "…"
        }
        return trimmed[..<cap] + "…"
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func buildShellCommand(workspace: String, prompt: String) -> String {
        "cd " + shellQuote(workspace) + " && claude " + shellQuote(prompt)
    }

    static func buildCommandScript(shellCommand: String) -> String {
        """
        #!/bin/bash
        # OpenQuack SPEC-031 — Terminal handoff launcher.
        # Written to NSTemporaryDirectory and deleted shortly after open(1)
        # accepts it; do not rely on it persisting.
        set -e
        \(shellCommand)
        """
    }

    static func ensureWorkspace(at url: URL) throws -> URL {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            do {
                try fm.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try? writeWorkspaceReadme(in: url)
            } catch {
                throw Error.workspaceUnavailable
            }
        } else if !isDir.boolValue {
            throw Error.workspaceUnavailable
        }
        return url
    }

    private static func writeWorkspaceReadme(in url: URL) throws {
        let body = """
        # OpenQuack agent workspace

        This is OpenQuack's default workspace for voice-launched
        background agent sessions (SPEC-031). Each time you press the
        agent-kickoff hotkey, a fresh `claude` session runs in the
        background here under the daemon's management, seeded by your
        spoken prompt. When it finishes you get a macOS notification.

        The agent runs with permission bypass — it executes shell
        commands, edits, and side effects without asking you first.
        That's the cost of fire-and-forget dispatch. Treat this dir
        like a sandbox: don't keep anything in it you'd hate to lose
        to an unexpected agent action.

        Re-enter a kickoff with `claude attach <short-id>` or browse
        all kickoffs with `claude agents`. Stop one with `claude stop
        <short-id>`. If you keep `~` synced via Dropbox / iCloud, the
        sync daemon can fight agent writes here — workspace override
        is M3+.
        """
        try body.write(
            to: url.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    static func writeCommandScript(shellCommand: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = dir.appendingPathComponent("openquack-kickoff-\(UUID().uuidString).command")
        let body = buildCommandScript(shellCommand: shellCommand)
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        } catch {
            throw Error.scriptWriteFailed
        }
        return url
    }

    private static func spawnCommandFile(shellCommand: String) throws {
        let url = try writeCommandScript(shellCommand: shellCommand)
        defer { scheduleDeletion(of: url) }
        try runOpen(on: url)
    }

    private static func runOpen(on scriptURL: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [scriptURL.path]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            throw Error.terminalDispatchFailed(exitCode: -1)
        }
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw Error.terminalDispatchFailed(exitCode: task.terminationStatus)
        }
    }

    private static func scheduleDeletion(of url: URL) {
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 30) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func resolveClaudePath() -> URL? {
        let env = ProcessInfo.processInfo.environment
        var paths = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        let home = NSHomeDirectory()
        paths.append(contentsOf: [
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ])
        let fm = FileManager.default
        for dir in paths where !dir.isEmpty {
            let candidate = (dir as NSString).appendingPathComponent("claude")
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}

/// Reference to a `claude --bg` session. The session is owned by
/// the claude daemon, not OpenQuack — this struct just carries
/// metadata + paths.
public struct KickoffSession: Sendable, Identifiable, Equatable {
    public let shortID: String
    public let workspace: URL
    public let prompt: String
    public let startedAt: Date
    public let displayName: String

    public var id: String { shortID }

    public var stateFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/jobs/\(shortID)/state.json")
    }

    public var timelineFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/jobs/\(shortID)/timeline.jsonl")
    }
}

/// Parsed snapshot of `~/.claude/jobs/<short>/state.json`.
public struct KickoffState: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case working, blocked, done, idle, unknown
    }
    public let kind: Kind
    public let detail: String?
    public let output: String?
    public let needs: String?

    public init(kind: Kind, detail: String?, output: String?, needs: String?) {
        self.kind = kind
        self.detail = detail
        self.output = output
        self.needs = needs
    }

    public var isTerminal: Bool {
        kind == .done || kind == .blocked || kind == .idle
    }

    /// Parse a JSON object as a state.json snapshot.
    public static func parse(_ data: Data) -> KickoffState? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let kindRaw = obj["state"] as? String ?? "unknown"
        let kind = Kind(rawValue: kindRaw) ?? .unknown
        return KickoffState(
            kind: kind,
            detail: obj["detail"] as? String,
            output: obj["output"] as? String,
            needs: obj["needs"] as? String
        )
    }
}

/// Final result presented in the response window + notification.
public struct KickoffResult: Sendable, Equatable {
    public let shortID: String
    public let prompt: String
    public let workspace: URL
    public let displayName: String
    public let state: KickoffState.Kind
    public let detail: String?
    public let output: String?
    public let needs: String?
    public let durationSeconds: Double

    public var succeeded: Bool { state == .done || state == .idle }

    public init(from state: KickoffState, session: KickoffSession) {
        self.shortID = session.shortID
        self.prompt = session.prompt
        self.workspace = session.workspace
        self.displayName = session.displayName
        self.state = state.kind
        self.detail = state.detail
        self.output = state.output
        self.needs = state.needs
        self.durationSeconds = Date().timeIntervalSince(session.startedAt)
    }
}
