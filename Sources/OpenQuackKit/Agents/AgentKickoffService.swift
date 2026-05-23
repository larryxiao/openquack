import Foundation

/// SPEC-031 — Agent kickoff (one-shot voice-to-action).
///
/// Background dispatch: spawn `claude -p` in a fresh detached
/// `Process`, no controlling TTY, no Terminal window, no
/// workspace-trust dialog (which `claude` skips automatically when
/// stdout isn't a TTY). The session runs in `~/OpenQuackAgent/`. When
/// the process exits, captured stdout becomes the agent's response;
/// the caller posts a macOS notification and surfaces the response
/// window when the user clicks it.
///
/// The `.command`-file helpers (`buildCommandScript`, `writeCommandScript`,
/// shellQuote, buildShellCommand) are retained for the *"Continue in
/// Terminal"* button — when the user wants to attach to the persisted
/// session interactively, we write a `cd workspace && claude --resume <id>`
/// `.command` file and `open(1)` it. Same shell-injection-safe
/// machinery, repurposed for the opt-in attach path.
public enum AgentKickoffService {
    public enum Error: Swift.Error, Equatable {
        /// `claude` is not on PATH (nor any of the manual-install locations).
        case claudeCLIMissing
        /// The kickoff prompt is empty after trimming.
        case emptyPrompt
        /// Embedded NUL — cannot be carried in `argv`.
        case invalidPrompt
        /// Workspace directory could not be created or accessed.
        case workspaceUnavailable
        /// `Process.run()` threw (executable missing, permission denied, …).
        case launchFailed
        /// Failed to write the `.command` script for Continue-in-Terminal.
        case scriptWriteFailed
        /// `open(1)` invocation for Continue-in-Terminal failed.
        case terminalDispatchFailed(exitCode: Int32)
    }

