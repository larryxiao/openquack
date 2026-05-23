# SPEC-031 — Agent kickoff (one-shot voice-to-action)

**Status:** draft (M2 — adoption-band demo feature)
**Owner:** `OpenQuackKit/Agents/` + `OpenQuackApp/{RecordingOverlay,ResponseWindow}.swift`
**Last updated:** 2026-05-23

## Goal

A second, separately-bindable hotkey that takes the user's spoken
utterance and dispatches it to a **fresh background `claude` session**
in a known workspace. The agent runs *headless* — no Terminal pops up,
no workspace-trust prompt, no focus stolen. When the agent finishes,
OpenQuack posts a macOS notification with the response preview;
clicking the notification opens a small floating window with the full
response and a button to drop into the live session in Terminal if
the user wants to continue.

Voice → action → notification. The user doesn't have to be in any
particular app, doesn't position a cursor, doesn't paste anything,
and isn't interrupted by a Terminal window appearing during whatever
they were doing.

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
Kickoff:    Transcribe ──▶ AgentKickoffService.startSession(…)
                            └─ overlay flashes "Agent launched ✓ (claude)"
                            └─ overlay dismisses after ~700 ms
                            └─ subprocess runs in background
```

No Terminal window appears. The recording overlay flashes the
launched-state for the same dwell time the dictation path uses for
"Pasted ✓", then dismisses. The kickoff process runs detached.

If the agent CLI is missing (`claude` not on `PATH`), the kickoff
fails loudly: an error banner in the overlay with a one-click "Install
Claude Code" link to `claude.com/claude-code`, and the transcript is
copied to the clipboard as a fallback so the user doesn't lose what
they said.

### Notification on completion

When the agent finishes, OpenQuack posts a notification via
`UNUserNotificationCenter`:

```
┌──────────────────────────────────────────────┐
│ 🦆 OpenQuack                                  │
│ ──────────────────────────────────────────── │
│ claude finished                               │
│ Timer set for 10:00. macOS reminder           │
│ scheduled via osascript; user will be …       │
└──────────────────────────────────────────────┘
```

Title: `claude finished` (or `claude failed` if the process exited
non-zero). Body: first ~150 characters of stdout, trimmed at a word
boundary. Notifications use a `kickoffResult` category whose default
action opens the response window (below).

Permission: `UNUserNotificationCenter.current().requestAuthorization`
is called the first time a kickoff is dispatched — never on app
launch — so the prompt arrives in context, not as one of N first-run
modals. If the user denies notification permission, completed
kickoffs surface as a dot on the menu-bar duck instead; clicking the
duck opens the response window directly.

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
│  claude responded (5.2s, exit 0):                      │
│  ─────────────────────────────────────────            │
│    Timer set for 10:00.                                │
│    Created reminder via osascript:                     │
│      tell application "Reminders" …                    │
│    macOS reminder scheduled; the system will fire     │
│    a notification at 10:00 sharp.                      │
│                                                       │
│  [Copy response]  [Continue in Terminal]  [Close]      │
│                                                       │
└────────────────────────────────────────────────────────┘
```

- **Copy response** — `NSPasteboard.general.setString(response, …)`.
- **Continue in Terminal** — reuses the `.command`-file spawn
  primitive from this spec's earlier draft: writes a one-line
  `cd <workspace> && claude --resume <session-id>` to a `.command`
  file in `NSTemporaryDirectory`, calls `open(1)` on it. The
  user's default terminal opens, attaches to the persisted session
  by ID, picks up where claude left off.
- **Close** — dismisses the window. The session remains on disk;
  the user can still resume it via Claude Code's own `--resume`
  picker.

The response window does NOT auto-open on completion — that would be
intrusive. It only opens via notification click or menu-bar fallback.

## Backend

### Public surface

```swift
// Sources/OpenQuackKit/Agents/AgentKickoffService.swift

public enum AgentKickoffService {
    /// Start a Claude Code session in the background, seeded by
    /// `prompt`, in the default workspace. Returns the live session
    /// handle. The process is detached (no controlling TTY) — `claude`
    /// runs headless under `--print`, so its workspace-trust dialog
    /// is skipped automatically. The caller is responsible for
    /// awaiting the session's completion (which fires when the
    /// process exits).
    public static func startClaudeCode(prompt: String) async throws -> KickoffSession

    /// `~/OpenQuackAgent/`. Created on first use with mode 0700.
    public static var defaultWorkspace: URL { get }

    /// `claude` resolvable on PATH plus common manual-install locs.
    public static func isClaudeAvailable() -> Bool

    public enum Error: Swift.Error, Equatable {
        case claudeCLIMissing
        case emptyPrompt
        case invalidPrompt           // NUL or other unsafe content
        case workspaceUnavailable
        case launchFailed
    }
}

/// One live (or recently-completed) kickoff. Each kickoff press
/// produces a new session value; OpenQuack does not reuse them.
public struct KickoffSession: Sendable {
    public let id: UUID
    public let workspace: URL
    public let prompt: String
    public let startedAt: Date
    /// `claude --name "OpenQuack: <40-char prompt prefix>"` so the
    /// session is recognisable in Claude Code's own `--resume` picker
    /// and in `claude agents --json`.
    public let displayName: String

    /// Stream the agent's output as it accumulates. The stream
    /// completes when the agent process exits. The aggregated result
    /// (response text + stderr + exit code + duration) is delivered
    /// via the completion handler set by the session manager.
    public func awaitResult() async throws -> KickoffResult
}

public struct KickoffResult: Sendable, Equatable {
    public let sessionId: UUID
    public let response: String        // stdout, trimmed
    public let stderr: String          // captured for failure surface
    public let exitCode: Int32
    public let durationSeconds: Double
    public var succeeded: Bool { exitCode == 0 }
}

public extension KeyboardShortcuts.Name {
    static let agentKickoff = Self("openquack.agentKickoff")
}
```

