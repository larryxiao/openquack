# Polish methodology critique — what the literature says about our approach

**Status:** research note (not a SPEC, not a commitment)
**Date:** 2026-05-04
**Scope:** survey 2024–2026 small-LLM fine-tuning + inference-compression
research (eval methodology, synthetic vs real data, LoRA, distillation,
quantization), then critique OpenQuack's polish pipeline against it.

> This document exists to answer: *"Are we doing the OpenQuack polish work
> in a way the literature would endorse, or are we missing something
> obvious?"*
>
> Short answer: the **methodology** has identifiable problems that the
> literature has solutions for. The **decision to park distillation in
> favour of off-the-shelf 4.6B + tight prompt** is consistent with the
> literature.

## TL;DR

What the literature says we got right:

1. Three quality dimensions (information preservation, fluency, faithfulness)
   match Anthropic's groundedness/coverage/style decomposition.
2. Pivoting to better prompt + bigger teacher when distillation rated 3/10
   matches "start with prompt engineering, fine-tune only when persistent
   skill is needed."
3. Bench-first methodology aligns with the measure-first principle.
4. Memory-headroom-over-fit is consistent with the literature.

What the literature says we got wrong:

1. **Off-policy distillation on synthetic-only data.** The exact failure mode
   in [Thinking Machines, *On-Policy Distillation*, Oct 2025](https://thinkingmachines.ai/blog/on-policy-distillation/):
   the student never sees its own error distribution, so it can't recover.
   Three rounds of the same off-policy recipe is three rounds of the same bug.
2. **Single-teacher synthetic.** Gemma 4 → Gemma 3 with no diversity
   injection. Multi-teacher (Gemma 4 + Sonnet + Haiku) would have much higher
   diversity per [*Synthetic Eggs in Many Baskets* (2025)](https://arxiv.org/html/2511.01490v1).
3. **No production distribution in training data.** Pure synthetic =
   guaranteed distribution shift at inference.
4. **No information-preservation rubric in training loss.** We measured it
   in the bench but didn't penalise it during training.
5. **18-case eval with no CIs / no inter-judge agreement / no idempotency
   tests.** 18/18 has wide CIs; we cannot statistically distinguish "great"
   from "lucky."
6. **Likely no prompt-loss masking ablation.** Per [Huerta-Enochian & Ko,
   2024](https://arxiv.org/html/2401.13586v2/), short-completion data needs
   PLW tuning; default settings probably hurt.
7. **r/alpha/target-modules likely defaults.** Polish is a multi-skill
   transformation; r=8–16 with q/v only is probably under-parameterised.
8. **1.3B Gemma 3 may be capacity-limited.** Most successful narrow
   distillations use ≥3B students.

## 1. Evaluation methodology

**LLM-as-judge biases (well-documented, 2024–2025).** Position bias is the
dominant artefact: swapping order in pairwise judging shifts accuracy >10pp,
judge-model choice matters more than task complexity ([Shi et al.,
*Judging the Judges*](https://aclanthology.org/2025.ijcnlp-long.18/)).
Verbosity bias is real — judges prefer longer/more formal outputs even when
worse. Self-enhancement bias (judges favour their own family) and
reference-answer bias also documented ([LLM-Judge-Bias](https://llm-judge-bias.github.io/)).
Agreement with humans on expert tasks runs only 60–68 %; on extractive QA
it reaches r=0.85 ([Galileo](https://galileo.ai/blog/llm-as-a-judge-vs-human-evaluation)).

**Implications for our 18/18 (and the earlier 48/54) score.** A single
pass-rate without 95 % CIs is statistically thin. For p≈0.89 and ±5pp margin
~150 samples are needed; we have 18. Our 95 % CI is roughly ±15pp
([Wolfe, *Stats for LLM Evals*](https://cameronrwolfe.substack.com/p/stats-llm-evals)).
A single judge model with no inter-judge agreement also under-detects bias.

**Anthropic's own guidance** ([Building Evals
cookbook](https://github.com/anthropics/anthropic-cookbook/blob/main/misc/building_evals.ipynb),
[Demystifying Evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)):
use multiple grader types (code-based, rubric-LLM, human spot-check); calibrate
judge prompt against expert labels; binary correct/incorrect tends to
outperform 1–10 scales; combine groundedness + coverage + style as separate
axes (our three dimensions match this — that part is correct).

**Composite scoring shape.** Three dimensions × case-level is fine, but 1–10
Likert from an LLM judge is noisier than binary per-rubric-item or pairwise;
the literature pushes toward decomposed binary checks ([Anthropic eval
docs](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests)).

**Real-use vs bench gap.** The literature attributes this primarily to (a)
corpus drift from the real input distribution, (b) judge-calibration drift,
(c) prompt/template tied to bench format. Our "dropped useful info"
complaint is exactly what synthetic-corpus benches miss when they don't
measure information preservation explicitly.

## 2. Synthetic vs real-distribution data

**Model collapse / mode narrowing is the canonical failure mode.** Iterative
training on model outputs causes "narrowing of the output distribution" with
long unlikely-token tails ([Shumailov et al., 2024](https://arxiv.org/html/2404.05090v1)).
Recent (2025) [*Synthetic Eggs in Many Baskets*](https://arxiv.org/html/2511.01490v1)
shows diversity of synthetic sources is the load-bearing variable —
multi-teacher synthetic > single-teacher synthetic by a wide margin.

**The exact failure we saw.** "Model dropped useful information" after
distilling 4.6B → 1.3B on (raw, polished) pairs is the textbook signature:
low-diversity synthetic data overfits its own assumptions, so the student
learns "shorten/clean" as a transformation rather than "preserve content
while polishing." This matches "over-specialisation to synthetic data
patterns" ([AI Competence](https://aicompetence.org/avoiding-model-collapse-in-synthetic-data-training/)).

**Recommended fix in the literature.** Accumulate, don't replace: real
production data alongside synthetic. Cursor-style flywheels treat user
interactions as the primary training signal ([ZenML LLMOps cases](https://www.zenml.io/blog/llmops-in-production-457-case-studies-of-what-actually-works)).
LIMA-style finding: ~1000 high-quality real examples often beats large
synthetic sets ([LIMA, Zhou et al.](https://arxiv.org/abs/2305.11206)).

## 3. LoRA / fine-tuning best practices

**Hyperparameters that actually matter.**

- **Rank**: r=16–32 is the 2026 instruction-tuning default; r=4–8 only for
  classification; r=64+ for code/reasoning ([Brenndoerfer
  guide](https://mbrenndoerfer.com/writing/lora-hyperparameters-rank-alpha-target-modules),
  [Unsloth docs](https://unsloth.ai/docs/get-started/fine-tuning-llms-guide/lora-hyperparameters-guide)).
- **Alpha**: 2×rank is Microsoft's default; alpha = rank is more
  conservative.
- **Target modules**: q_proj, k_proj, v_proj, o_proj minimum; including MLP
  (gate, up, down) usually helps for narrow style tasks.
- **Learning rate**: ~1e-4 to 3e-4 typical.

**Prompt-loss masking.** [Huerta-Enochian & Ko, 2024](https://arxiv.org/html/2401.13586v2/)
is the primary source: it matters a lot for short-completion data (PLW
~0.15–0.24 optimal, swings 20pp), and is irrelevant for long completions
(Rg ≥ 1). Our raw → polished is short-ish completion, so prompt masking
choice matters and probably wasn't tuned.

**LoRA "learns less and forgets less."** [Biderman et al.,
2024](https://arxiv.org/html/2405.09673v2): LoRA acts as a regulariser;
useful when you want to preserve base behaviour, *bad* when you need to
teach a new domain. Polish is closer to "teach a transformation" than "shift
tone slightly" — LoRA may be structurally undersized for it.

**DoRA** ([Liu et al., NVIDIA](https://developer.nvidia.com/blog/introducing-dora-a-high-performing-alternative-to-lora-for-fine-tuning/)):
consistently beats LoRA at half the rank; weight-decomposed mag/dir update
is more expressive. Worth trying if we revisit fine-tuning.

## 4. Distillation in 2024–2026

**The single most relevant piece of evidence for our situation:** [Thinking
Machines, *On-Policy Distillation* (Oct 2025)](https://thinkingmachines.ai/blog/on-policy-distillation/).
Off-policy distillation (our approach: SFT on teacher (raw, polished) pairs)
fails because *"if the student makes an early mistake that the teacher never
makes, it finds itself diverging ever farther from the states it observed in
training."* They achieved 70 % AIME'24 in ~150 steps via on-policy
distillation — 9–30× cheaper than the SFT baseline that we just paid for.

**Recipe.** Sample student trajectories → query teacher logprobs →
minimise per-token reverse-KL. This directly addresses the "drops information"
failure: the student gets corrective signal on its own mistake distribution,
not just on clean teacher outputs.

**Other distillation findings.**

- Sequence-level KD with rationales beats token-level for narrow tasks
  ([Knowledge Distillation Survey 2024](https://arxiv.org/html/2402.13116v3)).
- Smoothed soft labels reduce hallucination ([Mu et al., 2025](https://arxiv.org/html/2502.11306v1)).
- Multi-teacher (Gemma 4 + Sonnet + Haiku) often wins via diversity
  ([*Synthetic Eggs*](https://arxiv.org/html/2511.01490v1)).

**Why 1.3B may be structurally too small.** [Lottery-ticket-style
findings](https://arxiv.org/abs/2504.14772): narrow-task distillation
succeeds when student capacity ≥ task complexity. Polish requires
content-preservation + grammar + register — three orthogonal skills. 1.3B is
plausible but on the edge; most successful narrow distillations cited use
3B+ students.

## 5. Quantization

**Apple Silicon stack as of 2026** ([4bit Quant
Showdown](https://blog.labs.purplemaia.org/4bit-quant-showdown-finding-the-sweet-spot-for-qwen3-models/),
[TurboQuant on MLX](https://medium.com/@antonrozanov/turboquant-on-mlx-4-6x-kv-cache-compression-with-custom-metal-kernels-9cdee3f7d2a2)):

- **MLX 4-bit DWQ** beats both standard MLX-4bit and MXFP4-MLX on perplexity
  at the same size.
- **Q4_K_M (llama.cpp)** is the GGUF go-to; ~5pp drop on HumanEval vs BF16,
  ~identical on BFCL.
- **TurboQuant** primarily targets KV-cache compression (4.6× compression
  with custom Metal kernels), not weights.
- **MXFP4** is OpenAI's open-weights format; fine but not best on Apple.

**Gemma 3 QAT** ([Google, 2025](https://developers.googleblog.com/en/gemma-3-quantized-aware-trained-state-of-the-art-ai-to-consumer-gpus/)):
the 12B Q4_0 QAT model gets 67.07 MMLU vs 67.15 BF16 — essentially free. If a
Gemma 4 QAT 4.6B exists or we can produce one, this is strict-improvement
over PTQ.

**BitNet 1.58.** [b1.58 2B4T (Apr 2025)](https://arxiv.org/html/2504.12285v1)
matches FP16 at 2B but Microsoft explicitly says "not recommended for
commercial/real-world applications without further testing." Speculative for
production.

**4× memory at parity** holds for QAT 4-bit, mostly holds for DWQ / Q4_K_M,
breaks for naive Q4 on instruction-tuned models, and falls apart below
4-bit except for QAT and BitNet.

## Synthesis: critique

### A. What we did right

1. Three quality dimensions (information preservation, fluency, faithfulness)
   match Anthropic's groundedness/coverage/style decomposition.
2. Pivoting to better prompt + bigger teacher when distillation rated 3/10 —
   correct decision; matches "start with prompt engineering, fine-tune only
   when a persistent skill is needed" ([progression in fine-tuning
   literature](https://sysdebug.com/posts/fine-tuning-rag-prompt-engineering/)).
3. Bench-first methodology aligns with measure-first.
4. Memory-headroom intuition is consistent with the literature.

### B. What we did wrong methodologically (specific)

1. **Off-policy distillation on synthetic-only data** — exact failure mode
   in Thinking Machines' *On-Policy Distillation*. Three rounds of the
   same recipe is three rounds of the same bug.
2. **Single-teacher synthetic.** No diversity injection.
3. **No production distribution in training data.** Pure synthetic =
   guaranteed distribution shift.
4. **No information-preservation rubric in the training loss** itself.
5. **18-case eval with no CIs / no inter-judge agreement / no idempotency
   tests.** Too noisy to declare wins.
6. **Likely no prompt-loss masking ablation.** Default settings probably
   hurt.
7. **r/alpha/target-modules likely defaults.** Probably under-parameterised
   for a multi-skill transformation.
8. **1.3B Gemma 3 may be capacity-limited.** Most successful narrow
   distillations use ≥3B students.

### C. What the literature says we should have done

1. **On-policy distillation** ([Thinking Machines
   recipe](https://thinkingmachines.ai/blog/on-policy-distillation/)): student
   samples → teacher logprobs → reverse-KL loss. ~150 steps.
2. **Mix synthetic with real captures.** Even 100–300 production transcripts
   (LIMA-scale) re-weighted heavily.
3. **Multi-teacher synthetic.** Gemma 4 + Sonnet + Haiku polish for diversity.
4. **DoRA at r=32** instead of LoRA at low rank, all linear modules.
5. **QAT-then-quantize** rather than fine-tune-then-PTQ — Gemma 3 QAT pattern
   preserves 4-bit quality.
6. **Eval set: 150–300 cases, three difficulty strata, idempotency probes
   (re-polish polished output), CIs reported.**
7. **Two judges (Haiku + Sonnet)** with κ agreement reported; rotate position
   to neutralise position bias.

### D. Concrete next experiments, ranked by expected info gain

**E1. Test prompt-sensitivity of current 4.6B path (1 day, very high info
gain).** Hypothesis: 18/18 is within noise; 5 prompt variants will span
±15pp. If so, we don't yet know if the prompt is good or lucky.

*Action.* Run current bench × 5 prompt rephrasings × Haiku and Sonnet judges;
report 95 % CIs and inter-judge κ. Stop here if variance is high — fix the
eval before any model work.

**E2. Capture 200 real transcripts → re-bench with idempotency (2 days, very
high info gain).** Hypothesis: bench/real gap is corpus drift, not model
failure. If 4.6B scores well on real captures with idempotency probes,
distillation isn't needed at all.

*Action.* Log 200 real polish requests, run current pipeline, judge with
Haiku rubric + spot-check.

**E3. On-policy distillation (Thinking Machines recipe) 4.6B → 4B (or 3B)
(1 week, high info gain).** Hypothesis: the failure was the recipe, not the
task. Predict 4B student reaches 90 %+ of teacher quality on real corpus.

*Action.* Sample student trajectories, query Gemma 4 logprobs, reverse-KL
loss, ~150–500 steps. **Skip 1.3B target until 4B works** — capacity matters.

**E4. QAT or DWQ-quantize the current 4.6B teacher (2 days, medium info
gain).** Hypothesis: the right "small model" is a well-quantized teacher.
MLX 4-bit DWQ of 4.6B is ~2.3 GB and matches BF16 within 1–2 % on most
tasks.

*Action.* DWQ-quantize, re-bench. If parity, ship — distillation may be
unnecessary.

**E5. Multimodal speech-model probe (3 days, speculative info gain).**
Hypothesis: an audio → polished-text model removes the polish stage entirely,
possibly fixing information loss. *Speculative* — most current speech-LLMs
are weaker than ASR + polish on long-form fluency, but the gap is closing
fast (Gemini Live, Voxtral). See [`live-speech-models.md`](./live-speech-models.md).

*Action.* Benchmark 1–2 candidates against the corpus before investing.
Lower priority than E1–E4.

**Rank: E1 → E2 → E4 → E3 → E5.** E1 and E2 cost days, gate everything else,
and may make distillation moot. Don't run E3 until E1+E2 confirm the model
(not the eval or corpus) is the bottleneck.

### E. Speculative caveats

- Audio-LLM superiority for polish is a directional bet, not established —
  verify on our corpus first.
- The 1.3B "structurally too small" claim is informed by trend, not a single
  decisive paper.
- DWQ vs Q4_K_M comparison is from blog benchmarks (Purple Maia,
  Antonrozanov); peer-reviewed numbers lag.

## Primary sources

- [On-Policy Distillation (Thinking Machines, 2025)](https://thinkingmachines.ai/blog/on-policy-distillation/)
- [Judging the Judges: Position Bias (ACL 2025)](https://aclanthology.org/2025.ijcnlp-long.18/)
- [LoRA Learns Less and Forgets Less (Biderman et al., 2024)](https://arxiv.org/html/2405.09673v2)
- [Instruction Fine-Tuning: Does Prompt Loss Matter? (Huerta-Enochian & Ko, 2024)](https://arxiv.org/html/2401.13586v2/)
- [DoRA: Weight-Decomposed Low-Rank Adaptation](https://arxiv.org/pdf/2402.09353)
- [Synthetic Eggs in Many Baskets (2025)](https://arxiv.org/html/2511.01490v1)
- [Statistical Analysis of Language Model Collapse](https://arxiv.org/html/2404.05090v1)
- [BitNet b1.58 2B4T Technical Report](https://arxiv.org/html/2504.12285v1)
- [Gemma 3 QAT Models (Google, 2025)](https://developers.googleblog.com/en/gemma-3-quantized-aware-trained-state-of-the-art-ai-to-consumer-gpus/)
- [Anthropic: Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
- [Anthropic Cookbook: Building Evals](https://github.com/anthropics/anthropic-cookbook/blob/main/misc/building_evals.ipynb)
- [Knowledge Distillation Survey for LLMs (Xu et al., 2024)](https://arxiv.org/html/2402.13116v3)
- [Smoothed Knowledge Distillation for Hallucination (2025)](https://arxiv.org/html/2502.11306v1)
- [4bit Quant Showdown (Qwen3)](https://blog.labs.purplemaia.org/4bit-quant-showdown-finding-the-sweet-spot-for-qwen3-models/)
- [TurboQuant on MLX](https://medium.com/@antonrozanov/turboquant-on-mlx-4-6x-kv-cache-compression-with-custom-metal-kernels-9cdee3f7d2a2)
- [LIMA: Less Is More for Alignment (Zhou et al., 2023)](https://arxiv.org/abs/2305.11206)
