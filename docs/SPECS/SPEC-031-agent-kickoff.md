# SPEC-031 — Agent kickoff (one-shot voice-to-action)

**Status:** draft (M2 — adoption-band demo feature)
**Owner:** `OpenQuackKit/Agents/` + `OpenQuackApp/{RecordingOverlay,ResponseWindow}.swift`
**Last updated:** 2026-05-23 (v3 — claude --bg + daemon-managed sessions)

## Goal

A second, separately-bindable hotkey that takes the user's spoken
utterance and dispatches it to a **fresh background Claude Code
session managed by claude's own supervisor daemon**, via the
`claude --bg "<prompt>"` CLI. The session runs detached — no
Terminal pops up, no workspace-trust dialog, no focus stolen. The
session is **centrally tracked**: it appears in `claude agents
--json` (and the `claude agents` TUI) alongside any other background
agents the user is running. When the agent finishes (or asks for
input), OpenQuack posts a macOS notification; clicking it opens a
small floating window with the full response and a button to drop
into the **live** session via `claude attach <id>`.

Voice → action → notification → optional drop-in.

The user doesn't have to be in any particular app, doesn't position
a cursor, doesn't paste anything, and isn't interrupted by a Terminal
window appearing during whatever they were doing. The session
*persists* after dispatch — closing OpenQuack does not kill it; the
claude daemon does. Re-entering the session uses `claude attach`,
which connects to the live daemon-owned PTY rather than starting a
fresh process.

## User story

Two shapes, both real:

1. *Larry on a Tuesday morning, no editor open:*
   "Set me a timer for ten o'clock and put a Notification Centre entry
   on it." → presses the kickoff hotkey, speaks, releases. Overlay
   confirms "Agent launched ✓ (claude)" for ~700 ms and dismisses.
   Five seconds later, a notification slides in: *"claude finished —
   Timer set for 10:00. macOS reminder scheduled."* Larry keeps doing
   whatever he was doing.
2. *Larry mid-coding-session, OpenQuack repo in focus, sees a side task:*
   "In a scratch dir, sketch what a SwiftUI view that visualises the
   FnHotkeyMonitor's flag transitions would look like — just a one-file
   prototype, don't touch the repo." → kickoff hotkey, speaks, releases.
   Larry stays in the editor. ~90 seconds later a notification fires;
   clicking it opens the response window with the file path and a
   brief summary. The "Continue in Terminal" button drops him into the
   live session via `claude --resume <id>` if he wants to iterate.

Both work because the kickoff hotkey is *not* the dictation hotkey.
Dictation still pastes at the cursor of whatever app is in focus (the
SPEC-005 path). Kickoff bypasses focus entirely, runs the agent in
the background, and surfaces the result through native notification
mechanics that the user can ignore or click into at their own pace.

## Why now, and why distinct from SPEC-006

SPEC-006 (Agent dispatch, draft v2) covers the **multi-turn closed-loop
session** vision: a conversation panel, approval prompts, side-effect
chips, voice approval, and a session that lives across utterances. That
is the long-game design and it's in the deferred-feature band per
`docs/ROADMAP.md` (adoption pivot 2026-05-14).