### How dispatch actually happens

```swift
let id = UUID()
let workspace = try ensureWorkspace(at: defaultWorkspace)
let claudeBin = resolveClaudePath()!.path

let task = Process()
task.executableURL = URL(fileURLWithPath: claudeBin)
task.currentDirectoryURL = workspace
task.arguments = [
    "-p",
    "--session-id",      id.uuidString.lowercased(),
    "--permission-mode", "bypassPermissions",
    "--output-format",   "text",
    "--name",            "OpenQuack: \(prompt.prefix(40))",
    prompt,
]

let stdout = Pipe()
let stderr = Pipe()
task.standardOutput = stdout
task.standardError  = stderr
task.standardInput  = FileHandle.nullDevice  // explicitly no TTY

try task.run()
// Return the session handle immediately; a background Task in the
// session manager awaits `task.terminationHandler`, reads the
// pipes, and posts the notification.
```

No `.command` files for the headless dispatch. No `osascript`, no
`open(1)`, no AppleEvents — just `Process` with stdio piped. The
prompt is passed as a single argument (`argv[N]`); shell quoting is
*not* needed because no shell sits between us and `claude`. (The
shell-quoting code path is still kept for the "Continue in Terminal"
button — see UX above — where we genuinely need a `.command` file to
launch a user-facing terminal with `claude --resume <id>`.)

Why `--print` headless rather than the interactive default:
- **No workspace-trust dialog.** Per `claude --help`, the trust
  prompt is skipped when stdout isn't a TTY, which we guarantee by
  piping.
- **No window.** The agent runs as a background process; the user's
  workflow isn't interrupted.
- **Clean exit on completion.** The process exits when the agent has
  finished, so we have a natural completion signal (`Process.
  terminationHandler`) without polling.

Why `--permission-mode bypassPermissions`:
The agent runs unattended — there's no UI for the user to approve
individual actions during the run. Bypassing approvals is the cost
of fire-and-forget; it's why kickoff is opt-in with a consent prompt
that says so explicitly (see Privacy contract). The user can still
review the agent's actions in the response window when it finishes,
and the workspace is a known sandbox they control.

Why `--output-format text` rather than `json` or `stream-json`:
v1 surfaces the response as a single block in the response window.
JSON output would only be needed for structured rendering, which
isn't part of the v1 UI. Stream-json would enable live progress
into the response window — flagged as a follow-up.

### Session manager + notification

```swift
@MainActor
public final class AgentSessionManager: ObservableObject {
    @Published public private(set) var liveSessions: [UUID: KickoffSession] = [:]
    @Published public private(set) var completedSessions: [KickoffResult] = []

    public func dispatch(prompt: String) async throws {
        let session = try await AgentKickoffService.startClaudeCode(prompt: prompt)
        liveSessions[session.id] = session
        Task.detached { [weak self] in
            let result = try await session.awaitResult()
            await self?.handle(result: result, session: session)
        }
    }

    private func handle(result: KickoffResult, session: KickoffSession) {
        liveSessions[session.id] = nil
        completedSessions.append(result)
        // Cap to N most-recent (~20) so memory bounded.
        if completedSessions.count > 20 {
            completedSessions.removeFirst(completedSessions.count - 20)
        }
        postNotification(result: result, session: session)
    }
}
```

The notification carries the session UUID as `userInfo["sessionId"]`;
the click handler in `AppDelegate` looks up the result and opens the
response window.

### Workspace lifecycle

Unchanged from v1: `~/OpenQuackAgent/` is created on first use with
mode 0700, README written explaining the purpose. Idempotent.

### Tests

- `shellQuote` + `buildShellCommand` + `buildCommandScript` +
  `writeCommandScript` — kept verbatim from v1; used by the
  "Continue in Terminal" button. Same shell-injection corpus.
- `ensureWorkspace` — kept.
- New: argument-array assembly for `claude -p` — verify the exact
  argv list given a prompt, including `--session-id` lowercase,
  `--name` truncation at 40 chars, `--output-format text`,
  `--permission-mode bypassPermissions`.
- New: response truncation for the notification body (word-boundary
  cut at ~150 chars).
- The actual `Process` run is *not* unit-tested (it spawns a real
  claude session). End-to-end validation covers it manually.

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
