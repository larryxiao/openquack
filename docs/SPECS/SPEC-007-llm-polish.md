# SPEC-007 — LLM transcript polish

**Status:** draft (M2.5 — promoted as next-priority chunk after v0 launch)
**Owner:** `OpenQuackKit/Polish/` (extends the existing `TextPolisher`)
**Last updated:** 2026-04-27

## Goal

After Whisper produces a raw transcript, an optional **local LLM step**
cleans it up — fixes punctuation, removes verbal tics and false starts,
organises multi-idea utterances into bullets, normalises stop-word noise,
and preserves proper nouns / technical terms exactly. Stronger than the
regex-based [`TextPolisher`](SPEC-???); off by default; explicitly local.

The pipeline becomes:

```
audio → Whisper → raw transcript
                  │
                  ├── (optional) LLM polish ◀── this spec
                  │
                  └── Regex polish (TextPolisher)
                  │
                  paste at cursor
```

## Why this is M2.5 priority

User asked for it explicitly on 2026-04-27. The regex polish landed in
M2 catches the easy stuff (capitalisation, end-punctuation, fillers) but
real dictation often produces multi-clause runs that need restructuring,
which a 1–3 B local LLM can do in well under a second on Apple Silicon.
This is also the foundational LLM infra that SPEC-006 (agent dispatch)
will reuse, so doing polish first proves the local-LLM stack against a
narrower problem before agents land on top.

## Non-goals

- Cloud LLMs. The whole point is local-only.
- Translation (separate use case; cleanup must respect the input language).
- Agent-style action execution — that's SPEC-006.
- Polishing on by default. The compute / RAM / cold-start cost has to be
  opt-in until we ship a default model lighter than Whisper-medium itself.

## Public surface (sketch)

```swift
public protocol TextPolishEngine: AnyObject {
    static var engineName: String { get }
    var requiresNetwork: Bool { get }   // surfaced in the recording overlay
    var modelLabel: String { get }       // for status row

    /// Returns cleaned-up text. Should be idempotent on already-clean input.
    /// On any failure (network, OOM, model not loaded), throw — the caller
    /// falls back to the regex pipeline.
    func polish(_ raw: String, context: PolishContext) async throws -> String
}

public struct PolishContext: Sendable {
    public let language: String?      // engine hint, e.g. "en"
    public let foregroundApp: String? // best-effort, may be nil
    public let timestamp: Date
}

public enum PolishEngineKind: String, CaseIterable, Sendable {
    case off          // skip the LLM step entirely
    case ollama       // local Ollama HTTP
    case mlxLM        // in-process via mlx-swift-lm
}
```

## Engines (implementation order)

### 1. `OllamaPolishEngine` — fastest path to a working feature

- Local HTTP at `http://localhost:11434/api/chat` (configurable URL).
- Default model: `gemma3:1b` or `qwen2.5:3b-instruct` — small, fast,
  multilingual, low RAM. Final default settled by a SPEC-007 bench run
  per docs/BENCHMARKS.md.
- `keep_alive: -1` so the model stays in GPU memory across calls; we pay
  the cold-start once.
- `think: false` for thinking-capable models (Gemma 3, etc.) — voice
  cleanup doesn't need chain-of-thought, and thinking budget eats output
  tokens (we hit this in v0.1).
- Times out after 8 s of no first byte; raises so we fall back.
- `requiresNetwork = false` — loopback isn't network for the privacy
  indicator.

### 2. `MLXLMPolishEngine` — best privacy story

