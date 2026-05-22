# SPEC-031 — Agent kickoff (one-shot voice-to-action)

**Status:** draft (M2 — adoption-band demo feature)
**Owner:** `OpenQuackKit/Agents/` + `OpenQuackApp/RecordingOverlay.swift`
**Last updated:** 2026-05-22

## Goal

A second, separately-bindable hotkey that takes the user's spoken
utterance and uses it as the seed prompt for a **fresh local-agent
session** (Claude Code first, Codex as a follow-up). The agent opens in
a new Terminal window in a known workspace and immediately starts
working on the request.

Voice → action, one-shot. The user doesn't have to be in any particular
app, doesn't position a cursor, doesn't paste anything. Press, speak,
release — a Claude Code session is already running on what you said by
the time you've taken your hands off the keyboard.

## User story

Two shapes, both real:

1. *Larry on a Tuesday morning, no editor open:*
   "Set me a timer for ten o'clock and put a Notification Centre entry
   on it." → presses the kickoff hotkey, speaks, releases. Terminal pops
   open, `claude` is already running with that exact prompt; it picks
   `osascript` to schedule the reminder and reports back in the same
   window. Total: ~2s overlay → ~5s for Claude to act.
2. *Larry mid-coding-session, OpenQuack repo in focus, sees a side task:*
   "In a scratch dir, sketch what a SwiftUI view that visualises the
   FnHotkeyMonitor's flag transitions would look like — just a one-file
   prototype, don't touch the repo." → kickoff hotkey, speaks, releases.
   A new Terminal window opens in `~/OpenQuackAgent/`, isolated from the
   real repo; Claude scaffolds the prototype there. Larry stays in the
   editor; the side task happens in parallel.

Both work because the kickoff hotkey is *not* the dictation hotkey.
Dictation still pastes at the cursor of whatever app is in focus (the
SPEC-005 path). Kickoff bypasses focus entirely and routes the
transcript into a *new agent process*, in a *known workspace*, with a
*visible window the user can intervene in*.

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

- **Multi-turn / session reuse.** Every kickoff is fresh. Continuing
  the conversation is something the user does *in the spawned Terminal
  window* by typing or by switching focus and pressing the dictation
  hotkey to paste at cursor (the existing SPEC-005 path). SPEC-006 owns
  the dedicated multi-turn surface; this spec doesn't.