    /// `~/OpenQuackAgent/`. Created with mode 0700 on first use.
    public static var defaultWorkspace: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("OpenQuackAgent", isDirectory: true)
    }

    /// `claude` resolvable on the current `PATH` plus a few common
    /// manual-install locations that a `.app`-launched process
    /// inherited from launchd would not see.
    public static func isClaudeAvailable() -> Bool {
        resolveClaudePath() != nil
    }

    /// Start a Claude Code session in the background. Returns the
    /// session handle synchronously after the process is spawned. The
    /// caller awaits completion via `KickoffSession.awaitResult()`.
    public static func startClaudeCode(prompt: String) throws -> KickoffSession {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPrompt.isEmpty else { throw Error.emptyPrompt }
        guard !cleanedPrompt.contains("\0") else { throw Error.invalidPrompt }
        guard let claudeURL = resolveClaudePath() else { throw Error.claudeCLIMissing }

        let workspace = try ensureWorkspace(at: defaultWorkspace)
        let id = UUID()
        let displayName = makeDisplayName(prompt: cleanedPrompt)

        let task = Process()
        task.executableURL = claudeURL
        task.currentDirectoryURL = workspace
        task.arguments = buildClaudeArguments(
            sessionID: id,
            displayName: displayName,
            prompt: cleanedPrompt
        )
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

        return KickoffSession(
            id: id,
            workspace: workspace,
            prompt: cleanedPrompt,
            startedAt: started,
            displayName: displayName,
            process: task,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )
    }

    /// Open a `.command` file that attaches to a persisted session
    /// (`claude --resume <id>`) in the user's default terminal. Called
    /// from the response window's "Continue in Terminal" button.
    public static func continueInTerminal(sessionID: UUID, workspace: URL) throws {
        let cmd = "cd " + shellQuote(workspace.path) +
                  " && claude --resume " + shellQuote(sessionID.uuidString.lowercased())
        let scriptURL = try writeCommandScript(shellCommand: cmd)
        defer { scheduleDeletion(of: scriptURL) }
        try runOpen(on: scriptURL)
    }

    // MARK: - Internal helpers (exposed `internal` for tests)

    /// argv for `claude -p` headless. Stable, testable.
    static func buildClaudeArguments(
        sessionID: UUID,
        displayName: String,
        prompt: String
    ) -> [String] {
        [
            "-p",
            "--session-id",      sessionID.uuidString.lowercased(),
            "--permission-mode", "bypassPermissions",
            "--output-format",   "text",
            "--name",            displayName,
            prompt,
        ]
    }

    /// "OpenQuack: <first 40 chars of prompt, single-line>".
    /// Becomes the session name in `claude agents` + `--resume` picker.
    static func makeDisplayName(prompt: String) -> String {
        let oneLine = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let prefix = oneLine.prefix(40)
        return "OpenQuack: \(prefix)"
    }

    /// Trim the response for a notification body — at most ~150 chars
    /// at a word boundary, with an ellipsis if truncated.
    public static func notificationBody(from response: String, limit: Int = 150) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let cap = trimmed.index(trimmed.startIndex, offsetBy: limit)
        // Walk back to the last whitespace so we don't slice mid-word.
        let slice = trimmed[..<cap]
        if let lastSpace = slice.lastIndex(where: { $0.isWhitespace }) {
            return trimmed[..<lastSpace].trimmingCharacters(in: .whitespaces) + "…"
        }
        return trimmed[..<cap] + "…"
    }

    /// POSIX single-quote escape. Wraps `s` in `'...'` and replaces
    /// every literal `'` with `'\''` (close, escape, reopen).
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Build the shell command for the Continue-in-Terminal path.
    /// (No longer used for the primary dispatch — kept here because
    /// the .command flow is the only place we shell-exec by string.)
    static func buildShellCommand(workspace: String, prompt: String) -> String {
        "cd " + shellQuote(workspace) + " && claude " + shellQuote(prompt)
    }

    static func buildCommandScript(shellCommand: String) -> String {
        """
        #!/bin/bash
        # OpenQuack SPEC-031 — Continue-in-Terminal session launcher.
        # Written to NSTemporaryDirectory and deleted shortly after open(1)
        # accepts it; don't rely on it persisting.
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

        This is OpenQuack's default workspace for voice-launched agent
        sessions (SPEC-031). Each time you press the agent-kickoff
        hotkey, a fresh `claude` session runs **in the background**
        here, seeded by your spoken prompt. When it finishes, you get
        a macOS notification with the response.

        The agent runs with permission bypass — it executes shell
        commands, edits, and side effects without asking you first.
        That's the cost of fire-and-forget dispatch. Treat this dir
        like a sandbox: don't keep anything in it you'd hate to lose
        to an unexpected agent action.

        If you keep `~` synced via Dropbox / iCloud, the sync daemon
        can fight agent writes here. Workspace override is M3+.
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

/// A live (or recently-completed) Claude Code session started by
/// `AgentKickoffService.startClaudeCode`. Holds the Process and the
/// stdio pipes; the caller drives lifecycle via `awaitResult`.
public final class KickoffSession: @unchecked Sendable, Identifiable {
    public let id: UUID
    public let workspace: URL
    public let prompt: String
    public let startedAt: Date
    public let displayName: String

    private let process: Process
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe

    init(
        id: UUID,
        workspace: URL,
        prompt: String,
        startedAt: Date,
        displayName: String,
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe
    ) {
        self.id = id
        self.workspace = workspace
        self.prompt = prompt
        self.startedAt = startedAt
        self.displayName = displayName
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    /// Wait for the agent process to exit, then return the aggregated
    /// result (stdout, stderr, exit code, duration). Reads stdio
    /// fully — closing the pipes after the process exits avoids
    /// FIFO-buffer-full deadlocks on long responses.
    public func awaitResult() async -> KickoffResult {
        // Read pipes off the main thread; .availableData blocks.
        async let stdoutData: Data = Task.detached { [stdoutPipe] in
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }.value
        async let stderrData: Data = Task.detached { [stderrPipe] in
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }.value

        await Task.detached { [process] in
            process.waitUntilExit()
        }.value

        let stdoutBytes = await stdoutData
        let stderrBytes = await stderrData
        let stdout = String(data: stdoutBytes, encoding: .utf8) ?? ""
        let stderr = String(data: stderrBytes, encoding: .utf8) ?? ""
        let duration = Date().timeIntervalSince(startedAt)

        return KickoffResult(
            sessionId: id,
            prompt: prompt,
            workspace: workspace,
            response: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderr,
            exitCode: process.terminationStatus,
            durationSeconds: duration,
            displayName: displayName
        )
    }

    /// Terminate the in-flight agent process (e.g. on app quit).
    public func cancel() {
        if process.isRunning {
            process.terminate()
        }
    }
}

public struct KickoffResult: Sendable, Equatable {
    public let sessionId: UUID
    public let prompt: String
    public let workspace: URL
    public let response: String
    public let stderr: String
    public let exitCode: Int32
    public let durationSeconds: Double
    public let displayName: String

    public var succeeded: Bool { exitCode == 0 }
}
