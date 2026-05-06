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

## Atomic PR breakdown

To stay within `AGENTS.md` "atomic PRs," ship M2.5 as the following ordered
PRs. Each is small enough to review in 10 minutes and reverse cleanly.

| # | Title | Branch | Effort | Depends on | Files |
|---|---|---|---|---|---|
| 1 | `TextPolishEngine` protocol + types | `feat/spec-007-protocol` | S | — | `Sources/OpenQuackKit/Polish/PolishEngine.swift` (new), `Tests/OpenQuackKitTests/PolishEngineTests.swift` (new) |
| 2 | `OllamaPolishEngine` impl | `feat/spec-007-ollama-engine` | S | #1 | `Sources/OpenQuackKit/Polish/OllamaPolishEngine.swift` (new), tests with `URLProtocol` mock |
| 3 | Pipeline integration in `AppState` (off by default) | `feat/spec-007-app-integration` | S | #2 | `Sources/OpenQuackApp/AppState.swift` (edit), UserDefaults flag, fall-back to regex on `throws` |
| 4 | Settings → Polish pane (Off / Ollama only; MLX-LM disabled) | `feat/spec-007-settings-ui` | S | #3 | `Sources/OpenQuackApp/SettingsView.swift` (edit), engine picker, model field, URL field, "test connection" button |
| 5 | `MLXLMPolishEngine` impl | `feat/spec-007-mlx-engine` | M | #4 | `Package.swift` (add `mlx-swift-lm` dep), `Sources/OpenQuackKit/Polish/MLXLMPolishEngine.swift` (new), tests, enable MLX-LM in Settings picker |
| 6 | `openquack-polish-bench` wires both engines + reports | `feat/spec-007-bench-integration` | S | #5 | `Sources/OpenQuackPolishBench/PolishBenchRunner.swift` (edit) |
| 7 | Domain-term + send-confidence corpus seed | `feat/spec-007-corpus-seed` | S | #6 | `bench/polish_corpus/cases.jsonl` (new), `docs/BENCHMARKS-polish.md` (update) |

PRs ship in order. PR 1 has no behaviour change — it's protocol-only — so
it lands as soon as it builds and tests pass. Each subsequent PR is
non-breaking (the polish step stays opt-in with `.off` as the default
`PolishEngineKind`) until PR 4 ships the user-facing toggle.

A future PR set covers `WhisperKitLLMPolishEngine` if argmax-oss-swift's
text-models stack matures; that's not in M2.5.

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

Bench-able. A new SPM target `openquack-polish-bench` drives engine ×
model × corpus → `bench/out/polish/<host-tag>/`. WER is **not** the right
metric — polish intentionally rewrites — so we measure across three
dimensions plus latency and RAM.

### Three quality dimensions (scored separately, not averaged)

1. **Transcription error correction** — does the model fix homophone /
   proper-noun errors common in Whisper output?
   *Examples:* "cloud code" → "Claude Code", "income tax" → "in-context",
   "Gemma three" → "Gemma 3". Scored via `must_contain` /
   `must_not_contain` substring checks against the corpus case.
2. **Rephrase, organise, format** — fillers stripped, false starts
   removed, multi-idea runs split into bullets, sentence-end punctuation,
   length not bloated. Scored via auto micro-metrics:
   - filler-token removal rate (`um|uh|like|you know|...` regex pre/post)
   - punctuation completeness (% sentences ending in `.!?` / `。！？`)
   - length ratio (output / input — should be ≤ 1.0 per the prompt)
   - idempotency on already-clean input (polish(clean) ≈ clean; edit
     distance ≤ 5%).
3. **In-context rewrite** — same `raw`, different `app_context` slot
   (Slack / Mail / VS Code / Pages) → distinct, context-appropriate
   outputs. Detail: see SPEC-008.

### LLM-as-judge (final ranking signal)

Auto micro-metrics screen out broken outputs but don't discriminate
between models that all strip fillers correctly. The ranking signal is a
judge LLM that scores each candidate output 1–5 against the multi-
reference list, conditioned on the dimension being scored.

- **Primary judge:** `claude-haiku-4-5-20251001` (cheap, fast).
- **Adversarial / hard cases + gold-reference generation:**
  `claude-sonnet-4-6`.
- **Tiebreak only:** `claude-opus-4-7`.

This is bench-only — judge calls happen on the developer's machine when
producing a report, never in the runtime hot path. The privacy contract
covers what ships in the app, not what generates the README table.

### Latency / memory pressure

The optimisation target is **headroom**, not fit. A model that *just*
fits at idle will thrash under real user load (Whisper warm, polish
warm, browser + Slack open) and the cost shows up as P95/P99 latency
spikes — the user feels stutter even when the mean is fine.

- **Polish latency** — TTFT, mean, P95, P99 for a 50-word input. Target
  < 1 s mean and < 2 s P95 on M-series 16 GB with the chosen default
  model. Cold (just-loaded) and warm-and-held are reported separately.
- **Memory pressure (not just RSS).** Per call, sample:
  - `vm_stat` deltas: pages-compressed, pageins, pageouts.
  - System-wide free + wired pages via `host_statistics64(HOST_VM_INFO64)`.
  - macOS memory-pressure level (`memorystatus` API).
  RSS alone undercounts CoreML / Metal / ANE working sets — it's kept
  for continuity but is not the primary metric.
- **Coexistence test.** Hold WhisperKit medium + polish model warm,
  idle 60 s with a synthetic background allocation (~2 GB) to simulate
  a user's other apps, *then* measure polish latency on a fresh
  utterance. That's the latency users actually experience.

### Recommendation hierarchy

Smaller-that-clears-quality > faster > more accurate. If the smallest
candidate flunks only one quality dimension (e.g. category-1 proper-
noun correction) and is otherwise good, prefer it + an out-of-band
fallback (regex / domain-term dictionary) over scaling up the model.

### Corpus shape

`bench/polish_corpus/cases.jsonl` — one case per line:

```json
{
  "id": "en_trans_001",
  "category": "transcription_errors",
  "language": "en",
  "raw": "we should use cloud code to open a PR for this branch",
  "app_context": null,
  "references": [
    "Use Claude Code to open a PR for this branch.",
    "We should use Claude Code to open a PR for this branch."
  ],
  "must_contain": ["Claude Code"],
  "must_not_contain": ["cloud code"],
  "notes": "Whisper hears 'Claude' as 'cloud'"
}
```

Target ~80 cases at first launch:

| Bucket | Count | Notes |
|---|---:|---|
| `transcription_errors` (en) | 20 | Real Whisper mishearings, proper nouns |
| `rephrase_organize` (en) | 20 | Fillers, false starts, multi-clause runs |
| `in_context` paired sets | 30 | 10 raws × 3 contexts = 30 (SPEC-008) |
| Multilingual (zh/ja/es/fr/de) | 10 | 2 per language across both en buckets |

Cases drawn from: actual WhisperKit-medium output on the existing 177-clip
corpus (`bench/out/M4-16GB/report.csv`) where the polish step has work
to do, plus hand-crafted cases for failure modes Whisper doesn't reach.

## Open questions

- **Default model** — settle once we benchmark the candidate set on the
  three-dimension corpus above. Candidates: `gemma3:1b`, `gemma3:4b-it-qat`,
  `qwen2.5:1.5b-instruct`, `qwen2.5:3b-instruct`, `llama3.2:1b`,
  `llama3.2:3b`. The v0.1 incumbent `gemma3n:e2b` (~5.6 GB; aliased
  `gemma4:e2b` in v0.1's config) is included as a reference data point
  even though it busts the ≤ 2 GB cap.
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
