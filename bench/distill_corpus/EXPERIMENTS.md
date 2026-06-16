# Polish-pass experiments log

> ⚠️ **STATUS: merged to `main`, not yet in a tagged release.**
>
> SPEC-007 in-process LLM polish landed on `main` via **PR #75**
> (2026-06-08, commit `07878e78`): an opt-in `LlamaCppPolishEngine`
> (in-process llama.cpp, **not** Ollama) that auto-downloads
> `gemma-4-E2B-it-Q4_K_M.gguf` and is gated behind a Settings toggle,
> off by default. The shipped scaffold is the experiment-3 candidate
> below (narrow formatting prompt + `<<<TRANSCRIPT>>>`).
>
> It is **not yet in a tagged release** — latest is `v2.0.0-alpha.19`
> (2026-06-03), which predates the merge — so by this doc's strict
> definition (main **and** tagged release **and** DMG), users on the
> current DMG still get regex-only `TextPolisher` until the next alpha
> cuts. The dated experiment rows below predate the merge and remain a
> research log, not current state.

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
- **"Best candidate so far"** for experiment 3 was the polish path with the highest pass-rate at the time. It is now what landed: PR #75 wired it into the app as the opt-in `LlamaCppPolishEngine` path.
- `main` now contains the full SPEC-007 feature (in-process llama.cpp engine, auto-download, Settings toggle) as of PR #75 — but it is **merged, not yet released**. No tagged DMG ships it yet, so end users are unaffected until the next alpha.

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

