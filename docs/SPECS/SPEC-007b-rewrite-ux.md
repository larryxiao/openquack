# SPEC-007b — Intelligent rewrite UX

**Status:** draft (M2.5 — companion to SPEC-007 polish engine)
**Owner:** `OpenQuackApp/SettingsView.swift` + `OpenQuackApp/RecordingOverlay.swift`
**Last updated:** 2026-05-03

## Goal

Define the user-facing experience for the optional LLM polish step
(SPEC-007 + SPEC-007a + SPEC-016). The pipeline now works at acceptable
quality on a stock 4.6B Gemma 4 model with a tight formatting prompt;
the remaining work is making it discoverable, controllable, and trust-
worthy from the user's perspective.

## What the user actually wants (from real-use feedback)

1. **Predictable behavior.** "I dictated X, I want X back, just better
   formatted." The current toggle says "Polish with local LLM
   (experimental)" — too vague. User can't tell what will happen.
2. **No surprises on important text.** When polishing a casual Slack
   message, mistakes are cheap. When polishing a 5-paragraph memo or a
   paragraph being added to a customer email, mistakes are expensive.
3. **Visibility into what the model changed.** If the polish modified
   the text, the user wants to know what was changed before pasting —
   especially for high-stakes inputs.
4. **Easy escape hatch.** When the polish is wrong, retrieve the raw
   transcript instantly without re-recording.
5. **No memory pressure.** The polish model + Whisper running together
   shouldn't slow the rest of the user's apps.

## Three-tier toggle structure (replaces the single boolean)

The current `llmPolishEnabled` boolean is too coarse. Replace with a
4-level picker:

| Setting | What runs | Latency add | Best for |
|---|---|---|---|
| **Off** | Regex `TextPolisher` only (current SPEC-007 baseline) | 0 ms | Default; users who want exact Whisper output |
| **Light** | Regex polish + LLM only on inputs that match a specific pattern (long, multi-sentence, list-shaped) | 0–700 ms (most cases skip LLM entirely) | The recommended default once Light mode is shipped |
| **Standard** | Regex polish + LLM on every dictation | 500–900 ms | Users who want consistent formatting on every dictation |
| **Preview** | Same as Standard, but show raw vs polished side-by-side; user picks which to paste | 500–900 ms + user decision | High-stakes work; also the data-capture mode (SPEC-007c future) |

Default: **Off** at v0.2.0 ship; recommend Light once the gating logic
lands. Preview becomes opt-in for users who want the safety net.

## The Settings → Polish pane

```
┌── Polish ─────────────────────────────────────────────────┐
│                                                            │
│  Mode:  ○ Off   ◉ Light (recommended)   ○ Standard   ○ Preview │
│                                                            │
│  Light mode applies LLM polish only when the input would    │
│  benefit (long text, lists, multi-sentence). Short inputs   │
│  paste immediately without going through the LLM.           │
│                                                            │
│  Model:  [gemma4-textonly:Q4_K_M           ▾]               │
│          • ~3 GB resident, ~0.7 s polish on M-series        │
│          • Required: Ollama running with this model         │
│          • Status: ✓ available                              │
│                                                            │
│  ✓ Show "polish applied" indicator in overlay              │
│                                                            │
│  When polish fails:                                         │
│  ◉ Paste raw text silently (recommended)                    │
│  ○ Show error notification                                  │
│  ○ Cancel paste, copy raw to clipboard                      │
│                                                            │
│  ─────────────────────────────────────────────────────      │
│  Advanced                                                   │
│                                                            │
│  Custom system prompt:  [Edit...]                           │
│  Trigger threshold (Light mode):  [Auto ▾]                  │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## Recording overlay — feedback during polish

Today the overlay disappears at "Pasted." The polish step (700ms or so)
is invisible. Add a brief "Polishing…" intermediate state:

```
[●●● Recording 3.4s]
        ↓ (user releases hotkey)
[Transcribing 0.8s]    ← already present
        ↓
[Polishing 0.7s]       ← NEW — shows when LLM polish runs
        ↓
