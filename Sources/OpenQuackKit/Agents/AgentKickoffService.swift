import Foundation

/// SPEC-031 — Agent kickoff (one-shot voice-to-action).
///
/// The post-transcription branch that **does not** paste at the focused
/// app's cursor: instead, it spawns a fresh Claude Code session in a
/// fixed workspace, with the transcript as the seed prompt. The agent
/// runs inside a new terminal window so the user can see it work and
/// intervene (approve commands, follow up, abort).
///
/// Mechanism: write the shell command into a `.command` file and hand
/// the file to `open(1)`. macOS LaunchServices recognises `.command`
/// as a terminal-executable script and opens it in the user's default
/// terminal (Terminal.app, iTerm, Warp, …). No AppleEvents, no
/// Automation TCC entry — `open` is a stock command that any process
/// can call without permission bookkeeping. The user's default terminal
/// is respected automatically.
///
/// Shell-injection safety is the load-bearing concern. The transcript
/// can contain anything Whisper emits — backticks, quotes, `$(...)`,
/// newlines — and the `.command` file is executed by `/bin/bash`. We
/// protect against that by composing the entire shell command using
/// POSIX single-quote escaping in Swift; the quoted bytes pass through
/// bash literally as a single argument to `claude`.
public enum AgentKickoffService {
    public enum Error: Swift.Error, Equatable {
        /// `claude` is not on PATH.
        case claudeCLIMissing
        /// The kickoff prompt is empty after trimming.
        case emptyPrompt
        /// Embedded NUL — cannot be carried in `argv` (or a shell line).
        case invalidPrompt
        /// Workspace directory could not be created or accessed.
        case workspaceUnavailable
        /// Failed to write the `.command` script file.
        case scriptWriteFailed
        /// `open(1)` invocation failed.
        case terminalDispatchFailed(exitCode: Int32)
    }

    /// `~/OpenQuackAgent/`. Created with mode 0700 on first use.
    public static var defaultWorkspace: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("OpenQuackAgent", isDirectory: true)
    }

    /// `claude` resolvable on the current `PATH`. The lookup walks the
    /// process environment so it reflects what a fresh terminal session
    /// would see (a `.command` file runs under the user's default login
    /// shell, which inherits the user's PATH via shell rc files — so we
    /// also union in common manual-install locations that the
    /// `.app`-launched parent might not have).
    public static func isClaudeAvailable() -> Bool {
        resolveClaudePath() != nil
    }

    /// Spawn a Claude Code session in the default workspace, seeded
    /// with `prompt`. Returns once `open(1)` has accepted the file;
    /// does NOT wait for the agent itself to finish — the user follows
    /// the agent in the terminal window that just appeared.
    public static func dispatchClaudeCode(prompt: String) async throws {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPrompt.isEmpty else { throw Error.emptyPrompt }
        guard !cleanedPrompt.contains("\0") else { throw Error.invalidPrompt }
        guard isClaudeAvailable() else { throw Error.claudeCLIMissing }

        let workspace = try ensureWorkspace(at: defaultWorkspace)
        let shellCommand = buildShellCommand(workspace: workspace.path, prompt: cleanedPrompt)
        let scriptURL = try writeCommandScript(shellCommand: shellCommand)
        defer { Self.scheduleDeletion(of: scriptURL) }
        try runOpen(on: scriptURL)
    }

    // MARK: - Internal helpers (exposed `internal` for tests)

    /// POSIX single-quote escape. Wraps `s` in `'...'` and replaces
    /// every literal `'` with `'\''` (close, escape, reopen).
    ///
    /// This is the only piece of injection protection that matters —
    /// once a string is wrapped this way, no character it contains can
    /// escape the quoting context. Newlines, backticks, `$()`, `&&`,
    /// `|`, etc. all stay literal.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Build the exact shell command that gets executed inside the
    /// `.command` file's bash subshell.
    static func buildShellCommand(workspace: String, prompt: String) -> String {
        "cd " + shellQuote(workspace) + " && claude " + shellQuote(prompt)
    }

    /// Compose the full `.command` script body. The shebang locks the
    /// interpreter; the `set -e` makes the script bail if `cd` fails
    /// (so we don't accidentally run `claude` in the wrong dir).
    static func buildCommandScript(shellCommand: String) -> String {
        """
        #!/bin/bash
        # OpenQuack SPEC-031 — agent-kickoff session launcher.
        # This file is written to NSTemporaryDirectory and deleted shortly
        # after `open` accepts it; do not rely on it persisting.
        set -e
        \(shellCommand)
        """
    }

    /// Create `~/OpenQuackAgent/` if missing. Mode 0700 — voice
    /// transcripts ending up here may be sensitive, no need to expose
    /// to group/other readers.
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
        hotkey, a terminal window opens here with a fresh `claude`
        session seeded by your spoken prompt.

        OpenQuack itself doesn't write to this directory — files here
        come from agent activity you authorised. Treat it like any
        scratch dir: move what you want to keep, delete what you don't.

        If you keep `~` synced via Dropbox / iCloud and the sync daemon
        fights agent writes here, override the workspace path in
        Settings → Agent → Workspace (M3+).
        """
        try body.write(
            to: url.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Write the `.command` script to `NSTemporaryDirectory`. Mode 0700.
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

    /// `open <path>`. LaunchServices picks the default app for the
    /// `.command` extension (Terminal.app on a stock macOS install)
    /// and hands the file to it. The user's terminal starts a shell
    /// in the file's directory, reads the file as a script, and runs
    /// it. No AppleEvents — `open` is a launchd helper.
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

    /// Best-effort cleanup. Terminal reads the file at open time and
    /// exec'es a shell with it as argv[0]; once read, deletion is
    /// safe. We delete 30s later to make absolutely sure even slow
    /// terminals have had time to dispatch.
    private static func scheduleDeletion(of url: URL) {
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 30) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Resolves `claude` against the current process's PATH plus a few
    /// commonly-used manual install locations the user's shell would
    /// see but a `.app`-launched process inherited from launchd would
    /// not (~/.local/bin, npm global on nvm, Homebrew M-series, etc).
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
