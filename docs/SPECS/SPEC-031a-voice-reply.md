# SPEC-031a — Voice reply to live agent sessions

**Status:** draft
**Extends:** [SPEC-031](SPEC-031-agent-kickoff.md)
**Owner:** `OpenQuackKit/Agents/` + `OpenQuackApp/{AgentSessionManager,RecordingOverlay,ResponseWindow}.swift`
**Last updated:** 2026-05-24

## Goal

After a kickoff is in flight (or has just blocked asking the user for
input), let the user reply *by voice* to that specific session
without typing or opening a terminal. Two trigger surfaces:

1. **Modifier-key reply** — pressing the kickoff hotkey while holding
   ⌥ (Option) targets the most-recent live session instead of
   spawning a new one. Visible in the recording overlay as
   *"↳ replying to <displayName>"* so the user can confirm before
   speaking.
2. **Notification voice-reply action** — the macOS notification that
   fires on completion (or "needs input") gains a second action
   *"Voice reply"* alongside *"Open response"*. Click → OpenQuack
   starts recording in reply-to-<short-id> mode → release → transcript
   appended to that specific session as the next turn.

Voice → action → notification → voice → continued action. The full
loop without leaving wherever the user is.

## Why now, and why not SPEC-006

SPEC-006 (multi-turn closed-loop sessions) is the long-game design
for in-app conversation panels, approval routing, voice-approval, and
session reuse from the dictation hotkey. It's a big surface and
remains deferred per the adoption-pivot ROADMAP.

SPEC-031a is *much* smaller in scope. It composes with SPEC-031's
existing primitives (live sessions on the claude daemon, FSEventStream
watcher, response window) and adds:

- A second trigger path for kickoff that targets-by-id instead of
  spawning
- One new flag on the existing notification (the action)
- A reply-injection mechanism (one new service method)

No conversation panel, no in-app approval routing, no session-reuse
from the dictation hotkey. Those stay with SPEC-006.

## Non-goals (explicit)

- **Conversation panel UI.** The reply happens via voice and lands in
  the session; the user sees state updates via the existing
  notification + response-window surfaces. SPEC-006 owns the panel.
- **Voice approval of agent tool calls.** Mid-flight per-action
  approval (the agent asks "may I run X?") stays outside this spec.
  Kickoff already runs with `--permission-mode bypassPermissions`;
  reply doesn't change that.
- **In-app text input** to a live session. Typing follow-ups goes
  through `claude attach <id>` in Terminal as today. v3 of SPEC-031
  considered inline text in the response window and deferred it.
- **Picker UI for choosing which session to reply to.** v1 of
  SPEC-031a auto-targets "most-recent live session, preferring
  blocked over working." Explicit picker is M3.
- **Cross-machine reply** (replying to a session running on another
  Mac). Out of scope.

## UX

### Trigger 1: modifier-key reply

```
                    ┌─ ⌃⇧Space alone  → existing SPEC-031 kickoff (new session)
Kickoff hotkey ──┤
                    └─ ⌃⇧Space + ⌥   → SPEC-031a voice reply (most recent live session)
```

Implementation: the kickoff hotkey handler reads
`NSEvent.modifierFlags.contains(.option)` at handler-call time to
decide which path. No second registered shortcut name — the modifier
is overlaid on the existing kickoff binding. (KeyboardShortcuts
package fires only the bound combo, but inside the handler we can
introspect modifiers via `NSEvent.modifierFlags` synchronously.)

If the user has rebound the kickoff hotkey to something that doesn't
include a free ⌥ slot (e.g. they bound it to ⌥+something), the
modifier-overlay scheme falls back to: any kickoff-press while at
least one live session exists shows a *brief* overlay hint *"⌥+press
to reply instead"*; modifier-key reply remains opt-in.

Auto-target selection:

1. If there's a live session in state `blocked` → reply to it
2. Else if there's at least one live session in state `working` →
   reply to the most-recently-started
3. Else → show a brief overlay error *"No live session to reply to"*
   and fall through to spawning a new session (SPEC-031 default
   behaviour)

The recording overlay shows the target while recording:

```
[●●● Recording 2.4s · ↳ replying to "OpenQuack: set timer for 10am" (a3c4272d)]
```

