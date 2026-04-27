# SPEC-006 — Agent dispatch

**Status:** draft (M2 — the differentiating feature)
**Owner:** `OpenQuackKit/Agents/`
**Last updated:** 2026-04-26

## Goal

After the transcript lands, dispatch the user's voice command to a configured agent backend (Claude Code, Ollama, …) which performs the requested action and returns a result. **Voice → action.** This is OpenQuack's killer feature.

## Non-goals

- Building a new agent. We dispatch to existing ones.
- Cloud hosting, multi-tenant, RBAC.
- "Smart" intent classification at v2.0 — every utterance routes to the active agent unchanged.

## Public surface (proposed)

```swift
public protocol Agent: AnyObject {
    static var agentName: String { get }
    var requiresNetwork: Bool { get }            // surfaced in the overlay
    func dispatch(_ utterance: String, context: AgentContext) async throws -> AgentResult
}

public struct AgentContext: Sendable {
    public let foregroundApp: String?            // best-effort, may be nil
    public let workspaceDirectory: URL?          // configured per agent
    public let timestamp: Date
}

public enum AgentResult: Sendable {
    case text(String)                            // paste at cursor
    case sideEffect(summary: String)             // agent did something off-screen; show summary
    case failure(message: String)
}

public enum AgentKind: String, Sendable { case passthrough, claudeCode, ollama }

public actor AgentRouter {
    public init(active: AgentKind)
    public func setActive(_ kind: AgentKind)
    public func dispatch(_ utterance: String) async throws -> AgentResult
}
```

## Agents (in implementation order)

### 1. `PassthroughAgent` (default, no network)

```swift
public final class PassthroughAgent: Agent {
    public static let agentName = "passthrough"
    public let requiresNetwork = false
    public func dispatch(_ utterance: String, context: AgentContext) async throws -> AgentResult {
        return .text(utterance)
    }
}
```

This is OpenQuack-as-dictation. Default until the user picks an agent.

### 2. `ClaudeCodeAgent` (M2)

- Spawn `claude` (the user's Claude Code CLI) as a subprocess.
- Working directory: a configured `workspaceDirectory` from Settings.
- Pipe the utterance into stdin, parse stdout/stderr.
- Return `.sideEffect(summary: …)` when Claude Code reports actions; `.text(…)` when it just answers.
- Honour the user's existing `claude` config; don't read or store their API key.

```swift
public final class ClaudeCodeAgent: Agent {
    public static let agentName = "claude-code"
    public let requiresNetwork = true   // shown in overlay
    public init(workspace: URL, claudePath: URL = URL(fileURLWithPath: "/usr/local/bin/claude"))
    public func dispatch(_ utterance: String, context: AgentContext) async throws -> AgentResult { ... }
}
```

### 3. `OllamaAgent` (M3)

- Local Ollama HTTP API (`http://localhost:11434`).
- Configurable model (default: a sensible local one once we benchmark).
- `requiresNetwork = false` — we treat localhost loopback as not network for the privacy indicator.

### 4. `MLXLMAgent` (M3+)

- In-process via `mlx-swift-lm`.
- No subprocess overhead.
- Best privacy story for "fully local" agent.

## Privacy contract (binding)

1. Default active agent is `passthrough`. Fresh installs do NOT route to a network agent.
2. Switching to a network-using agent triggers a one-time consent prompt naming the destination ("This routes your transcripts to Anthropic via Claude Code. OK?"). Stored as a per-agent flag in Settings, revocable.
3. The recording overlay shows a network indicator any time the active agent has `requiresNetwork == true`.
4. `localhost` is treated as not-network for the indicator (Ollama, local servers).
5. The PR that introduces a new agent must state in the description whether it satisfies these rules.

## Open questions (must resolve before implementation lands)

- **Trigger phrasing.** Always-route once an agent is configured, or require a `claude, …` prefix? Recommend: always-route, with a "manual confirm before send" mode for high-risk agents.
- **Side-effect summary UX.** Where do we show "PR #1234 opened" — overlay only, or persistent history pane? Lean overlay-only at v2.0; history pane is opt-in privacy hazard.
- **Timeouts and crashes.** Agent failure UX — surface `.failure(message:)` in overlay with a copy-utterance-to-clipboard fallback so the user doesn't lose work.
- **Config surface.** Settings → Agent tab needs at minimum: active agent picker, workspace dir picker (Claude Code), Ollama URL/model picker, network-consent reset.

## References

- Anthropic's Claude Code CLI docs (whatever's current at implementation time).
- v0.1's `thinker.py` had the LLM-call pattern; concepts only, not code.
- `Sources/OpenQuackKit/` will gain `Agents/` once this spec ratifies.
