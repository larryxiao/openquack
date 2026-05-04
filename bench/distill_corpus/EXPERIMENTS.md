# Polish-pass experiments log

> ⚠️ **STATUS: Research-only. Nothing in this log is shipped to users.**
>
> The polish feature (LLM rewrite of Whisper output) is **under
> investigation**, not in any released build. Every model decision
> recorded below was either rejected outright or is parked pending
> further work. The current shipping behavior of OpenQuack is
> regex-only `TextPolisher` (in `Sources/OpenQuackKit/Polish/`); no
> LLM model is downloaded by users, no Settings toggle exposes the
> feature, no released build runs Ollama.
>
> The actual app-side wiring lives on the un-pushed
> `feat/intelligent-rewrite` branch and is not on `main`.

One row per experiment. Adopted from karpathy/autoresearch's discipline:
each experiment changes ONE thing against the same baseline, gets one
primary metric, gets a yes/no decision.

**Primary metric:** pass-rate on `runtime_cases.jsonl` (currently 18 cases).
Run with `python3 bench/distill_corpus/test_runtime_prompt.py`.

**Secondary metrics:** mean wall, P95 wall, resident memory.

| # | Date | Hypothesis | Change | Pass-rate | Mean wall | Decision (status only — nothing released) |
|---|---|---|---|---|---|---|
| 1 | 2026-05-03 | LoRA-distilled 1B (Opus teacher, 351 pairs) is the right Standard-tier model | Train openquack-polish:v3 from gemma-3-1b-it base via LoRA | n/a (pre-test) — real-use rated 3/10 | 0.74s | **rejected**: model drops information on real use; bench score didn't predict reality |
| 2 | 2026-05-03 | gemma3:1b base (no LoRA) can do formatting-only with the right prompt | Test stock gemma3:1b with tight formatting prompt | 0/11 (massive hallucination — base 1B treats inputs as chat) | ~3s | **rejected**: 1B base cannot do this task without fine-tuning |
| 3 | 2026-05-03 | The 4.6B teacher (gemma4-textonly:Q4_K_M) does formatting cleanly with a narrow prompt — no fine-tuning needed | Swap (in WIP branch only) OllamaPolishEngine default → gemma4-textonly:Q4_K_M; new formatting-only prompt; `<<<TRANSCRIPT>>>` scaffold | **18/18** on the canonical corpus | 0.65s | **best candidate so far, NOT shipped**: stays on `feat/intelligent-rewrite` for further validation; current shipping behavior is regex-only |
| 4 | 2026-05-03 | mlx-community 4-bit MLX variant ("TurboQuant") would shrink resident vs Ollama Q4_K_M | Pull mlx-community/gemma-4-e2b-it-4bit; bench via mlx-vlm | quality matched Ollama, resident essentially the same (~3.6 GB on disk vs Ollama's 3.1 GB) | 0.69s median | **deferred**: actual TurboQuant (DWQ) might shrink further; not chased now |

## What "shipped" / "not shipped" mean here

- **"Shipped" anywhere in this doc means** "merged to `main` AND included in a tagged release AND distributed to users via the cask/DMG."
- **"Best candidate so far"** for experiment 3 means the polish path with the highest pass-rate to date — but it lives only on the WIP branch and has had ~30 minutes of real-use testing total. **Not validated for release.**
- The current `main` tip (819b605) contains research artifacts only — no model download, no Settings UI, no behavior change for users.

## Patterns we now know to be wrong

- **"Remove fillers" in the prompt** — Whisper already strips fillers. Telling the LLM to remove them primes it to find them in inputs that have none, and remove content instead.
- **"Keep it concise — shorter than the input"** — direct instruction to drop information. The single most damaging line in the v1/v2 prompt.
- **"Organise multiple ideas into bullet points" without qualifier** — encourages bullets on prose where prose is correct.
- **Distilling 4.6B → 1.3B before nailing the dataset** — the v1/v2/v3 LoRA models were trained on synthetic pairs that taught aggressive concision. The student inherited the wrong behavior. Distillation only makes sense after we have real captured (raw, what-you-actually-wanted) pairs from real use.
- **Bench scores can lie about real use** — composite 3.18 felt like a 3/10 in real use because the bench corpus didn't exercise the long-tail patterns where the model damaged content.

## Evaluation dataset — quality / coverage gaps to address before scaling

The current `runtime_cases.jsonl` is **18 cases across 14 categories** —
which means several categories have only a single case. Before we
generate more synthetic data or run more model experiments, the
dataset itself needs attention. Specific gaps:

### Coverage gaps

- **Categories with only 1 case** are statistically meaningless. Each
  category should have **at least 3 cases** of varying difficulty
  (easy / typical / adversarial) before we consider it tested.
  Currently thin: `very_short`, `informal_chat`, `name_that_could_be_request`,
  `code_identifiers`, `technical_jargon`, all multilingual buckets.
- **No real Whisper output samples.** Every case in the corpus is
  hand-written. Real WhisperKit output (with its actual
  capitalization, punctuation, and rare mishearings) doesn't appear.
  The training distribution doesn't match production.
- **No long-form audio samples.** Multi-minute dictations with
  natural paragraph structure are absent. Polish on a 30-second
  monologue is qualitatively different from polish on a 5-second
  utterance, but the corpus doesn't distinguish.
- **No streaming intermediate samples.** If we eventually add
  streaming transcription (SPEC-012 territory), polish needs to
  handle partial transcripts. Not in corpus.
- **No mixed-language switching.** Bilingual users dictate
  code-switched ("the build is failing 但是 still passing on staging").
  Not represented.
- **Self-correction depth is shallow.** All current self-correction
  cases are single-step ("X — actually Y"). Real dictation has
  multi-step ("X — wait no — I mean Y — actually let's go with Z").

### Quality gaps in scoring

- **Heuristic scoring is too tolerant** in some places. The current
  `score()` accepts capitalization changes silently — but if a model
  capitalizes proper nouns inconsistently, that's a real defect we'd
  want to catch.
- **Heuristic scoring is too strict** in others. Whether bullets-vs-line-
  breaks is "the same" depends on the user's preference; encoding
  one as canonical loses real signal.
- **No human-judge layer**. SPEC-007's design called for Claude /
  Haiku as a judge; we've been doing this manually. Need a
  reproducible script.

### Decision — improve before scaling

Before generating ~600 more cases (the previous "5x" target) or running
another distillation round, the right move is:

1. **Deepen each existing category to 3-5 cases** with explicit
   easy / typical / adversarial labels. Target ~50 cases total.
2. **Add 5-10 real WhisperKit output samples** by recording 1-2 minutes
   of dictation locally and using the actual transcript as the
   `raw` field. Hand-write the `expected` field. This is the
   highest-signal addition and the only one that captures real
   distribution shift.
3. **Add a Claude-judge scoring path** that complements the heuristic
   scorer — use the existing `bench/judge.py` harness pattern.
4. **Defer multi-step self-correction and streaming-partial cases**
   until after a v4 pass on the basics; they're worth their own
   experiment slots.

## Pipeline / model collaboration thinking

Current pipeline (under investigation, not shipped):

```
audio → WhisperKit (transcribe) → TextPolisher (regex) → paste
                                                         ↑
                          (optional, opt-in, not shipped)
                          ↓
                          OllamaPolishEngine (LLM polish)
                          ↓
                          back into TextPolisher
```

This is a **two-model pipeline** — Whisper for ASR, an LLM for
formatting. The handoff is text-only; the LLM doesn't see audio.

**Alternative being researched:** a single multimodal speech model
(audio-in, text-out, streaming, system-prompt-conditioned) replacing
both Whisper *and* the polish step. Potentially:

- One model, less RAM
- Streaming output (text appears as the user speaks)
- System prompt could condition transcription style (e.g., "format
  lists as bullets", "use this glossary for proper nouns")
- No two-stage error: the polish model can't damage what Whisper
  produced because there's no separate polish model

Trade-offs to investigate:
- These models are larger than Whisper-medium (1.5 GB) — typical
  multimodal speech LLMs are 3-7 B params
- ASR accuracy may not match Whisper-medium (Whisper has been
  optimized hard for raw transcription quality)
- Most are not yet open-weight or not yet on-device-friendly
- Ecosystem is moving fast — what's right today may be dated in
  6 months

A separate research dive (in progress as of 2026-05-04) is documenting
the live-models landscape: Moshi, Voxtral, Parakeet, Gemini Live,
GPT-4o Realtime, Qwen2-Audio, etc. Output will land at
`docs/research/live-speech-models.md`.

## Hypotheses queued for next experiments

- E5: **Improve eval dataset (this section's "Decision" above)** — deepen each category, add real WhisperKit samples, add Claude-judge scoring. **Highest priority — every other experiment needs this first.**
- E6: TurboQuant DWQ — actual `mlx_lm.dwq` workflow (vs the standard 4-bit). Might give the "4× memory" reduction the docs claim. Cost: ~1 hour.
- E7: Local capture mechanism in the app — review-mode toggle that logs (raw, your_pasted) pairs locally. Once we have ~100 real pairs, retrain v4 from real data. Cost: 3-4 hours app work + weeks of accumulation.
- E8: Tier-1 rules in `TextPolisher.swift` — paragraph break rule, list-detection regex, question-mark rule. Replaces some LLM work with deterministic regex. Cost: 1-2 hours.
- E9: Hardware-tier gate — auto-detect 8 GB / 16 GB / 24 GB+ Macs and pick model accordingly. Currently the toggle is off-by-default at all tiers; should be smart. Cost: 1 hour.
- E10: Invocation gate — only call the LLM when input matches self-correction patterns OR exceeds N words; pass through clean short inputs. Reduces compute, reduces damage surface. Cost: 1 hour.
- E11: **Multimodal streaming model integration** — try Voxtral / Moshi / Parakeet on Mac and compare end-to-end latency + quality vs Whisper + polish. Cost: 1-2 days.

## Reproducing the corpus run (research only)

```sh
# Pull the model (text-only Gemma 4 E2B at Q4_K_M via unsloth)
# See bench/distill_corpus/README.md for the Modelfile.

# Run the runtime test corpus
python3 bench/distill_corpus/test_runtime_prompt.py
# Expected: 18/18 passed, mean wall ~0.65s on M4 / 16 GB
```

This requires Ollama running with `gemma4-textonly:Q4_K_M` imported.
End users will not have this set up; they get the regex-only polish
path that already ships in OpenQuack today.