Current pipeline (on `main` via PR #75; opt-in, off by default):

```
audio → WhisperKit (transcribe) → LlamaCppPolishEngine (LLM polish) → TextPolisher (regex) → paste
                                  (optional, opt-in, in-process llama.cpp)
```

The LLM step is `LlamaCppPolishEngine` (embedded llama.cpp over the GGUF),
**not** Ollama — Ollama is only the bench harness, not the app runtime.

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

A separate research dive (completed 2026-05-04) documents the live-models
landscape — Moshi, Voxtral, Parakeet, WhisperKit, Qwen2.5-Omni / Qwen3-ASR,
Phi-4-Multimodal, Canary-Qwen, MiniCPM-o, GPT-4o Realtime, Gemini Flash Live,
plus the Chinese ecosystem (Doubao, Step-Audio 2, Hunyuan Voice, Tencent
Covo-Audio, Baichuan-Audio): see [`docs/research/live-speech-models.md`](../../docs/research/live-speech-models.md).

A companion methodology critique surveys 2024–2026 work on eval methodology,
synthetic-vs-real data, LoRA hyper-parameters, distillation, and quantization,
then critiques our pipeline: see [`docs/research/polish-methodology-critique.md`](../../docs/research/polish-methodology-critique.md).
The headline finding: off-policy distillation on synthetic-only data is the
exact failure mode in Thinking Machines' *On-Policy Distillation* (Oct 2025) —
three rounds of the same recipe was three rounds of the same bug.

A third doc, [`docs/research/realtime-voice-product-findings.md`](../../docs/research/realtime-voice-product-findings.md),
pulls engineering findings from the realtime-voice products (GPT-4o Realtime,
Gemini Live, Doubao Realtime Voice, Phi-4-MM, Apple SpeechAnalyzer / WhisperKit)
and adjacent research (NVIDIA NeMo, Mistral Voxtral, Kyutai Moshi, LiveKit,
Modal+Pipecat). Headline findings most relevant to OpenQuack: cascade beats
native S2S on reasoning by 26 points (Big Bench Audio); OpenAI's 8-section
realtime-prompt structure is directly liftable for our polish prompt;
Apple SpeechAnalyzer (macOS 26) is a real competitive threat — the polish
layer is the moat, not the ASR.

## Hypotheses queued for next experiments

Re-ranked 2026-05-04 after the methodology survey. The top three (E1, E2, E4)
gate everything else — they tell us whether the bench (not the model) is the
bottleneck. **Don't run distillation again until E1 + E2 confirm the model is
the real constraint.**

- **E1 (highest priority, ~1 day):** prompt-sensitivity + judge-noise probe — run the current bench × 5 prompt rephrasings × Haiku and Sonnet judges; report 95 % CIs and inter-judge κ. With 18 cases the CI is ±15pp; we cannot tell "good" from "lucky" yet.
- **E2 (~2 days):** capture 200 real transcripts → re-bench with idempotency (re-polish polished output and check it doesn't drift). Tells us whether the bench/real gap is corpus drift or model failure. Probably makes distillation moot.
- **E4 (~2 days):** QAT or DWQ-quantize the current 4.6 B teacher. MLX 4-bit DWQ ≈ 2.3 GB at ~BF16 parity per blog benchmarks; if it holds for our task the right "small model" is just a better-quantized teacher.
- **E3 (~1 week, only if E1+E2 say model is the bottleneck):** on-policy distillation 4.6 B → 4 B (skip 1.3 B until 4 B works — capacity matters per the lottery-ticket trend). Sample student trajectories → query teacher logprobs → reverse-KL loss, ~150–500 steps. The Thinking Machines recipe directly addresses our "drops information" failure.
- E5: **Improve eval dataset** — deepen each category, add real WhisperKit samples, add Claude-judge scoring. Subsumed by E1 + E2 above; tracked separately for the dataset deliverable.
- E6: TurboQuant DWQ — actual `mlx_lm.dwq` workflow (vs the standard 4-bit). Folded into E4.
- E7: Local capture mechanism in the app — review-mode toggle that logs (raw, your_pasted) pairs locally. Required for E2; this is the app-side prerequisite. Cost: 3–4 hours app work + weeks of accumulation.
- E8: Tier-1 rules in `TextPolisher.swift` — paragraph break rule, list-detection regex, question-mark rule. Replaces some LLM work with deterministic regex. Cost: 1–2 hours.
- E9: Hardware-tier gate — auto-detect 8 GB / 16 GB / 24 GB+ Macs and pick model accordingly. Currently the toggle is off-by-default at all tiers; should be smart. Cost: 1 hour.
- E10: Invocation gate — only call the LLM when input matches self-correction patterns OR exceeds N words; pass through clean short inputs. Reduces compute, reduces damage surface. Cost: 1 hour.
- E11: **Multimodal streaming model integration** — try Voxtral Realtime / Parakeet-TDT-0.6B-v3 on Mac and compare end-to-end latency + quality vs Whisper + polish. Per the live-models survey, Voxtral Realtime is closest single-model fit but **doesn't yet support system prompts** (only context biasing); Parakeet-TDT is a drop-in WhisperKit replacement that frees memory headroom for the polish LLM. Cost: 1–2 days.

## Reproducing the corpus run (research only)

```sh
# Pull the model (text-only Gemma 4 E2B at Q4_K_M via unsloth)
# See bench/distill_corpus/README.md for the Modelfile.

# Run the runtime test corpus
python3 bench/distill_corpus/test_runtime_prompt.py
# Expected: 18/18 passed, mean wall ~0.65s on M4 / 16 GB
```

This requires Ollama running with `gemma4-textonly:Q4_K_M` imported.

**Bench fidelity caveat.** The Ollama bench model and the app's downloaded
GGUF are byte-identical weights — same 3,106,736,256 bytes, same
sha256 `9378bc47…8672d`, both `google/gemma-4-E2B-it` Q4_K_M (unsloth
imatrix, **not** the QAT checkpoint; QAT ships as a separate `…-it-qat-GGUF`
in Q4_0). What differs is the **prompt framing**: the app's
`LlamaCppPolishEngine` uses the model's native `<|turn>` / `<turn|>` tokens,
while the Ollama Modelfile's `TEMPLATE` is written with `<start_of_turn>` /
`<end_of_turn>` (it also declares `RENDERER/PARSER gemma4`). So this bench
validates the weights + Ollama framing, not the app's exact llama.cpp
framing. A bench that drives `LlamaCppPolishEngine` directly is the
faithful follow-up.
