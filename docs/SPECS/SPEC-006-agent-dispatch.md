# SPEC-006 — Agent dispatch (closed-loop sessions)

**Status:** draft v2 (M2 — the differentiating feature)
**Owner:** `OpenQuackKit/Agents/`
**Last updated:** 2026-04-27 (rewritten for multi-turn sessions; original
v1 modelled one-shot dispatch which lost the multi-turn nature of Claude
Code and similar agents — see "Why the rewrite" below.)

## Goal

After the user speaks, dispatch the transcript to a configured agent backend
(Claude Code, Ollama, MLX-LM, …) which works on the request and **streams
events back** — status, partial output, tool-use, approval prompts, side
effects — that OpenQuack surfaces in a **persistent conversation panel**.
Subsequent voice presses go to the *same session* by default, so multi-turn
interaction works naturally.

Voice → action, sustained — not voice → action, fire-and-forget.

## Why the rewrite

The earlier v1 of this spec modelled dispatch as a single call:

```swift
agent.dispatch(_ utterance: String) async throws -> AgentResult
```

That works for "type this" or a simple "run that" command. It does NOT
work for the actual high-leverage flows the product is for:

- *"fix the bug in main.py"* → agent: *"I see two bugs. Which one?"* → user replies
- agent works for 30 s, emitting status updates, then asks to run a test
- user approves → agent runs test → reports outcome → asks if it should commit
- user says "yes, commit and open PR" → agent does, reports PR URL

The user explicitly flagged this on 2026-04-27: *"for agent dispatch, i
think some thoughts can be put into it for a close loop agent experience.
otherwise it seems to be only one way, single shot and how do we get back
or interactive from the session."*

This v2 design accepts that **the unit is a session, not a request**.

## Non-goals (still)

- Building a new agent. We dispatch to existing ones.
- Cloud hosting / multi-tenant.
- Smart intent classification — every utterance routes to the active session
  unchanged. (We do reserve a "no active agent → paste-only" fallback.)

## Public surface (v2 sketch)

```swift
public protocol Agent: AnyObject {
    static var agentName: String { get }
    /// Whether dispatch involves any network IO. Surfaced in the overlay.
    var requiresNetwork: Bool { get }
    /// Begin a session. Long-lived; multiple turns submitted into it.
    func startSession(context: AgentContext) async throws -> any AgentSession
}

public protocol AgentSession: AnyObject {
    var id: String { get }
    var startedAt: Date { get }
    var agentName: String { get }

    /// Submit a turn. Yields events as the agent works; completes (with
    /// either `.done` or a thrown error) when the turn finishes. The session
    /// remains open after — call `submit` again for the next turn.
    func submit(_ utterance: String) -> AsyncThrowingStream<AgentEvent, Error>

    /// Reply to an `.approvalRequest` event from the current or prior turn.
    func reply(approval: ApprovalReply, for requestID: String) async throws

    /// Cancel the in-flight turn (e.g. user pressed cancel hotkey while
    /// agent was working). Session stays open.
    func cancelCurrentTurn() async

    /// End the session. Releases subprocess, frees resources, makes the
    /// session no longer usable.
    func close() async
}

public enum AgentEvent: Sendable {
    /// Free-form status string (e.g. "Reading main.py", "Searching for usages").
    case status(String)
    /// A streamed text chunk to append to the agent's response. Multiple
    /// `partialText` events per turn are normal.
    case partialText(String)
    /// The agent invoked a tool. Surfaced for transparency.
    case toolUse(name: String, summary: String)
    /// The agent wants approval before doing something. The session is
    /// PAUSED until `reply(approval:for:)` is called.
    case approvalRequest(prompt: String, id: String)
    /// The complete final answer for this turn (also reachable by
    /// concatenating `partialText` chunks; emitted for convenience).
    case finalText(String)
    /// The agent did something off-screen (opened a PR, ran a command).
    /// Surfaced as a chip in the conversation panel.
    case sideEffect(summary: String)
    /// Turn complete. The next `submit` starts a new turn in the same session.
    case done
}

public enum ApprovalReply: Sendable {
    case approve
    case deny
    case approveAlways    // remember for this session
}

public struct AgentContext: Sendable {
    public let foregroundApp: String?      // best-effort
    public let workspaceDirectory: URL?    // configured per agent
    public let timestamp: Date
}

public actor AgentRouter {
    public init(active: AgentKind, context: AgentContext)
    public var activeKind: AgentKind { get }
    public var currentSession: (any AgentSession)? { get }

    /// Submit a turn into the current session, starting one if none exists.
    public func submitTurn(_ utterance: String) -> AsyncThrowingStream<AgentEvent, Error>

    /// Tear down the current session and start fresh on next submit.
    public func endCurrentSession() async

    /// Switch agent backend. Ends the current session if any.
    public func setActive(_ kind: AgentKind) async
}

public enum AgentKind: String, Sendable, CaseIterable {
    case passthrough     // no agent — paste at cursor (current dictation behaviour)
    case claudeCode      // local `claude` CLI subprocess
    case ollama          // local Ollama HTTP
    case mlxLM           // in-process via mlx-swift-lm (M3+)
}
```

## Agents

### 1. `PassthroughAgent` — default, no network

Models a session as "every utterance becomes a single `.finalText` event,
followed by `.done`." There's no state across turns. This is OpenQuack-
as-dictation and remains the default until the user explicitly picks an
agent. `requiresNetwork == false`.

### 2. `ClaudeCodeAgent` — M2 target