- In-process via [`mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm).
  No subprocess, no Ollama install required.
- Default model: `Qwen2.5-1.5B-Instruct-4bit` (~1 GB) or similar.
- Re-uses the `~/Library/Application Support/OpenQuack/MLX/` cache pattern
  we already use for Whisper.
- Streaming token output is *available* but we wait for the full polished
  text before paste — partial polished text is worse UX than the raw
  transcript.

### 3. `WhisperKitLLMPolishEngine` (later)

If argmax-oss-swift's text-models stack matures, mirror its API. Skip
for now.

## Prompt template (port from v0.1 `thinker.py`)

```
You reorganise raw voice transcriptions into clean, structured text.

You MUST:
- Respond in the SAME language as the input.
- Add correct punctuation (。，for Chinese; periods, commas for English; etc.).
- Remove filler words, verbal tics, false starts, and repetitions.
- Remove garbled or nonsensical text (transcription errors / artefacts).
- Organise multiple ideas into bullet points (use • or -).
- Keep it concise — shorter than the input.
- Preserve all technical terms, proper nouns, and names exactly as spoken.
- Output ONLY the reorganised text — no commentary, labels, or markdown fences.
```

Per-call options:
- `temperature: 0.3` for short input (≤ 50 words), `0.5` for longer.
- `num_predict: min(max(wordCount * 2, 80), 1024)`.
- `think: false` (Ollama) — prevents thinking-mode models eating budget.
- CJK character count via the same heuristic v0.1 used for the fast-path
  word-count check.

## Pipeline integration

In `AppDelegate.stopAndTranscribe`:

```swift
let raw = try await transcriber.transcribe(...)

let polished: String
if polishEngineKind != .off, let engine = polishEngine {
    do {
        polished = try await engine.polish(raw, context: ctx)
    } catch {
        // Fall back to regex-only polish.
        polished = TextPolisher.polish(raw)
    }
} else {
    polished = TextPolisher.polish(raw)
}

// Paste / clipboard ...
```

Order matters: LLM polish runs first (it produces better-structured
output), then regex polish handles any leftovers (trailing whitespace,
stray casing). If LLM is off, regex polish is the only step.

## Settings

New tab or section:

- **Settings → Polish**
  - "Use local LLM" picker: Off / Ollama / MLX-LM
  - When Ollama: URL field, model picker (lists available `ollama list` models)
  - When MLX-LM: model picker (we ship a curated list with download status)
  - "When polish fails" → fall back to regex only (default) | show error in popover
- **Settings → Privacy**
  - The polish engine's `requiresNetwork` is shown here; the `mlxLM` and
    `ollama` engines both report false (loopback / in-process), so the
    Privacy pane stays green.

## Quality gates

Bench-able. Add to `openquack-bench`:

- **Polish WER delta** — LibriSpeech raw vs polished output, against the
  reference. Polish should NOT make WER worse on already-correct text.
- **Polish latency** — wall-clock for a 50-word input. Target < 1 s on
  M-series 16 GB with the default 1.5–3 B model.
- **Polish RAM** — peak RSS during polish; combined with WhisperKit
  medium (200 MB), the total budget should fit comfortably on 8 GB Macs.

## Open questions

- **Default model** — settle once we benchmark gemma3:1b / qwen2.5:1.5b /
  qwen2.5:3b on representative dictation corpora. The v0.1 prototype
  used gemma4:e2b (7.7 GB) which is too heavy; aim for ≤ 2 GB.
- **Streaming** — should the polish step stream into the overlay? The
  raw transcript is already shown; streaming the polish on top is
  visually noisy. Lean: don't stream; show polish-in-progress spinner
  and reveal the final polished text on paste.
- **Approval gate** — for risky edits (long medical / legal dictations),
  should the user see a "polished version, approve?" popover before
  paste? Defer to a later spec; start with auto-paste and add a
  "preview before paste" Settings toggle if users ask.
- **Custom system prompts** — power users will want to tune the prompt
  per-app ("when in Slack, keep it casual; when in Pages, format as
  prose"). That's the App Branch concept from voxt; defer to M3+.

## References

- v0.1 `thinker.py` — concepts only; the Swift port is fresh code.
- The `think: False` lesson and CJK word-counting heuristic from v0.1
  must be ported, they're real bug fixes, not stylistic choices.
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) for the
  in-process engine.
- [Ollama API](https://github.com/ollama/ollama/blob/main/docs/api.md)
  for the HTTP engine.