[Pasted ✓]             ← already present
```

Sub-1-second states should still flash visibly so the user understands
what's happening. The "Polishing" state never appears in Off mode and
appears only when the LLM is actually invoked (in Light mode).

## Preview mode — the data-capture variant

In Preview mode, after Whisper + polish complete, instead of pasting,
show a small comparison overlay:

```
┌── Polish preview ──────────────────────────────────────────┐
│                                                            │
│  Raw:                                                       │
│  the build is failing on CI again because of the test      │
│  that flakes                                                │
│                                                            │
│  Polished:                                                  │
│  The build is failing on CI again because of the test      │
│  that flakes.                                               │
│                                                            │
│  [⌘1 Use polished]  [⌘2 Use raw]  [⌘3 Edit & paste]       │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

Whichever the user picks gets logged locally as a (raw, chosen, polished)
triple in `~/Library/Application Support/OpenQuack/polish-pairs.jsonl`.
Stays on the user's machine — never leaves. After ~100-200 real triples
accumulate, that becomes the v4 training data: real preferences > our
synthetic guesses.

(This is SPEC-007c material — separate spec when we're ready to ship.)

## Hardware-tier auto-default

Per SPEC-007a's tier matrix, the default mode should depend on RAM:

| Detected RAM | Default mode | Rationale |
|---|---|---|
| 8 GB | Off (toggle to Light if user opts in) | 3 GB Gemma 4 + 1.5 GB Whisper + macOS overhead = pressure-warning; users should opt in only after seeing the resident impact |
| 16 GB | Light | Comfortable headroom; "polish only when useful" matches expected behavior |
| 24 GB+ | Standard | Memory headroom is generous; users can always step down |

The Settings → Polish pane should display the detected tier and explain
the recommendation. Override is always available.

## Failure UX

The polish step has three failure modes:

1. **Ollama unreachable** (daemon not running, network glitch on
   loopback, model not loaded). Most common.
2. **Timeout** (12s default).
3. **Model returned empty / decoding failed.**

Current behavior: silent fall-through to regex-only paste (good — paste
must never block). Improvement: log to system log + accumulate counts
for the Settings pane so users can see if polish is failing often:

```
Polish status:  ✓ available (last failure: never in last 100 calls)
                ⚠ frequent failures (38 of last 100 calls failed) [Diagnose…]
                ✗ unavailable (Ollama not running) [Open Ollama docs]
```

The "Diagnose…" button surfaces:
- Whether Ollama is running (`curl localhost:11434/api/tags`)
- Whether the configured model is in the list
- Latency over the last N calls
- Memory pressure during polish

## Security / privacy considerations

The LLM polish runs over loopback HTTP to a local Ollama daemon. The
existing privacy contract (nothing leaves the device) holds, but be
explicit about it in the Settings pane:

> *Polish runs entirely on your Mac via a local Ollama daemon at
> http://localhost:11434. The model never sends your transcript over
> the network. You can verify with Little Snitch or by reading
> `Sources/OpenQuackKit/Polish/OllamaPolishEngine.swift`.*

## What this spec defers

- **The capture mechanism** (Preview-mode logging) — needs its own SPEC-007c
- **Custom prompt UI** — listed as "Advanced" but the editor itself is M3
- **Per-app polish profiles** — different polish behavior for Slack vs
  Mail vs code editor; defer to SPEC-008 / SPEC-009
- **Streaming polish output** to the overlay — currently not worth the
  complexity; the polish completes in ~0.7s, full-output reveal is fine

## Acceptance criteria (M2.5 ship gate)

- [ ] `llmPolishMode` UserDefault replaces `llmPolishEnabled` boolean
- [ ] Settings → Polish pane renders the 4-mode picker + model picker
- [ ] Recording overlay shows "Polishing…" state when LLM runs
- [ ] Hardware-tier auto-detect picks the recommended default at first launch
- [ ] Polish-failure mode is configurable (silent / notify / cancel)
- [ ] Status line shows availability + recent failure count
- [ ] Preview mode is implemented but ships hidden behind a flag (M3+)
- [ ] All canonical 18 cases in `bench/distill_corpus/runtime_cases.jsonl`
      pass with the shipped default model + prompt

## References

- [SPEC-007](SPEC-007-llm-polish.md) — parent polish-engine spec
- [SPEC-007a](SPEC-007a-gemma-bench.md) — model / quant selection
- [SPEC-016](SPEC-016-distilled-polish-model.md) — distillation experiments
  (currently on hold pending real captured pairs)
- [bench/distill_corpus/EXPERIMENTS.md](../../bench/distill_corpus/EXPERIMENTS.md) — running experiment log
- [bench/distill_corpus/runtime_cases.jsonl](../../bench/distill_corpus/runtime_cases.jsonl) — canonical test corpus