- Spawns `claude` (the user's CLI) as a long-running subprocess in
  `context.workspaceDirectory`. The session owns the process for its
  lifetime; `close()` terminates it cleanly.
- Uses Claude Code's streaming output mode (e.g. `claude --output-format
  stream-json` or the equivalent at implementation time) so each event
  the agent emits maps onto an `AgentEvent`.
- Pipes utterances and approval replies via stdin.
- Surfaces tool-use as `.toolUse` events; surfaces approval prompts as
  `.approvalRequest` (the session pauses until `reply(approval:for:)`
  unblocks it).
- `requiresNetwork == true`. Network indicator is mandatory in the
  conversation panel and the overlay.

### 3. `OllamaAgent` — M3

- Local Ollama HTTP API (`http://localhost:11434`).
- Configurable model. Server-side conversation history is keyed by
  session ID.
- `requiresNetwork == false` (loopback is treated as not-network).

### 4. `MLXLMAgent` — M3+

- In-process via `mlx-swift-lm`. Best privacy story for "fully local".
- Holds conversation in memory; no subprocess.

## Session UX

Three new surfaces compose the closed-loop experience. None of these
exist yet; each gets its own follow-up spec.

1. **Conversation panel** (new, M2) — a separate floating window (NOT the
   menu-bar popover) that shows the full turn history of the active
   session. Opens automatically when a non-passthrough agent has been
   used. Closing the window does **not** end the session; an explicit
   "End conversation" button does.

   Layout: chat-bubble style. Each turn shows the user's transcribed
   utterance, then the agent's status updates, tool-uses, partial text
   that aggregates into the final answer, and any side-effect chips.
   Approval prompts get an inline Approve / Deny / Always button row,
   keyboard-navigable, and a "yes / no" voice command also resolves them
   (see voice-approval below).

2. **Compact reply overlay** — when the agent is mid-turn and emits a
   `.approvalRequest` event, the floating recording overlay (SPEC-004)
   morphs into an "approval pill" with the prompt + buttons. Provides
   keyboard- or voice-driven approval without opening the conversation
   panel.

3. **Voice approval** (M3) — while an approval is pending, pressing the
   hotkey and saying "yes" / "no" / "approve" / "deny" / "always" maps
   to the corresponding `ApprovalReply`. Off by default; opt-in via
   Settings → Agent. When off, only buttons / keyboard work.

## Session lifecycle

```
no-session ──hotkey+speak──▶ session A starts ──hotkey+speak──▶ turn 2 in A
                                                ──"end conv"───▶ session closed
                                                ──switch agent─▶ A closed → B starts
```

- Sessions are scoped per (agent, workspaceDirectory) pair. Switching
  workspace ends the current session.
- Sessions DO NOT persist across app restarts (M2). M3 may add
  Claude-Code-style `--resume <session_id>` so a hot restart re-attaches.

## Privacy contract (binding)

1. Default active agent remains `passthrough`. Fresh installs do not
   route transcripts anywhere external.
2. Switching to a network-using agent triggers a one-time consent prompt
   naming the destination ("This routes your transcripts to Anthropic
   via Claude Code. OK?"). Stored as a per-agent flag, revocable in
   Settings → Privacy.
3. Both the recording overlay AND the conversation panel show a network
   indicator any time the active agent has `requiresNetwork == true`.
4. `localhost` is NOT treated as network. (Ollama/MLX local servers don't
   trigger the indicator.)
5. Conversation history is held in memory only; nothing is written to
   disk by default. A future "save conversation" feature must be opt-in
   per-session.
6. Audio for any turn is still deleted by `AudioRecorder` after
   transcription, same as dictation mode. The agent never sees raw
   audio, only the transcript.

## Open questions

- **Stream format for Claude Code.** Verify the actual streaming API at
  impl time (`claude --output-format stream-json` or its successor). The
  AgentEvent mapping must be deterministic and testable.
- **Approval semantics.** Does Claude Code's `--permission-mode` mode flag
  let us route approvals through OpenQuack's UI vs. its own CLI prompt?
  Settle before the agent ships.
- **Cancellation.** Cancel-current-turn semantics: kill in-flight tool
  calls, or only stop streaming events to us? Lean kill-and-tell-agent so
  the user gets the abort they asked for, accepting that some side effects
  may already be applied.
- **Multi-modal input.** Mid-session keyboard typing for replies — does
  the conversation panel accept text input as well as voice? Lean yes;
  voice-only would be hostile to typed clarifications.
- **Concurrent sessions.** Single active session per app? Multiple, with
  a switcher? Lean single for v2.0; revisit if the use case shows up.

## Implementation order

1. **`PassthroughAgent` + `AgentRouter` + conversation panel skeleton** —
   ratify the protocol against the simplest agent. The conversation panel
   shows just user turns (no agent reply pane) since passthrough has no
   meaningful response. (S, separate spec for the panel.)
2. **`ClaudeCodeAgent` MVP** — single-turn-at-a-time, no approvals yet,
   surface partial text + tool-use. Confirm session reuse works across
   hotkey presses. (M)
3. **Approval prompt flow** — overlay morph + buttons. (S)
4. **Voice approval** — Settings opt-in, simple "yes"/"no" parsing. (S)
5. **`OllamaAgent`** — once the protocol shape is proven by Claude Code. (S)
6. **`MLXLMAgent`** — last; needs the LLM weights story. (M)

## References

- v1 of this spec (one-shot dispatch model) — superseded.
- Anthropic's Claude Code CLI docs (verify streaming output flag at
  implementation time).
- v0.1's `thinker.py` had a one-shot LLM-call pattern; *concepts* only,
  not code.
- `Sources/OpenQuackKit/` will gain `Agents/` once this spec ratifies.
