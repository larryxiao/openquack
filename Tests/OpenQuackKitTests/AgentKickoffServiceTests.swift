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

    func testDispatchRejectsEmptyPrompt() async {
        do {
            try await AgentKickoffService.dispatchClaudeCode(prompt: "   \n  ")
            XCTFail("expected emptyPrompt error")
        } catch let error as AgentKickoffService.Error {
            XCTAssertEqual(error, .emptyPrompt)
        } catch {
            XCTFail("expected AgentKickoffService.Error.emptyPrompt, got \(error)")
        }
    }

    func testDispatchRejectsNullByte() async {
        do {
            try await AgentKickoffService.dispatchClaudeCode(prompt: "hi\0there")
            XCTFail("expected invalidPrompt error")
        } catch let error as AgentKickoffService.Error {
            // If claude is missing on the test machine we hit that
            // first; both pre-osascript validation errors are
            // acceptable since the contract is "never let it through".
            XCTAssertTrue(error == .invalidPrompt || error == .claudeCLIMissing)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
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
