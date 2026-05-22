import Foundation

/// SPEC-031 — Agent kickoff (one-shot voice-to-action).
///
/// The post-transcription branch that **does not** paste at the focused
/// app's cursor: instead, it spawns a fresh Claude Code session in a
/// fixed workspace, with the transcript as the seed prompt. The agent
/// runs inside a new Terminal.app window so the user can see it work
/// and intervene (approve commands, follow up, abort).
///
/// Shell-injection safety is the load-bearing concern. The transcript
/// can contain anything Whisper emits — backticks, quotes, `$(...)`,
/// newlines — and we hand it to a shell-running process. We protect
/// against that by composing the entire shell command **in Swift**
/// using POSIX single-quote escaping, then passing it to `osascript`
/// as a single `argv` entry. AppleScript hands it to `/bin/sh` opaquely
/// via `do script`; the single quotes preserve every byte literally.
public enum AgentKickoffService {
    public enum Error: Swift.Error, Equatable {
        /// `claude` is not on PATH.
        case claudeCLIMissing
        /// The kickoff prompt is empty after trimming.
        case emptyPrompt
        /// Embedded NUL — cannot be carried in `argv`.
        case invalidPrompt
        /// Workspace directory could not be created or accessed.
        case workspaceUnavailable
        /// `osascript` invocation failed.
        case terminalDispatchFailed(exitCode: Int32)
    }

    /// `~/OpenQuackAgent/`. Created with mode 0700 on first use.
    public static var defaultWorkspace: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("OpenQuackAgent", isDirectory: true)
    }

    /// `claude` resolvable on the current `PATH`. The lookup walks the
    /// process environment so it reflects what a fresh Terminal session
    /// would see (Terminal inherits the user's login shell PATH; this
    /// process inherits the parent that launched the app, which on a
    /// .app bundle is launchd — so we also union in common manual-
    /// install locations).
    public static func isClaudeAvailable() -> Bool {
        resolveClaudePath() != nil
    }

    /// Spawn a Claude Code session in the default workspace, seeded
    /// with `prompt`. Returns once `osascript` has been launched; does
    /// NOT wait for the agent itself to finish — the user follows the
    /// agent in the Terminal window that just appeared.
    public static func dispatchClaudeCode(prompt: String) async throws {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPrompt.isEmpty else { throw Error.emptyPrompt }
        guard !cleanedPrompt.contains("\0") else { throw Error.invalidPrompt }
        guard isClaudeAvailable() else { throw Error.claudeCLIMissing }

        let workspace = try ensureWorkspace(at: defaultWorkspace)
        let command = buildShellCommand(workspace: workspace.path, prompt: cleanedPrompt)
        try runOsascript(deliveringTo: command)
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

    /// Build the exact shell command that gets handed to `/bin/sh`
    /// inside a fresh Terminal tab.
    static func buildShellCommand(workspace: String, prompt: String) -> String {
        "cd " + shellQuote(workspace) + " && claude " + shellQuote(prompt)
    }

    /// AppleScript template — fixed; the only variable is `argv[0]`,
    /// which carries the (already-escaped) shell command.
    static let terminalAppleScript = """
    on run argv
        if (count of argv) < 1 then return
        tell application "Terminal"
            activate
            do script (item 1 of argv)
        end tell
    end run
    """

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
        hotkey, a Terminal window opens here with a fresh `claude`
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

    /// `osascript -e <script> <command>` — the script's `argv[0]` is
    /// the shell command. We do not write the script to disk.
    private static func runOsascript(deliveringTo shellCommand: String) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", terminalAppleScript, shellCommand]
        // Detach stdio so the spawn doesn't keep file handles open on us.
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            throw Error.terminalDispatchFailed(exitCode: -1)
        }
        // We deliberately do NOT call `task.waitUntilExit()`; osascript
        // returns nearly instantly after issuing the AEvent to Terminal.
        // A short wait verifies it dispatched without an error code.
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw Error.terminalDispatchFailed(exitCode: task.terminationStatus)
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
