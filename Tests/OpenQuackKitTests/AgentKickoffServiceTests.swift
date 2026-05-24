import XCTest
@testable import OpenQuackKit

/// SPEC-031 — shell-injection corpus.
///
/// The bytes that go into `shellQuote(_:)` are bytes that Whisper put
/// in our hands; they're outside our trust boundary. The contract is:
/// no matter what's in the prompt, the resulting shell command is a
/// `cd` followed by `claude <one-literal-argument>`. Nothing about the
/// prompt ever reaches `/bin/sh` as syntax.
final class AgentKickoffServiceTests: XCTestCase {
    // MARK: - shellQuote

    func testShellQuoteSimple() {
        XCTAssertEqual(
            AgentKickoffService.shellQuote("hello world"),
            "'hello world'"
        )
    }

    func testShellQuoteWithSingleQuote() {
        // The single classic case: a literal apostrophe must close the
        // outer quoting, escape the apostrophe, and reopen.
        XCTAssertEqual(
            AgentKickoffService.shellQuote("it's fine"),
            "'it'\\''s fine'"
        )
    }

    func testShellQuoteEmpty() {
        XCTAssertEqual(AgentKickoffService.shellQuote(""), "''")
    }

    func testShellQuotePreservesShellMetacharacters() {
        // Each of these would be live syntax outside single quotes.
        let cases: [(String, String)] = [
            ("`whoami`",        "'`whoami`'"),
            ("$(rm -rf /)",     "'$(rm -rf /)'"),
            ("$USER",           "'$USER'"),
            ("a && b",          "'a && b'"),
            ("a | b",           "'a | b'"),
            ("a > b",           "'a > b'"),
            ("a; b",            "'a; b'"),
            ("a\nb",            "'a\nb'"),
            ("a\\b",            "'a\\b'"),
            ("\"quoted\"",      "'\"quoted\"'"),
            ("# comment",       "'# comment'"),
            ("~/secret",        "'~/secret'"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(
                AgentKickoffService.shellQuote(input),
                expected,
                "shellQuote failed to preserve input: \(input.debugDescription)"
            )
        }
    }

    func testShellQuoteUnicode() {
        // Emoji and non-ASCII are pass-through bytes inside single
        // quotes; nothing magical happens.
        XCTAssertEqual(
            AgentKickoffService.shellQuote("set a timer 🦆 за десять минут"),
            "'set a timer 🦆 за десять минут'"
        )
    }

    // MARK: - buildShellCommand

    func testBuildShellCommandSimple() {
        let cmd = AgentKickoffService.buildShellCommand(
            workspace: "/Users/larry/OpenQuackAgent",
            prompt: "list the files in this folder"
        )
        XCTAssertEqual(
            cmd,
            "cd '/Users/larry/OpenQuackAgent' && claude 'list the files in this folder'"
        )
    }

    func testBuildShellCommandInjectionAttempt() {
        // The classic "what if the user dictates a backtick subshell"
        // worry. The output must contain the bytes literally and not
        // as live syntax — i.e., they sit inside the closing `'`.
        let cmd = AgentKickoffService.buildShellCommand(
            workspace: "/tmp/agent",
            prompt: "tell me what `whoami` returns"
        )
        XCTAssertEqual(
            cmd,
            "cd '/tmp/agent' && claude 'tell me what `whoami` returns'"
        )
        // Sanity: the backtick sits inside single quotes, not outside.
        XCTAssertFalse(cmd.hasSuffix("`"))
    }

    func testBuildShellCommandPromptWithApostrophe() {
        let cmd = AgentKickoffService.buildShellCommand(
            workspace: "/tmp/agent",
            prompt: "it's a multi-sentence prompt; let's see"
        )
        XCTAssertEqual(
            cmd,
            "cd '/tmp/agent' && claude 'it'\\''s a multi-sentence prompt; let'\\''s see'"
        )
    }

    func testBuildShellCommandWorkspaceWithSpaces() {
        let cmd = AgentKickoffService.buildShellCommand(
            workspace: "/Users/larry/My Quack Files",
            prompt: "hello"
        )
        XCTAssertEqual(
            cmd,
            "cd '/Users/larry/My Quack Files' && claude 'hello'"
        )
    }

    func testBuildShellCommandNewlineInPrompt() {
        // Whisper occasionally emits multi-line transcripts.
        let cmd = AgentKickoffService.buildShellCommand(
            workspace: "/tmp/agent",
            prompt: "first line\nsecond line"
        )
        XCTAssertEqual(
            cmd,
            "cd '/tmp/agent' && claude 'first line\nsecond line'"
        )
    }

    // MARK: - dispatch input validation

    func testStartRejectsEmptyPrompt() {
        do {
            _ = try AgentKickoffService.startClaudeKickoff(prompt: "   \n  ")
            XCTFail("expected emptyPrompt error")
        } catch let error as AgentKickoffService.Error {
            XCTAssertEqual(error, .emptyPrompt)
        } catch {
            XCTFail("expected AgentKickoffService.Error.emptyPrompt, got \(error)")
        }
    }

    func testStartRejectsNullByte() {
        do {
            _ = try AgentKickoffService.startClaudeKickoff(prompt: "hi\0there")
            XCTFail("expected invalidPrompt error")
        } catch let error as AgentKickoffService.Error {
            // If claude is missing on the test machine we hit that
            // first; either pre-process validation error is acceptable
            // since the contract is "never let it through".
            XCTAssertTrue(error == .invalidPrompt || error == .claudeCLIMissing)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - claude --bg argv assembly

    func testBuildClaudeArgumentsHasExpectedFlags() {
        let argv = AgentKickoffService.buildClaudeArguments(
            prompt: "hello there",
            displayName: "OpenQuack: hello"
        )
        // Order matters for argv readability; verify the contract.
        // Environment context lives in workspace CLAUDE.md, not here.
        XCTAssertEqual(argv[0], "--bg")
        XCTAssertEqual(argv[1], "--permission-mode")
        XCTAssertEqual(argv[2], "bypassPermissions")
        XCTAssertEqual(argv[3], "--name")
        XCTAssertEqual(argv[4], "OpenQuack: hello")
        XCTAssertEqual(argv.last, "hello there")
        XCTAssertEqual(argv.count, 6)
    }

    func testBuildClaudeArgumentsPassesPromptAsFinalPositional() {
        // The prompt is the only positional argument; everything else
        // is named flags. Verify the prompt is at argv.last regardless
        // of whether the prompt looks like a flag.
        let argv = AgentKickoffService.buildClaudeArguments(
            prompt: "--this-is-not-a-flag",
            displayName: "name"
        )
        XCTAssertEqual(argv.last, "--this-is-not-a-flag")
    }

    // MARK: - workspace CLAUDE.md (environment context for the agent)

    func testClaudeMDBodyFlipsPostureFromChatToAction() {
        // Minimal CLAUDE.md — posture only. We trust the model knows
        // AppleScript dictionaries; we don't list them here. Lock in
        // the load-bearing substrings: the action-context framing,
        // the bash-is-universal nudge, the named anti-pattern.
        let body = AgentKickoffService.claudeMDBody
        XCTAssertTrue(body.contains("OpenQuack"))
        XCTAssertTrue(body.contains("Voice = action context"))
        XCTAssertTrue(body.contains("bash"))
        XCTAssertTrue(body.contains("osascript"))
        XCTAssertTrue(body.contains("bypassPermissions"))
        XCTAssertTrue(body.contains("\"I don't have access\""))
        // Should NOT have a long recipe book — keep it short. The
        // file is doc, not training data.
        XCTAssertLessThan(
            body.count, 1000,
            "CLAUDE.md drifting toward a recipe book; trim it back to posture-only"
        )
    }

    func testEnsureWorkspaceWritesClaudeMD() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("openquack-agent-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = try AgentKickoffService.ensureWorkspace(at: tmp)
        let claudeMD = tmp.appendingPathComponent("CLAUDE.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: claudeMD.path))

        let content = try String(contentsOf: claudeMD, encoding: .utf8)
        XCTAssertEqual(content, AgentKickoffService.claudeMDBody)
    }

    func testEnsureWorkspaceRefreshesClaudeMDOnExistingDir() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("openquack-agent-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // First call creates the dir + writes CLAUDE.md.
        _ = try AgentKickoffService.ensureWorkspace(at: tmp)
        // Stomp the file with old content.
        let claudeMD = tmp.appendingPathComponent("CLAUDE.md")
        try "stale content from old OpenQuack version".write(
            to: claudeMD, atomically: true, encoding: .utf8)

        // Second call refreshes it.
        _ = try AgentKickoffService.ensureWorkspace(at: tmp)
        let content = try String(contentsOf: claudeMD, encoding: .utf8)
        XCTAssertEqual(content, AgentKickoffService.claudeMDBody)
    }

    // MARK: - banner parser

    func testParseBackgroundedBannerCanonical() {
        let stdout = "backgrounded · 1a2b3c4d (idle — send a prompt to start)"
        XCTAssertEqual(
            AgentKickoffService.parseBackgroundedBanner(stdout),
            "1a2b3c4d"
        )
    }

    func testParseBackgroundedBannerLeadingWhitespace() {
        let stdout = "\n\n   backgrounded · 1a2b3c4d (idle — …)\n"
        XCTAssertEqual(
            AgentKickoffService.parseBackgroundedBanner(stdout),
            "1a2b3c4d"
        )
    }

    func testParseBackgroundedBannerWithAnsiEscapes() {
        // Real claude output includes ANSI colour escapes around the
        // banner. Strip them and parse.
        let stdout = "\u{001B}[2mbackgrounded\u{001B}[0m · \u{001B}[1ma3c4272d\u{001B}[0m (idle)"
        XCTAssertEqual(
            AgentKickoffService.parseBackgroundedBanner(stdout),
            "a3c4272d"
        )
    }

    func testParseBackgroundedBannerVariantSeparators() {
        // Defensive: tolerate bullet, hyphen, colon in place of the
        // middle-dot in case the format drifts across versions.
        for sep in ["·", "•", ":", "-"] {
            let stdout = "backgrounded \(sep) ef0d33c5 (idle)"
            XCTAssertEqual(
                AgentKickoffService.parseBackgroundedBanner(stdout),
                "ef0d33c5",
                "failed for separator: \(sep)"
            )
        }
    }

    func testParseBackgroundedBannerMissingReturnsNil() {
        let stdout = "Some unrelated output without the banner."
        XCTAssertNil(AgentKickoffService.parseBackgroundedBanner(stdout))
    }

    // MARK: - stderr disclaimer detection

    func testStderrDisclaimerDetection() {
        let bypass = "--bg with bypassPermissions requires accepting the disclaimer first. Run `claude --dangerously-skip-permissions` once interactively."
        XCTAssertTrue(AgentKickoffService.stderrIndicatesDisclaimer(bypass))

        let auto = "--bg with auto mode requires opting in first. Run `claude --permission-mode auto` once interactively."
        XCTAssertTrue(AgentKickoffService.stderrIndicatesDisclaimer(auto))

        let unrelated = "Couldn't connect to daemon."
        XCTAssertFalse(AgentKickoffService.stderrIndicatesDisclaimer(unrelated))
    }

    // MARK: - state JSON parsing

    func testParseStateJSONDone() {
        let data = #"{"state":"done","detail":"Timer set.","output":"OK","needs":null}"#
            .data(using: .utf8)!
        let s = KickoffState.parse(data)
        XCTAssertEqual(s?.kind, .done)
        XCTAssertEqual(s?.detail, "Timer set.")
        XCTAssertEqual(s?.output, "OK")
        XCTAssertNil(s?.needs)
        XCTAssertTrue(s?.isTerminal == true)
    }

    func testParseStateJSONBlocked() {
        let data = #"{"state":"blocked","detail":"awaiting user","needs":"reply when ready","output":null}"#
            .data(using: .utf8)!
        let s = KickoffState.parse(data)
        XCTAssertEqual(s?.kind, .blocked)
        XCTAssertEqual(s?.needs, "reply when ready")
        XCTAssertTrue(s?.isTerminal == true)
    }

    func testParseStateJSONWorking() {
        let data = #"{"state":"working","detail":"reading file"}"#.data(using: .utf8)!
        let s = KickoffState.parse(data)
        XCTAssertEqual(s?.kind, .working)
        XCTAssertFalse(s?.isTerminal == true)
    }

    func testParseStateJSONUnknownKind() {
        let data = #"{"state":"weird-new-state","detail":""}"#.data(using: .utf8)!
        let s = KickoffState.parse(data)
        XCTAssertEqual(s?.kind, .unknown)
    }

    func testParseStateJSONMalformedReturnsNil() {
        let data = "not json".data(using: .utf8)!
        XCTAssertNil(KickoffState.parse(data))
    }

    // MARK: - KickoffSession paths

    func testKickoffSessionStateFilePath() {
        let s = KickoffSession(
            shortID: "abc12345",
            workspace: URL(fileURLWithPath: "/tmp/ws"),
            prompt: "p",
            startedAt: Date(),
            displayName: "X"
        )
        XCTAssertTrue(s.stateFileURL.path.hasSuffix("/.claude/jobs/abc12345/state.json"))
        XCTAssertTrue(s.timelineFileURL.path.hasSuffix("/.claude/jobs/abc12345/timeline.jsonl"))
    }

    // MARK: - display name

    func testDisplayNameTruncatesAt40Chars() {
        let long = String(repeating: "a", count: 200)
        let name = AgentKickoffService.makeDisplayName(prompt: long)
        XCTAssertEqual(name, "OpenQuack: " + String(repeating: "a", count: 40))
    }

    func testDisplayNameFlattensNewlines() {
        let name = AgentKickoffService.makeDisplayName(prompt: "first\nsecond\rthird")
        XCTAssertFalse(name.contains("\n"))
        XCTAssertFalse(name.contains("\r"))
        XCTAssertTrue(name.contains("first second third"))
    }

    // MARK: - notification body

    func testNotificationBodyKeepsShortResponseVerbatim() {
        let r = "Timer set for 10:00."
        XCTAssertEqual(AgentKickoffService.notificationBody(from: r), r)
    }

    func testNotificationBodyTrimsAtWordBoundary() {
        // A 200-char response should be cut at ~150 chars at a space.
        let r = String(repeating: "word ", count: 60)  // 300 chars
        let body = AgentKickoffService.notificationBody(from: r, limit: 150)
        XCTAssertTrue(body.hasSuffix("…"))
        XCTAssertLessThanOrEqual(body.count, 152)
        // Should not end with a half-word, so the char before "…" is
        // either a space-trimmed boundary or the previous full word.
        XCTAssertFalse(body.contains("wor…"),
                       "should cut at word boundary, not mid-word")
    }

    func testNotificationBodyHandlesNoWhitespace() {
        // Pathological: a 200-char run of non-whitespace.
        let r = String(repeating: "x", count: 200)
        let body = AgentKickoffService.notificationBody(from: r, limit: 50)
        XCTAssertTrue(body.hasSuffix("…"))
        XCTAssertEqual(body.count, 51)  // 50 chars + ellipsis
    }

    func testNotificationBodyTrimsWhitespace() {
        let r = "\n\n  short answer  \n"
        XCTAssertEqual(AgentKickoffService.notificationBody(from: r), "short answer")
    }

    // MARK: - workspace lifecycle

    func testEnsureWorkspaceCreatesDirectoryAndReadme() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("openquack-agent-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = try AgentKickoffService.ensureWorkspace(at: tmp)
        XCTAssertEqual(url, tmp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))

        let readme = tmp.appendingPathComponent("README.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: readme.path))
        let content = try String(contentsOf: readme, encoding: .utf8)
        XCTAssertTrue(content.contains("OpenQuack"))
    }

    func testEnsureWorkspaceIsIdempotent() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("openquack-agent-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = try AgentKickoffService.ensureWorkspace(at: tmp)
        _ = try AgentKickoffService.ensureWorkspace(at: tmp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
    }

    func testEnsureWorkspaceRejectsFileAtPath() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("openquack-agent-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Put a regular file where the dir should be.
        try "not a dir".write(to: tmp, atomically: true, encoding: .utf8)

        do {
            _ = try AgentKickoffService.ensureWorkspace(at: tmp)
            XCTFail("expected workspaceUnavailable")
        } catch let error as AgentKickoffService.Error {
            XCTAssertEqual(error, .workspaceUnavailable)
        }
    }

    // MARK: - .command script body

    func testCommandScriptHasShebangAndSetE() {
        // The script is `bash`-run; the shebang locks the interpreter
        // and `set -e` makes the script bail if `cd` fails (so we
        // don't accidentally execute claude in the wrong directory).
        let body = AgentKickoffService.buildCommandScript(
            shellCommand: "cd '/tmp/agent' && claude 'hi'"
        )
        XCTAssertTrue(body.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(body.contains("set -e"))
        XCTAssertTrue(body.contains("cd '/tmp/agent' && claude 'hi'"))
    }

    func testWriteCommandScriptIsExecutable() throws {
        let url = try AgentKickoffService.writeCommandScript(
            shellCommand: "cd '/tmp' && claude 'hello'"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "command")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path))

        // Read it back: shell-injection escape must survive the round trip
        // through file write + UTF-8 decode.
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("claude 'hello'"))
    }

    func testWriteCommandScriptPreservesInjectionCorpus() throws {
        // The .command file is executed by /bin/bash; the same
        // single-quote escape from buildShellCommand has to survive
        // file write → file read → bash parsing. Verify the bytes
        // are preserved exactly across the write step.
        let tricky = "tell me what `whoami` returns and $(date) and 'quotes'\nline2"
        let cmd = AgentKickoffService.buildShellCommand(
            workspace: "/tmp",
            prompt: tricky
        )
        let url = try AgentKickoffService.writeCommandScript(shellCommand: cmd)
        defer { try? FileManager.default.removeItem(at: url) }

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains(cmd),
                      "expected tricky shell command to survive write verbatim")
    }
}