- **Conversation panel / approval routing.** No new windows beyond the
  Terminal that hosts the agent. Approvals (Claude Code's "may I run
  this?" prompts) are answered by the user *in that Terminal*, the
  same as if they'd launched `claude` themselves.
- **Headless / background invocation.** Visible Terminal window only.
  Headless is a tempting follow-up for "set a timer" cases but is out
  of scope — the visible window IS the trust gradient for v1.
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
- **Sandbox / permission attenuation.** The spawned `claude` inherits
  the user's normal Claude Code permissions and approval mode. We do
  not insert ourselves between the user and the agent.

## UX

### Two hotkeys, separately bindable

```
Dictation hotkey  (SPEC-003, default ⌃⇧Space)  ──▶  Whisper → paste at cursor
Kickoff hotkey    (SPEC-031, default unset)    ──▶  Whisper → spawn agent in Terminal
```

The kickoff hotkey is bound under **Settings → Shortcut → Agent
kickoff**, using the same `FnAwareShortcutRecorder` introduced in
SPEC-003a — so a user who's already on `fn` for dictation can use
`fn+K` (or any other combo) for kickoff. The recorder, the
KeyboardShortcuts package, and the Fn monitor all already handle two
distinct shortcut names; no new infra is needed.

Default: **unset**. The feature is opt-in via Settings; first-launch
users see normal dictation, no surprise behaviour.

### The recording overlay distinguishes the two modes

While recording, the SPEC-004 overlay shows a small mode chip in the
top-right corner:

```
[●●● Recording 3.4s — paste at cursor]      ← dictation hotkey was pressed
[●●● Recording 3.4s — agent kickoff (claude)] ← kickoff hotkey was pressed
```

This is the user's only confirmation that the right hotkey fired
before they start speaking. Cancel (Esc / cancel hotkey) works the
same in both modes.

### After release

Both modes share the recording → transcribing pipeline. They diverge
at the *output* step:

```
Dictation:  Transcribe ──▶ PasteService.paste(transcript)      [SPEC-005]
Kickoff:    Transcribe ──▶ AgentKickoffService.dispatch(transcript)
```

For kickoff: a new Terminal.app window opens at the configured
workspace, with `claude "<transcript>"` already executing. The
recording overlay's terminal state is "Launched ✓ (claude)" — same
visual cadence as "Pasted ✓".

If the agent CLI is missing (`claude` not on `PATH`), the kickoff
fails loudly: an error banner in the overlay with a one-click "Install
Claude Code" link to `claude.com/claude-code`, and the transcript is
copied to the clipboard as a fallback so the user doesn't lose what
they said.

### What the user sees in Terminal

Whatever Claude Code shows when you launch it with a prompt. No
OpenQuack chrome inside the Terminal — we don't decorate the agent's
output, we just hand it the prompt and a workspace.

## Backend

### Public surface (small on purpose)

```swift
// Sources/OpenQuackKit/Agents/AgentKickoffService.swift

public enum AgentKickoffService {
    /// Hand `prompt` to a fresh Claude Code session in the agent
    /// workspace. Spawns Terminal.app as the host. Returns once the
    /// window has been requested; does NOT wait for the agent to
    /// finish.
    public static func dispatchClaudeCode(prompt: String) async throws

    /// `~/OpenQuackAgent/`. Created on first use with mode 0700.
    public static var defaultWorkspace: URL { get }

    /// `claude` resolvable on PATH. Cached for the process lifetime
    /// after first miss — re-check is opt-in via the Settings pane.
    public static func isClaudeAvailable() -> Bool

    public enum Error: Swift.Error {
        case claudeCLIMissing
        case terminalDispatchFailed(underlying: Swift.Error)
        case workspaceUnavailable(underlying: Swift.Error)
    }
}

public extension KeyboardShortcuts.Name {
    static let agentKickoff = Self("openquack.agentKickoff")
}
```

That's the whole API for v1. A protocol arrives when the second agent
lands; trying to abstract one impl is the kind of premature shape
SPEC-006 already covers in its bigger frame.

### How the spawn actually happens (shell-injection safe)

`Process` invokes `osascript`, passing the prompt as a separate `argv`
entry — never via shell interpolation. `osascript`'s `argv` is
exposed inside AppleScript as `argv`; we pipe it through `quoted form
of` (AppleScript's built-in shell-escape) before composing the
`do script` line. The transcript can contain anything (backticks,
quotes, `$()` substitutions, newlines) and it remains a literal
argument to `claude`.

Sketch:

```swift
let script = """
on run argv
    set thePrompt to item 1 of argv
    set theWorkspace to item 2 of argv
    tell application "Terminal"
        activate
        do script "cd " & quoted form of theWorkspace & " && claude " & quoted form of thePrompt
    end tell
end run
"""

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
task.arguments = ["-", prompt, workspace.path]  // "-" = read script from stdin

let stdin = Pipe()
task.standardInput = stdin
try task.run()
stdin.fileHandleForWriting.write(script.data(using: .utf8)!)
try stdin.fileHandleForWriting.close()
```

Why osascript rather than `Process` directly invoking `claude`:
launching `claude` headless gives the user no visible window and no
way to interact with approval prompts; opening Terminal.app and having
*it* run `claude` matches what the user would do by hand and inherits
the user's shell environment (PATH, dotfiles, `nvm` setup, etc.). The
two layers of `quoted form of` (one for the path, one for the prompt)
keep both safe.

Tests: unit test the AppleScript-generation helper with a corpus of
prompts that should *not* break out of the quoted argument — backticks,
double quotes, single quotes, `$(rm -rf /)`, newlines, NUL. The
generated script is captured as a string and asserted against expected
escaping (we don't run osascript in tests; the integration test in the
manual-QA pass covers end-to-end).

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
user's existing Claude Code auth.

Constraints derived from `docs/VISION.md` and AGENTS.md's hard rules:

1. **Default off.** The kickoff hotkey ships unbound. A user opting in
   sees a one-time consent modal naming the destination explicitly:
   > "Agent kickoff sends your dictated prompt to Claude Code, which
   > routes it through Anthropic's API under your Claude Code
   > credentials. The dictation hotkey is unaffected and continues to
   > paste locally. Continue?"
   Stored as a `UserDefaults` flag, revocable from Settings → Privacy.
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
5. **No second-party retention by OpenQuack.** We don't log kickoff
   prompts to disk beyond the existing `HistoryStore` (SPEC-014),
   which the user can disable; the same toggle covers both dictation
   and kickoff transcripts.

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

- **Terminal application choice.** v1 hardcodes Terminal.app because
  it's always present. iTerm2 users would prefer iTerm — the
  AppleScript shape differs (`do script` exists on both, but tab/
  window semantics differ). Defer to a Settings option in M3. The
  spawn primitive can grow a `host:` parameter then without changing
  callers.
- **What if `~/OpenQuackAgent/` is a Dropbox / iCloud path?** Some
  users keep `~` synced. Claude Code in a sync'd dir works but can
  fight the sync daemon on temp-file writes. Document but don't
  prevent; advise an opt-out path in the workspace `README.md`.
- **Workspace trust.** Claude Code added a workspace-trust dialog
  recently — first launch in a new directory prompts. The user sees
  this once per workspace and we don't need to handle it ourselves,
  but the first-kickoff UX will include that extra modal. Note in the
  acceptance criteria.
- **`fn` modifier for the kickoff hotkey.** SPEC-003a's `FnShortcut`
  is wired only for `.toggleRecording`; we'll need a parallel binding
  for `.agentKickoff`. The Fn monitor's design allows it but the
  storage key + UI need a one-line extension. Not blocking; flagged.

## Acceptance criteria (M2 ship gate)

A reviewer can validate the feature by running through the following
on an M-series Mac with `claude` installed and authenticated:

- [ ] **Spec merges first.** No implementation PR opens before this
      spec is merged or reviewed by Larry.
- [ ] **Hotkey infrastructure** — Settings → Shortcut shows two
      recorders: "Toggle recording" (existing) and "Agent kickoff"
      (new). Binding the latter to `fn+K` (or any combo) persists
      across app relaunch.
- [ ] **Consent prompt fires once** the first time the kickoff hotkey
      is bound; the modal names Anthropic explicitly; revoking from
      Settings → Privacy clears the binding.
- [ ] **Overlay mode chip** appears when recording was started by the
      kickoff hotkey; shows the network indicator; absent for normal
      dictation.
- [ ] **Happy path** — with kickoff hotkey bound, the user presses
      it and says *"list the files in this folder and tell me which
      is the largest"*, releases. Within **2 s** of release, a new
      Terminal window appears at `~/OpenQuackAgent/`; `claude` is
      already running on that prompt; within **10 s** the answer is
      visible. The transcript never appears at the previously-
      focused app's cursor.
- [ ] **Shell-injection safety** — manually dictating prompts
      containing `` ` ``, `"`, `'`, `$(date)`, newlines, and a long
      Unicode emoji string each spawn a session that treats the
      utterance as a literal argument (the agent quotes them back as
      the user's prompt rather than executing them).
- [ ] **Missing-CLI fallback** — temporarily rename `~/.local/bin/claude`,
      press the kickoff hotkey, speak. The overlay shows the
      install-Claude-Code error banner; the transcript lands on the
      clipboard; the focused app's cursor is untouched.
- [ ] **Privacy contract preserved** — dictation hotkey behaviour is
      unchanged; transcripts from dictation never route to Anthropic;
      `~/Library/Application Support/OpenQuack/` contains no new
      log file for kickoff prompts beyond what SPEC-014 already
      records.
- [ ] **Tests** — `swift build && swift test` green; a new
      `AgentKickoffServiceTests` covers AppleScript escaping for the
      prompt-corpus listed in the *Backend* section.
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