so the user can confirm before speaking. Esc / cancel hotkey aborts
the reply without sending.

### Trigger 2: notification voice-reply action

The existing notification (SPEC-031) gains a second action button
beside the default *"Open response"*:

```
┌──────────────────────────────────────────────────────┐
│ 🦆 OpenQuack                                          │
│ ──────────────────────────────────────────────────── │
│ claude needs input                                    │
│ "I see two main.py files — which one do you want me  │
│  to fix?"                                             │
│ [Open response]  [Voice reply]                        │
└──────────────────────────────────────────────────────┘
```

Click *"Voice reply"* →

1. Notification dismisses
2. OpenQuack focuses (briefly — accessory app, doesn't steal full
   focus)
3. Recording starts in reply-to-`<short-id>` mode (overlay's mode
   chip shows the target session)
4. User speaks, releases (or cancels)
5. Transcript injected into the target session

The session ID is unambiguous (carried in the notification's
`userInfo["shortID"]`), so there's no ambiguity even if multiple
sessions have notifications outstanding.

### Response window also gets a voice-reply button

When the response window is showing a session that's still in
`blocked` state, the button row gains *"Voice reply"* alongside the
existing buttons:

```
[Copy] [Continue in Terminal] [All kickoffs] [Voice reply] [Stop] [Close]
```

Click → window closes (or stays open with a small recording chip) →
OpenQuack starts recording in reply mode → same path as Trigger 2.

### What the user sees during reply

The recording overlay's mode chip changes from:

```
[claude]              ← new kickoff (existing SPEC-031)
```

to:

```
[↳ a3c4272d]          ← voice reply targeting that session
```

Same colour palette / globe icon (still network-bound), with a small
return-arrow glyph signaling "reply" semantics. Hovering or
long-pressing the chip surfaces the session's displayName.

## Backend

### Public surface

```swift
// Sources/OpenQuackKit/Agents/AgentKickoffService.swift

public extension AgentKickoffService {
    /// Append `prompt` as the next turn in an already-running
    /// daemon-managed session. The session continues; its state.json
    /// transitions back to `working` (then to `done` or `blocked` on
    /// completion). The same FSEventStream watcher established at
    /// kickoff time picks up the new transition and fires the next
    /// notification.
    ///
    /// Mechanism: TBD at impl time — verify whether
    /// `claude --resume <id> -p <text>` cleanly appends to a live
    /// bg session or whether we need a daemon-socket call. See open
    /// questions.
    static func voiceReply(prompt: String, to shortID: String) throws
}

public enum AgentKickoffService.Error /* extended */ {
    /// Voice reply targeted a session that's no longer live.
    case noLiveSession(shortID: String)
    /// Reply injection failed (subprocess error / daemon protocol).
    case replyInjectionFailed(underlying: Swift.Error?)
}
```

### Mode coordination

`AppState.RecordingMode` gains a third case so the recording
pipeline knows where to route the transcript:

```swift
public enum RecordingMode: Equatable {
    case dictation
    case agentKickoff
    case agentReply(shortID: String, displayName: String)
}
```

The post-transcribe dispatch fork (currently a switch over
`.dictation` / `.agentKickoff`) gains a third arm for `.agentReply`
that calls `voiceReply(prompt:to:)`. Failure handling: stash the
transcript on the clipboard with a clear error label (same shape as
existing kickoff failures).

### Notification action registration

Update `AgentSessionManager.registerNotificationCategory()` to
register a second `UNNotificationAction` with identifier
`"openquack.kickoff.voiceReply"`. The category becomes:

```swift
let openAction = UNNotificationAction(
    identifier: "openquack.kickoff.open",
    title: "Open response",
    options: [.foreground]
)
let replyAction = UNNotificationAction(
    identifier: "openquack.kickoff.voiceReply",
    title: "Voice reply",
    options: [.foreground, .authenticationRequired]  // ensure app is unlocked
)
let category = UNNotificationCategory(
    identifier: notificationCategory,
    actions: [openAction, replyAction],
    intentIdentifiers: [],
    options: []
)
```

The click handler in `AppDelegate`'s `UNUserNotificationCenterDelegate`
gains a switch on `response.actionIdentifier`:

- `openquack.kickoff.open` (or default) → open response window
  (existing path)
