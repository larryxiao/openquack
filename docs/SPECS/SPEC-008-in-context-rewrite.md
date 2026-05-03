# SPEC-008 — In-context transcript rewrite

**Status:** draft (M3 candidate; benched alongside SPEC-007 in M2.5)
**Owner:** `OpenQuackKit/Polish/` (extends `TextPolishEngine` from SPEC-007)
**Last updated:** 2026-04-29

## Goal

Augment the LLM polish step with **active-app context** so the polished
transcript reads correctly for where it's about to be pasted. The same
spoken sentence should produce a Slack-shaped DM in Slack, prose in
Pages, and code/comment style in VS Code, **and** domain terms should
resolve correctly given the context (e.g. "income tax" — heard by
Whisper from "in-context" — gets corrected when the foreground app is
VS Code).

This is the M3 row from `docs/ROADMAP.md`:

> Active-app context: feed the foreground app + focused input field's
> surrounding text into Whisper's prompt bias and the polish/agent
> prompt, so domain terms resolve correctly and the agent has the same
> context the user does.

## Why now (benched in M2.5, shipped in M3)

Picking the SPEC-007 default model without testing in-context behaviour
risks shipping a model that polishes well in isolation but ignores
context when given it. We bench in-context cases now so the model
recommendation considers all three dimensions (see SPEC-007 §Quality
gates). Implementation lands in M3 once SPEC-007 has shipped its base
polish UI.

## Non-goals

- Reading the focused input field's surrounding text on macOS — that's
  a privacy-sensitive Accessibility-API call and gets its own design
  pass. Phase 1 uses **only the foreground app name and bundle ID**.
- Per-app *custom* system prompts (the App Branch concept from voxt).
  Out of scope; defer to M3+.
- Agent context (SPEC-006) — that's a separate pipeline.

## Public surface

Extend `PolishContext` from SPEC-007:

```swift
public struct PolishContext: Sendable {
    public let language: String?
    public let foregroundApp: AppContext?  // nil if user disabled in Settings
    public let timestamp: Date
}

public struct AppContext: Sendable {
    public let bundleID: String         // e.g. "com.tinyspeck.slackmacgap"
    public let displayName: String      // "Slack"
    public let category: AppCategory    // coarse bucket — see below
}

public enum AppCategory: String, Sendable {
    case chat        // Slack, Discord, iMessage, Teams
    case email       // Mail, Outlook, Spark
    case code        // VS Code, Xcode, JetBrains, Cursor
    case docs        // Pages, Word, Google Docs (Safari/Chrome)
    case terminal    // Terminal, iTerm, Warp
    case browser     // generic
    case other
}
```

The category is what the prompt actually consumes; the bundle ID is
kept for telemetry and future per-app tuning.

## Prompt augmentation

Append a single **context line** before the user message:

```
[Context: writing in {category} ({displayName})]
{raw_transcript}
```

Per-category nudges baked into the system prompt:

- `chat` — keep it short, casual, no full bullets unless the user
  clearly listed several items.
- `email` — formal sentences, no bullets unless requested, end with
  proper punctuation.
- `code` — preserve identifiers, don't add prose; if input is clearly a
  code comment, format as one line.
- `docs` — paragraph form, prefer prose over bullets.
- `terminal` — single-line command-shaped output if input is a command;
  otherwise prose. Do not invent flags.
- `browser` / `other` — fall back to base SPEC-007 behaviour.

These nudges are appended to the SPEC-007 system prompt, not a
replacement.

## Bench (paired references)

In `bench/polish_corpus/cases.jsonl`, in-context cases use the
`in_context` category and group N raws × M contexts:

```json
{"id": "ctx_001_chat", "category": "in_context", "language": "en",
 "raw": "ok so I'm thinking we drop the model and pick one of the smaller ones",
 "app_context": "chat",
 "references": ["thinking we drop the current model and pick a smaller one"],
 "must_contain": [], "must_not_contain": []}

{"id": "ctx_001_email", "category": "in_context", "language": "en",
 "raw": "ok so I'm thinking we drop the model and pick one of the smaller ones",
 "app_context": "email",
 "references": ["I'm thinking we should drop the current model and pick a smaller one."],
 "must_contain": [], "must_not_contain": ["ok so"]}

{"id": "ctx_001_code", "category": "in_context", "language": "en",
 "raw": "ok so I'm thinking we drop the model and pick one of the smaller ones",
 "app_context": "code",
 "references": ["// drop the current model and pick a smaller one",
                "Drop the current model and pick a smaller one."],
 "must_contain": [], "must_not_contain": ["ok so"]}
```

Initial set: 10 raws × 3 contexts = 30 paired cases. The judge prompt
sees the `app_context` slot and scores whether the output fits.

## Settings (M3 implementation, not M2.5)

- **Settings → Polish → Use active-app context** toggle, default OFF.
  When ON, OpenQuack reads only the foreground app name (no window
  titles or focused field contents) and feeds the category to the
  prompt. The Privacy pane lists exactly what's read.
- The toggle is independent from "Use local LLM" — turning context on
  with `engine = off` is a no-op.

## Open questions

- **Browser → infer category from URL?** A user dictating into a Gmail
  tab is in `email`, not `browser`. Phase 1 says no (that needs
  AX/tab-URL access). Revisit after shipping.
- **Window title.** Same privacy concern as focused field; deferred.
- **Per-app system-prompt overrides.** Defer to a SPEC-008 follow-up.

## References

- SPEC-007 — base polish pipeline this extends.
- v0.1 `context.py` — gathered foreground app via `osascript`; the Swift
  port should use `NSWorkspace.shared.frontmostApplication` instead.
- `docs/ROADMAP.md` M3 row 3.