This spec is a **distinct one-shot kickoff**. The two compose later
(SPEC-006's `ClaudeCodeAgent` can adopt the same spawn primitive), but
neither needs to absorb the other. Carving the one-shot kickoff out
gives us:

- A *demo-grade* surface that captures the "voice as a system command"
  pitch in a single GIF — material the cold-start playbook needs and
  generic-dictation competitors don't have.
- A way to validate the underlying use case ("do people actually want
  voice→agent kickoff?") with a small surface, before investing in the
  conversation panel.
- An adoption-band justification for the next OpenQuack release:
  *differentiation*, not feature accretion.

The relationship is stated and capped: SPEC-006 owns the multi-turn /
session-reuse / approval-routing surface; SPEC-031 owns the
one-utterance-spawns-one-session surface. The two specs cite each
other; neither grows.

## Non-goals (explicit, to keep MVP shippable)

- **Multi-turn / session reuse from voice.** Each kickoff hotkey-press
  spawns a fresh session. Continuing the conversation is done in the
  Terminal window that the response-window's "Continue in Terminal"
  button opens (`claude --resume <id>`). SPEC-006 owns the dedicated
  voice-driven multi-turn surface.
- **Conversation panel / approval routing.** The headless agent runs
  with `--permission-mode bypassPermissions` — see Privacy contract.
  No mid-flight approval UI in v1.
- **Live progress streaming.** v1 captures the agent's output only
  when the process exits. No realtime stream into a panel while the
  agent is working. (`--output-format stream-json` would enable this;
  it's a follow-up once we know users actually want progress.)
- **Agent picker UI.** v1 ships Claude Code only. Codex (`codex`) is
  named-and-scaffolded but not built; switching agents requires a code
  change. Settings-driven picker comes with the second agent.
- **Per-app or per-project workspace inference.** v1 always uses a
  fixed workspace at `~/OpenQuackAgent/`, created on first use. Smart
  workspace selection (current finder dir, foreground editor's project
  root, …) is M3 material — SPEC-006 already brushes against it under
  the "active-app context" backlog row.
- **Polish on the transcript.** Kickoff prompts go to the agent
  verbatim from Whisper output (regex polish only — same as the
  dictation default; SPEC-007 polish is off by default and stays off).
- **Session history UI.** v1 fires-and-forgets. The notification +
  response window are the only surfaces for completed kickoffs; once
  dismissed they're gone from OpenQuack's UI. Claude Code's own
  `--resume` picker still has the session by ID. A dedicated history
  pane is M3.

## UX

### Two hotkeys, separately bindable

```
Dictation hotkey  (SPEC-003, default ⌃⇧Space)  ──▶  Whisper → paste at cursor
Kickoff hotkey    (SPEC-031, default unset)    ──▶  Whisper → background `claude`
```

The kickoff hotkey is bound under **Settings → Shortcut → Agent
kickoff**, opt-in. Default: **unset**.

### The recording overlay distinguishes the two modes

Same as before: a globe-icon "claude" mode chip appears in the pill
during a kickoff-mode recording. This is the user's only confirmation
that the right hotkey fired before they start speaking. Cancel
(Esc / cancel hotkey) works the same in both modes.

### After release — dispatch + brief confirmation

```
Dictation:  Transcribe ──▶ PasteService.paste(transcript)        [SPEC-005]
Kickoff:    Transcribe ──▶ AgentKickoffService.startClaudeKickoff(…)
                            └─ short-lived Process spawns:
                                  claude --bg \
                                    --permission-mode bypassPermissions \
                                    --name "OpenQuack: <prefix>" \
                                    <prompt>
                                  (cwd=~/OpenQuackAgent/)
                            └─ stdout parsed for banner:
                                  "backgrounded · <short-id> (idle — …)"
                            └─ short-id captured; daemon owns the session
                            └─ overlay flashes "Agent launched ✓ (claude)"
                            └─ overlay dismisses after ~700 ms
                            └─ spawn process exits; agent keeps running
```

No Terminal window appears. The recording overlay flashes the
launched-state for the same dwell time the dictation path uses for
"Pasted ✓", then dismisses. The kickoff session is owned by the
claude daemon; OpenQuack only holds a reference (short-id +
workspace + prompt).

If the agent CLI is missing (`claude` not on `PATH`), the kickoff
fails loudly: an error banner in the overlay with a one-click "Install
Claude Code" link to `claude.com/claude-code`, and the transcript is
copied to the clipboard as a fallback so the user doesn't lose what
they said.

If the daemon disclaimer hasn't been accepted (claude prints
*"--bg with bypassPermissions requires accepting the disclaimer first.
Run `claude --dangerously-skip-permissions` once interactively."*),
OpenQuack opens a `.command` Terminal with that exact command so the
user can accept the one-time disclaimer, and the current transcript
is stashed on the clipboard. The next kickoff press dispatches
normally.

### Completion signal — FSEventStream on state.json

The claude daemon writes per-session state to
`~/.claude/jobs/<short-id>/state.json` with shape:

```json
{
  "state": "working" | "blocked" | "done" | "idle",
  "detail": "<one-line summary the agent wrote>",
  "tempo": "...",
  "inFlight": { "tasks": 0, "queued": 0, "kinds": [] },
  "needs": "<what the agent is waiting on, when blocked>",
  "output": "<final response, when done>",
  ...
}
```

OpenQuack watches each session's `state.json` via FSEventStream and
notifies on transitions:

| State transition | Notification |
|---|---|
| `working → done` | "claude finished" + `detail` (or `output` first line) |
| `working → blocked` | "claude needs input" + `needs` |
| `→ idle` after working | Same as `done` — final state |
| anything → exit (file deleted) | "claude session ended" + last `detail` |

Title: `claude finished` / `claude needs input` / `claude failed`.
Body: agent-written `detail` field if present, else first ~150 chars
of `output`, word-boundary trimmed. Notifications use a
`kickoffResult` category whose default action opens the response
window (below).

Permission: `UNUserNotificationCenter.current().requestAuthorization`
is called the first time a kickoff completes — never on app launch —
so the prompt arrives in context. If the user denies notification
permission, completed kickoffs surface as a dot on the menu-bar duck;
clicking the duck opens the response window directly.

### Response window (click handler)

Clicking the notification opens a small floating window
(`ResponseWindow`):

```
┌── claude — your kickoff result ───────────────────────┐
│                                                       │
│  You said:                                             │
│    "Set me a timer for ten o'clock and put a          │
│    notification centre entry on it."                   │
│                                                       │
│  claude finished (state: done, 5.2s)                   │
│  ─────────────────────────────────────────            │
│    Timer set for 10:00.                                │
│    Created reminder via osascript:                     │
│      tell application "Reminders" …                    │
│    macOS reminder scheduled; the system will fire     │
│    a notification at 10:00 sharp.                      │
│                                                       │
│  [Copy response] [Continue in Terminal]                │
│  [Show all kickoffs] [Stop session] [Close]            │
│                                                       │
└────────────────────────────────────────────────────────┘
```

- **Copy response** — `NSPasteboard.general.setString(response, …)`.
- **Continue in Terminal** — writes a one-line
  `cd <workspace> && claude attach <short-id>` to a `.command`
  file in `NSTemporaryDirectory`, calls `open(1)`. The user's
  default terminal opens and **attaches to the live daemon-owned
  session** (different from `--resume`, which starts a fresh
  process). If the session is in `blocked` state waiting on input,
  attach lets the user answer live. If `done`, attach lets the
  user continue the conversation.
- **Show all kickoffs** — writes `claude agents` to a `.command`
  file and `open(1)`s it. The user lands in claude's own TUI
  showing every background session (ours plus theirs), with
  arrow-key navigation, peek, attach, stop.
- **Stop session** — runs `claude stop <short-id>` via Process.
  The daemon terminates the session; OpenQuack updates the
  response window to a final "Stopped" state.
- **Close** — dismisses the window. The session remains live (or
  done, depending on state) on the daemon; the user can still
  attach via Terminal or `claude agents`.

The response window does NOT auto-open on completion — that would be
intrusive. It only opens via notification click or menu-bar fallback.

### What about Claude.app (the desktop app)?

The Claude desktop app currently does **not** register a `claude://`
URL scheme route for opening a specific Claude Code session by ID
(verified in `Claude.app/Contents/Resources/app.asar` — only
`claude://cowork/shared-artifact?uuid=` is registered). Until
Anthropic adds something like `claude://session/<id>`, the only
deep-link continuation surface is Terminal + `claude attach`.

Filing a feature request with Anthropic for a session-deep-link URL
is a follow-up. When/if it lands, the response window can grow a
fourth button ("Open in Claude app") without other changes.

## Backend

### Public surface

```swift
// Sources/OpenQuackKit/Agents/AgentKickoffService.swift

public enum AgentKickoffService {
    /// Spawn `claude --bg <prompt>` in the default workspace.
    /// The spawn process exits within ~seconds after the daemon
    /// accepts the dispatch; the actual agent session is owned by
    /// the claude daemon and persists after this returns. Parses
    /// stdout for the dispatch banner to capture the short session
    /// ID.
    public static func startClaudeKickoff(prompt: String) throws -> KickoffSession

    /// Open the user's default terminal at the workspace with
    /// `claude attach <short-id>` running. Attaches to the LIVE
    /// daemon-owned session, not a fresh process. Used by the
    /// "Continue in Terminal" button.
    public static func continueInTerminal(shortID: String, workspace: URL) throws

    /// Open the user's default terminal with `claude agents` (the
    /// full background-sessions TUI). Used by the "Show all
    /// kickoffs" button.
    public static func showAgentsTUI() throws

    /// Run `claude stop <short-id>` via Process. Daemon
    /// terminates the session. Used by the "Stop session" button.
    public static func stopSession(shortID: String) throws

    /// Spawn a Terminal with `claude --dangerously-skip-permissions`
    /// for the user to accept the one-time disclaimer that
    /// `--bg --permission-mode bypassPermissions` requires. Called
    /// from the consent flow OR auto-triggered if dispatch fails
    /// with the "disclaimer not accepted" error.
    public static func openDisclaimerTerminal() throws

    /// `~/OpenQuackAgent/`. Created on first use with mode 0700.
    public static var defaultWorkspace: URL { get }

    /// `claude` resolvable on PATH plus common manual-install locs.
    public static func isClaudeAvailable() -> Bool

    public enum Error: Swift.Error, Equatable {
        case claudeCLIMissing
        case emptyPrompt
        case invalidPrompt
        case workspaceUnavailable
        case launchFailed
        /// `claude --bg` printed the disclaimer error. Caller should
        /// call `openDisclaimerTerminal()` and stash the transcript.
        case disclaimerNotAccepted
        /// Couldn't parse the short-id banner from stdout.
        case bannerParseFailed(stdout: String)
        case scriptWriteFailed
        case terminalDispatchFailed(exitCode: Int32)
    }
}

/// Reference to a kickoff dispatched via `claude --bg`. The session
/// itself is owned by the claude daemon — OpenQuack only holds
/// metadata + paths for watching its state.
public struct KickoffSession: Sendable, Identifiable, Equatable {
    /// 8-char short ID printed in the dispatch banner; used by
    /// `claude agents`, `claude attach`, `claude stop`, and as
    /// the directory name in `~/.claude/jobs/<short>/`.
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

/// One snapshot of a kickoff's state. Read from
/// `~/.claude/jobs/<short>/state.json` by `StateFileWatcher`.
public struct KickoffState: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case working, blocked, done, idle, unknown
    }
    public let kind: Kind
    public let detail: String?  // one-line agent-written summary
    public let output: String?  // final response (when done)
    public let needs: String?   // what agent waits on (when blocked)
}

public extension KeyboardShortcuts.Name {
    static let agentKickoff = Self("openquack.agentKickoff")
}
```

### How dispatch actually happens

```swift
let workspace = try ensureWorkspace(at: defaultWorkspace)
let claudeBin = resolveClaudePath()!  // URL

let task = Process()
task.executableURL = claudeBin
task.currentDirectoryURL = workspace
task.arguments = [
    "--bg",
    "--permission-mode", "bypassPermissions",
    "--name", "OpenQuack: \(prompt.prefix(40))",
    prompt,
]

let stdout = Pipe()
let stderr = Pipe()
task.standardOutput = stdout
task.standardError = stderr
task.standardInput = FileHandle.nullDevice  // explicitly no TTY

let start = Date()
try task.run()
task.waitUntilExit()  // --bg returns in seconds after daemon accept

let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
let stdoutStr  = String(data: stdoutData, encoding: .utf8) ?? ""
let stderrStr  = String(data: stderrData, encoding: .utf8) ?? ""

if stderrStr.contains("requires accepting the disclaimer") {
    throw Error.disclaimerNotAccepted
}
if task.terminationStatus != 0 {
    throw Error.launchFailed
}

// Parse: "backgrounded · <short> (idle — send a prompt to start)"
guard let shortID = parseBackgroundedBanner(stdoutStr) else {
    throw Error.bannerParseFailed(stdout: stdoutStr)
}

return KickoffSession(
    shortID: shortID,
    workspace: workspace,
    prompt: prompt,
    startedAt: start,
    displayName: "OpenQuack: \(prompt.prefix(40))"
)
```

Banner parser:

```swift
/// Matches "backgrounded · <8-hex-id> (idle — …)" with tolerance for
/// surrounding whitespace, ANSI escapes, and version-to-version drift
/// in the parenthetical suffix.
static func parseBackgroundedBanner(_ stdout: String) -> String? {
    let pattern = #"backgrounded\s*[·•]\s*([0-9a-f]{6,12})"#
    let cleaned = stripAnsi(stdout)
    guard let match = cleaned.range(of: pattern, options: .regularExpression)
    else { return nil }
    let snippet = String(cleaned[match])
    let idPattern = #"[0-9a-f]{6,12}"#
    guard let idMatch = snippet.range(of: idPattern, options: .regularExpression)
    else { return nil }
    return String(snippet[idMatch])
}
```

The dispatch process completes quickly because the daemon
acknowledges acceptance once the session is spawned; the agent's
actual work happens inside the daemon-owned worker process. Nothing
holds the OpenQuack-side spawn open after that.

### Why `claude --bg` rather than `claude -p`

The v2 design used `claude -p` (print mode). v3 abandons that because:

- `-p` is one-shot — the process *is* the session, and exits on
  completion. Sessions don't appear in `claude agents --json` while
  running (the daemon never sees them) and can't be `attach`-ed.
- `--bg` is daemon-managed — sessions persist after the spawn CLI
  exits, are listed by `claude agents --json`, survive OpenQuack
  quitting, and can be entered via `claude attach <id>`.

This matches the spec's "centralized session management" requirement
(user feedback 2026-05-23): voice-launched sessions visible alongside
any other background work in the claude TUI.

### Why `--permission-mode bypassPermissions`

The agent runs unattended — there's no UI for per-action approvals
during the run. Bypass mode is required for actuator tasks ("set a
timer", "move these files") which need bash. The cost is real and
called out in the consent prompt (Privacy contract below).

This mode requires a one-time disclaimer acceptance via
`claude --dangerously-skip-permissions` (the system-level claude
opt-in). OpenQuack's consent flow surfaces this as a guided two-step:
first OpenQuack's own consent modal, then a Terminal popup for the
claude-side disclaimer.

### Session manager (file-watcher-based)

```swift
@MainActor
public final class AgentSessionManager: ObservableObject {
    @Published public private(set) var liveSessions: [String: KickoffSession] = [:]
    @Published public private(set) var liveStates:   [String: KickoffState]   = [:]
    @Published public private(set) var completedResults: [KickoffResult] = []

    private var watchers: [String: StateFileWatcher] = [:]

    public func track(_ session: KickoffSession) {
        liveSessions[session.shortID] = session
        let watcher = StateFileWatcher(url: session.stateFileURL) { [weak self] state in
            Task { @MainActor in self?.handle(state: state, session: session) }
        }
        watchers[session.shortID] = watcher
        watcher.start()
    }

    private func handle(state: KickoffState, session: KickoffSession) {
        liveStates[session.shortID] = state
        let isTerminal = state.kind == .done || state.kind == .idle || state.kind == .blocked
        if isTerminal {
            // Convert to result, archive, notify.
            let result = KickoffResult(from: state, session: session)
            completedResults.append(result)
            cap(&completedResults, at: 20)
            watchers[session.shortID]?.stop()
            watchers[session.shortID] = nil
            liveSessions[session.shortID] = nil
            postNotification(result: result)
        }
    }
}
```

`StateFileWatcher` wraps `FSEventStream` for one state.json path,
parses JSON on each write, calls back with the parsed state. Has a
small (~100ms) debounce because state writes can come in bursts
during fast tool sequences.

### Workspace lifecycle + agent environment context

`~/OpenQuackAgent/` is created on first use with mode 0700. On every
dispatch, OpenQuack (re)writes two files in the workspace:

- **`README.md`** — for the human user, explains what the directory
  is and how to interact with kickoffs (`claude attach`, `claude
  agents`, `claude stop`).
- **`CLAUDE.md`** — for the agent. Auto-discovered by claude on
  session start (cwd = workspace). Documents the **environment**:
  full bash + osascript / AppleScript access, common macOS idioms
  for timers / reminders / browser state / notifications, and the
  shape of the kickoff lifecycle (background + notification + attach).

Why CLAUDE.md rather than `--append-system-prompt`:

- CLAUDE.md is the native claude pattern for "environment context"
  — same machinery as project-level CLAUDE.md files.
- It lives with the workspace, not the dispatch — easy to inspect,
  edit, version. Users can extend it with their own preferences.
- The dispatch argv stays small and stable; no per-invocation
  payload to maintain.
- Conceptually right: CLAUDE.md says *"here's where you are and what
  you have"*; `--append-system-prompt` would say *"override your
  defaults this turn"*. The former composes; the latter doesn't.

Content focuses on **teaching the agent to reach for bash + osascript
for macOS-flavored tasks** rather than reflexively refusing with *"I
don't have access to that"*. Recurring user-feedback failure mode:
the agent says it has no clock / browser / etc. access, when bash +
osascript would have handled it.

MCP server inheritance: the dispatch does NOT pass `--strict-mcp-config`,
so any MCP servers the user has registered via `claude mcp add` are
loaded into the kickoff session by default. (Most v1 users won't have
local MCP servers configured beyond Anthropic-managed ones, but those
who have computer-use / browser MCPs get them for free.) A future
"Quack capabilities" Settings pane could let users opt-in to specific
MCP server bundles per-session.

### Tests

- `shellQuote` + `buildShellCommand` + `buildCommandScript` +
  `writeCommandScript` — kept; used by `continueInTerminal`,
  `showAgentsTUI`, `stopSession`, `openDisclaimerTerminal`. Shell-
  injection corpus retained.
- `ensureWorkspace` — kept.
- New: `parseBackgroundedBanner` against a corpus of expected
  banner formats (with/without ANSI escapes, different parenthetical
  suffixes, leading whitespace, multi-line stdout).
- New: argv assembly for `claude --bg` — verify exact flag order
  (`--bg`, `--permission-mode bypassPermissions`, `--name ...`,
  prompt as final positional).
- New: state.json parsing for the four known `state` values.
- New: notification body truncation (kept).
- The actual `Process` run is NOT unit-tested. End-to-end validation
  covers it manually.

### How the spawn actually happens (shell-injection safe)

Dispatch writes the shell command into a `.command` file and hands
the file to `/usr/bin/open`. macOS LaunchServices recognises the
`.command` extension as a terminal-executable script and opens it
in the user's default terminal (Terminal.app on a stock install,
respecting an override like iTerm or Warp if the user set one).
No AppleEvents are involved, so this path does **not** trigger
the Automation TCC prompt that `osascript`-based dispatch would —
`open` is a launchd helper, callable by any process.

Sketch:

```swift
// All quoting is in Swift; bash receives the prompt as a literal arg.
let command = "cd " + shellQuote(workspace.path) + " && claude " + shellQuote(prompt)
let script = """
#!/bin/bash
set -e
\(command)
"""

let url = NSTemporaryDirectory()
    .appending("openquack-kickoff-\(UUID().uuidString).command")
try script.write(toFile: url, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url)

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
task.arguments = [url]
try task.run()
task.waitUntilExit()  // open returns nearly instantly; we just check exit code.
// Best-effort delete the script ~30s later (Terminal reads it at open time;
// the file isn't needed once the spawned shell has it).
```

Why `.command` files rather than `osascript`-driven `do script`:

- **No Automation permission.** `osascript`'s `tell application
  "Terminal" to do script` is an AppleEvent, which goes through the
  Automation TCC pathway and prompts the user on first use. `open` is
  a stock LaunchServices helper that any process can call without TCC
  bookkeeping. Dispatch works on a fresh install with no extra grants.
- **Respects the user's default terminal.** `.command` opens in
  whatever app the user has bound to the extension — Terminal.app by
  default, but iTerm/Warp/Ghostty if configured. We don't hardcode
  Terminal.app.
- **Simpler.** One layer of escaping (POSIX single quotes in Swift)
  vs. two (Swift → AppleScript → shell).

Why we still want a visible window (vs. invoking `claude` headless
via `Process`): the user must see the agent work to follow approval
prompts, abort, type follow-ups. Headless dispatch hides the agent.

Tests: unit-test `shellQuote`, `buildShellCommand`, `buildCommandScript`,
and `writeCommandScript` against a corpus of prompts that should *not*
break out of the quoted argument — backticks, double quotes, single
quotes, `$(rm -rf /)`, newlines, NUL, Unicode/emoji. The file write is
verified to produce an executable file at mode 0700, and the tricky
shell command is verified to round-trip through write → read intact.

### Workspace lifecycle

`~/OpenQuackAgent/` is created on first kickoff with mode 0700. It is
**not** wiped between kickoffs — the user may have files there from a
prior session. A small `README.md` is written on creation explaining:

> This directory is OpenQuack's default workspace for voice-launched
> agent sessions. Each kickoff opens here. It's gitignored by default
> — files you want to keep, move out. Files you don't, delete. Nothing
> here is touched by OpenQuack itself.

A future Settings pane (M3) lets users override this. For v1 the path
is hardcoded in `AgentKickoffService.defaultWorkspace`.

## Privacy contract (binding)

This is the load-bearing section. OpenQuack's privacy promise has been
"audio and transcript stay on your Mac." Agent kickoff to Claude Code
**changes that** for kickoff-mode utterances — the transcript is
handed to `claude`, which routes through Anthropic's API under the
user's existing Claude Code auth. *Additionally*, kickoff runs the
agent with `--permission-mode bypassPermissions`, meaning the agent
executes shell commands, edits, and side effects without per-action
prompts.

Constraints derived from `docs/VISION.md` and AGENTS.md's hard rules:

1. **Default off.** The kickoff hotkey ships unbound. A user opting in
   sees a one-time consent modal naming both destinations:
   > "Agent kickoff sends what you say to Claude Code, which routes
   > through Anthropic's API under your Claude Code credentials. The
   > agent then runs *unattended* with permission bypass — it will
   > execute commands, edit files, and take system actions in
   > ~/OpenQuackAgent/ without asking you first. Your normal
   > dictation hotkey is unaffected and continues to paste locally.
   > Continue?"
   Stored as a `UserDefaults` flag, revocable by clearing the
   kickoff hotkey in Settings → Shortcut.
2. **Recording overlay shows a network indicator** any time the
   kickoff hotkey is the one that started recording. Same indicator
   SPEC-006 reserves for `requiresNetwork == true` agents.
3. **AGENTS.md hard rule.** "Adding a network call in the dictation
   or agent-dispatch hot path that wasn't there before" — this spec
   *adds* a network hop on the kickoff hot path. Explicit human
   approval is required before the implementation PR merges. The
   spec PR (this file) does not add a network call by itself.
4. **Audio is still deleted** by `AudioRecorder` after transcription,
   identical to dictation. The agent never sees audio, only the
   transcript.
5. **Workspace isolation.** The agent runs with cwd
   `~/OpenQuackAgent/`. It can still touch the wider filesystem
   (claude itself doesn't sandbox tool calls), but the default
   cwd is a contained location away from user repos. The README
   in that dir tells the user as much. Per-app or per-project
   workspace override is deferred (M3).
6. **No second-party retention by OpenQuack.** We don't log kickoff
   prompts or responses to disk beyond the existing `HistoryStore`
   (SPEC-014), which the user can disable; the same toggle covers
   both dictation and kickoff transcripts. The session itself is
   persisted by *Claude Code* (so `--resume` works), not by us.
7. **Notification permission** is requested in-context — the first
   time a kickoff completes — rather than at app launch. Declining
   keeps kickoff functional; completion surfaces as a menu-bar dot
   instead.

## Settings (deferred; v1 ships minimal)

For v1 the Settings → Shortcut pane gains exactly one new row: a
recorder for the kickoff hotkey, plus the one-time consent prompt the
first time it's bound. No agent picker, no workspace picker, no
"always allow approvals" toggle. Those are M3 material.

## Implementation order (atomic PRs)

| # | Title | SPEC cite | Effort | Notes |
|---|---|---|---|---|
| 1 | `docs(SPEC-031): one-shot agent kickoff` | SPEC-031 | XS | this spec; merges before any impl |
| 2 | `feat(agents): AgentKickoffService + Claude Code spawn` | SPEC-031 | S | adds `OpenQuackKit/Agents/`, unit tests on AppleScript escaping; **no UI yet** |
| 3 | `feat(hotkey,settings): kickoff hotkey + consent prompt` | SPEC-031 | S | wires the new `KeyboardShortcuts.Name`, Settings row, consent modal, overlay mode chip |
| 4 | `docs(integrations): one-line note on kickoff in claude-code.md` | SPEC-031 | XS | the integration doc gains a "Quick voice-to-action" section pointing at the kickoff hotkey |

PR #2 is shippable on its own — it's a service with tests, no user-
visible surface, no network call yet (it would only run when invoked,
which the absent hotkey prevents). PR #3 is the one that wires up the
hot path; **PR #3 is the one that needs Larry's explicit OK** per
AGENTS.md's network hard rule, called out in the PR description and
blocked on his comment.

PR #4 lands last, after the build is validated.

Codex (`codex`) is a follow-up: PR #5 is `feat(agents): CodexKickoff +
agent picker`. Spec-side, it's already named in non-goals; an
addendum to this spec covers the picker UX when we open that PR.

## Open questions

- **Multiple concurrent kickoffs.** v1 supports running several
  in-flight sessions simultaneously — each dispatched press gets its
  own `Process` + UUID; the session manager tracks them by ID.
  Notifications fire independently per session. Open: should we cap
  the concurrent count? Risk is the user fires N kickoffs and burns
  cost; benefit is fire-and-forget. v1 ships uncapped; revisit if
  feedback shows runaway use.
- **Cancellation.** No cancel-running-kickoff UI in v1. If the user
  realises mid-flight they didn't mean to fire, they can:
  - quit OpenQuack (kills child claude processes via SIGTERM on
    AppDelegate.applicationWillTerminate)
  - or `kill <pid>` from `claude agents --json`
  A cancel-button on a "live sessions" menu-bar pane is a follow-up.
- **What if `~/OpenQuackAgent/` is a Dropbox / iCloud path?** Some
  users keep `~` synced. Claude Code in a sync'd dir works but can
  fight the sync daemon on temp-file writes. Document but don't
  prevent; advise an opt-out path in the workspace `README.md`.
- **`fn` modifier for the kickoff hotkey.** SPEC-003a's `FnShortcut`
  is wired only for `.toggleRecording`; we'll need a parallel binding
  for `.agentKickoff`. The Fn monitor's design allows it but the
  storage key + UI need a one-line extension. Not blocking; flagged.
- **Live progress.** v1 captures output only on exit. For long
  kickoffs (>30s) the user may want to peek at intermediate progress.
  `--output-format stream-json` would expose tool-use events live.
  Defer until users actually ask — flagged here so the response
  window's layout can grow into it.

## Acceptance criteria (M2 ship gate)

A reviewer can validate the feature by running through the following
on an M-series Mac with `claude` installed and authenticated:

- [ ] **Hotkey infrastructure** — Settings → Shortcut shows two
      recorders: "Toggle recording" (existing) and "Agent kickoff"
      (new). Binding the latter to any combo persists across app
      relaunch.
- [ ] **Consent prompt fires once** the first time the kickoff hotkey
      is pressed; the modal names Anthropic *and* the
      bypass-permissions behavior explicitly; declining = no-op.
- [ ] **No Terminal popup, no trust dialog** — happy path opens NO
      Terminal window during dispatch. No "do you trust this folder?"
      prompt from Claude Code is shown to the user during a kickoff
      session.
- [ ] **Overlay mode chip** appears when recording was started by the
      kickoff hotkey; shows the network indicator; absent for normal
      dictation. Dismisses ~700 ms after dispatch.
- [ ] **Happy path** — with kickoff hotkey bound, the user presses
      it and says *"say hi in three lowercase words"*, releases.
      Within **2 s** of release, overlay flashes "Agent launched ✓"
      and dismisses. Within **15 s**, a macOS notification appears
      titled "claude finished" with body containing the response
      text. Clicking the notification opens the response window
      showing the prompt + full response + buttons.
- [ ] **Continue in Terminal** — clicking that button in the response
      window opens the user's default terminal at `~/OpenQuackAgent/`
      with `claude --resume <session-id>` running; the session's
      conversation context (the original prompt) is visible.
- [ ] **Shell-injection safety (Continue path)** — manually dictating
      prompts containing `` ` ``, `"`, `'`, `$(date)`, newlines, and
      emoji each round-trip through the kickoff and yield a
      Continue-in-Terminal command that quotes them literally.
- [ ] **Missing-CLI fallback** — temporarily rename `claude` out of
      PATH, press the kickoff hotkey, speak. The overlay shows the
      install-Claude-Code error banner; the transcript lands on the
      clipboard; the focused app's cursor is untouched. No
      notification is posted.
- [ ] **Privacy contract preserved** — dictation hotkey behaviour is
      unchanged; transcripts from dictation never route to Anthropic;
      `~/Library/Application Support/OpenQuack/` contains no new
      log file for kickoff prompts beyond what SPEC-014 already
      records.
- [ ] **Notification permission asked in-context** — fresh install,
      no notifications granted; first kickoff dispatch shows the
      system permission prompt *before* posting the result
      notification. Declining: completion surfaces as a dot on the
      menu-bar duck instead.
- [ ] **Tests** — `swift build && swift test` green;
      `AgentKickoffServiceTests` covers shell-quoting for the
      Continue-in-Terminal path, workspace lifecycle, and the
      argv assembly for the headless `claude -p` invocation.
- [ ] **No bench regression** — kickoff dispatch runs *after*
      Whisper completes; the transcription hot path is untouched.
      `swift run openquack-bench --models tiny --corpus
      bench/corpus/short` shows no WER / RTF delta vs. main.

## References

- [SPEC-003](SPEC-003-hotkey.md) — hotkey infrastructure reused for the
  new binding name
- [SPEC-003a](SPEC-003a-fn-key.md) — Fn-key recorder; the kickoff hotkey
  uses the same `FnAwareShortcutRecorder`
- [SPEC-005](SPEC-005-paste.md) — paste-at-cursor; the *other* fork of
  the post-transcription pipeline
- [SPEC-006](SPEC-006-agent-dispatch.md) — multi-turn closed-loop
  agent sessions; this spec deliberately does *not* subsume that one
- [`docs/integrations/claude-code.md`](../integrations/claude-code.md)
  — current dictation-into-Claude-Code workflow; PR #4 adds a kickoff
  section to it
- [AGENTS.md](../../AGENTS.md) hard rules — network on the
  agent-dispatch hot path requires explicit human approval; flagged
  for PR #3