- `openquack.kickoff.voiceReply` → look up session by shortID, set
  `recordingMode = .agentReply(shortID, displayName)`, start recording

If the session is no longer live by the time the action fires (user
ignored the notification for hours, session ended), the action shows
a brief overlay error and dismisses.

## Reply-injection mechanism

This is the load-bearing technical question for v1: **how do we
append a turn to a live daemon-managed session?**

Two paths to evaluate at impl time:

**Path 1: `claude --resume <id> -p <text>`** (documented).
   - Pro: Uses public CLI flags only. Same shape as `--bg`.
   - Pro: We already understand `-p` semantics from v2 of SPEC-031.
   - Con: Spawns a SECOND claude process attached to the same session.
     Could conflict with the live bg worker on the rendezvous socket.
     Needs empirical verification.
   - Con: `-p` is "print and exit" semantics — does the bg worker
     pick up the appended turn and continue?

**Path 2: Daemon control socket** (undocumented).
   - The daemon at `/tmp/cc-daemon-501/<id>/control.sock` accepts
     ops like `dispatch` (per subagent 1's reverse-engineering).
     There likely exists an `inject` / `submit` / `turn` op for the
     agent view's "user types into a live session" path.
   - Pro: First-class — same mechanism the agent view uses.
   - Con: Undocumented; brittle across claude versions. Strict Zod
     schema validation in the daemon.

**Path 3: Write to the session's JSONL transcript directly**
   - `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` is the
     source of truth for the session's conversation history.
   - Append a user-turn JSON object and the bg worker should see the
     new entry on its next scan.
   - Pro: No new external surface; just a file append.
   - Con: Race condition with the bg worker mid-write. Schema is
     internal (claude's persistence format).

**Recommendation (v1)**: try Path 1 first — empirically test whether
`claude --resume <id> -p "<reply>"` cleanly appends and the bg worker
picks it up. If it does, ship. If it conflicts, fall back to Path 2
with explicit version-pinning + a brittleness note. Path 3 is the
last resort.

## State coordination after reply

After a reply lands:

1. Session's `state.json` transitions: `blocked → working` (or
   `working → working` if reply arrived during work)
2. OpenQuack's existing `StateFileWatcher` for that session picks up
   the transition
3. Watcher logic (`AgentSessionManager.handle(state:session:)`) treats
   the `working` re-entry as "session resumed" — clears any cached
   terminal `KickoffResult` for that session
4. When the session next reaches a terminal state (`done`/`blocked`),
   notification fires as usual

No new watcher needed. No new file paths. The reply just unblocks the
existing observation loop.

## Failure modes

| Failure | Behaviour |
|---|---|
| Modifier-key reply, no live session | Brief overlay error *"No live session to reply to"*; falls through to new kickoff (per SPEC-031 default) |
| Notification action, session ended between notify + click | Brief overlay error *"Session a3c4272d has ended"*; transcript stashed on clipboard |
| Reply injection fails (subprocess error) | Clipboard fallback; overlay shows *"Reply failed — transcript on clipboard"* |
| User Esc / cancels mid-recording | No reply sent; session remains in its previous state |
| Reply transcript empty after trimming | No-op; brief overlay error *"Nothing to say"* |
| Two replies dispatched in rapid succession | Both queue against the same session; second waits for first to land. Document but don't prevent. |

## Privacy / consent

No new consent prompt. Voice reply uses the same network hop +
permission-mode bypass that the user already consented to at kickoff
time. The recording overlay's mode chip + the notification action
title (*"Voice reply"*, not generic *"Reply"*) keep the user aware
that voice is going to a network agent.

## Open questions

- **Reply injection mechanism.** Verify Path 1 (`claude --resume
  <id> -p`) empirically against a live `--bg` session. If it
  conflicts with the rendezvous socket or doesn't trigger the bg
  worker to continue, fall back to Path 2 (daemon socket) and
  document brittleness.
- **State transition on reply when session was `done`.** What if the
  user replies to a session that has already settled to `done`?
  Probably the session takes the reply and transitions back to
  `working` (claude sessions can always be re-entered). Verify; if
  not, voice-reply against a done session falls back to spawning a
  new session that includes the prior transcript as context (i.e.
  `claude --resume <id>` style).
- **Modifier-key collisions** with apps that use ⌥+⌃⇧Space (e.g.
  some Spotlight replacements). v1 accepts the collision and lets
  the user rebind. Flag as a Settings UI improvement.
- **Notification permission denial.** Trigger 2 doesn't work if the
  user denied notification perm. Trigger 1 (modifier key) still
  does, so the feature isn't gated on notifications. Document.
- **Multi-user / multi-claude** machines. The `claude agents --json`
  list is per-user, so we're fine.

## Implementation order

| # | Title | SPEC | Effort | Notes |
|---|---|---|---|---|
| 1 | `docs(SPEC-031a): voice reply to live sessions` | SPEC-031a | XS | this spec; merges before any impl |
| 2 | `feat(agents): voiceReply + injection probe` | SPEC-031a | S | adds `voiceReply(prompt:to:)`; resolves Path 1 vs 2 vs 3 empirically; ships standalone with tests for argv assembly + state-coordination |
| 3 | `feat(hotkey,overlay): modifier-key reply trigger + overlay chip` | SPEC-031a | S | reads `NSEvent.modifierFlags` in the kickoff handler; adds `.agentReply` recording mode; overlay chip changes to "↳ shortID" |
| 4 | `feat(notification,response-window): voice-reply action + button` | SPEC-031a | S | registers the action, wires the click handler, adds the button to the response window for blocked sessions |

PR #2 lands first (mechanism settled), then #3 + #4 in either order.

## Acceptance criteria (M2 ship gate)

Reviewer validates on an M-series Mac with `claude` ≥ 2.1.143 and
notification permission granted:

- [ ] **Spec merges first.** No implementation PR opens before this
      spec is merged.
- [ ] **Modifier-key reply targets correct session.** Fire a kickoff
      that ends in `blocked` (e.g. *"ask me a question"*). Without
      releasing the previous notification, press ⌃⇧⌥Space, speak
      the answer, release. Overlay shows *"↳ replying to <name>"*.
      The session unblocks (state → `working`) and ultimately
      reaches `done`. The transcript is NOT routed into a new
      session.
- [ ] **No live session → modifier press shows error.** With no live
      sessions, press ⌃⇧⌥Space. Overlay shows *"No live session to
      reply to"* and (per non-goal) falls through to a new kickoff.
- [ ] **Notification "Voice reply" action works.** Same blocked-session
      setup. Click the notification's *"Voice reply"* action. App
      focuses, recording starts in reply mode; speaking + releasing
      injects the transcript into that specific session.
- [ ] **Notification action with stale session shows error.** Stop
      the session via `claude stop <id>`. Click the still-visible
      *"Voice reply"* action on the prior notification. Overlay
      shows *"Session <id> has ended"*; transcript on clipboard.
- [ ] **Response window voice-reply button.** Open a blocked
      session's response window. Click *"Voice reply"*. Same
      injection path as the notification action.
- [ ] **State coordination.** State.json transitions on reply are
      observed by the existing StateFileWatcher; new terminal
      transitions fire fresh notifications.
- [ ] **Dictation hotkey untouched.** Pressing the dictation hotkey
      (default ⌃Space) still pastes at cursor; no kickoff or reply
      path triggered.
- [ ] **Privacy contract preserved.** Voice-reply uses the same
      network hop already consented to at kickoff time; no new
      consent prompt; recording overlay shows the network indicator.
- [ ] **Tests** — `swift build && swift test` green; new test
      cases cover modifier-key dispatch logic, target-session
      auto-selection (blocked > working > none), and notification
      action routing.
- [ ] **No bench regression** — reply path runs after Whisper
      completes; transcription hot path untouched.

## References

- [SPEC-031](SPEC-031-agent-kickoff.md) — parent spec; the live
  daemon-managed sessions this spec extends
- [SPEC-006](SPEC-006-agent-dispatch.md) — long-game multi-turn
  closed-loop sessions; deliberately NOT subsumed
- [SPEC-003](SPEC-003-hotkey.md) — hotkey infrastructure; modifier
  introspection via `NSEvent.modifierFlags`
- [SPEC-004](SPEC-004-overlay.md) — recording overlay; mode chip
  surface
