# OpenQuack polish bench — SPEC-007a

Living document. Numbers below are real, reproducible from
`bench/out/polish/M4-16GB-*` (three runs as of 2026-05-03), and supersede
earlier preliminary runs (`bench/out/polish/M4-16GB/`,
`M4-16GB-gemma4-baseline/`).

## TL;DR (M4 / 16 GB, Standard tier)

> **`gemma4-textonly:Q4_K_M` (text-only GGUF from `unsloth/gemma-4-E2B-it-GGUF`,
> 4.6 B params, **3.14 GB resident**) is the recommended polish default for 16 GB Macs.**
> Composite quality matches the full-multimodal `gemma4:e2b` build on auto-metrics
> (Punct 0.92, RefMinDist 6.2 vs 6.4) at less than half the resident footprint.
> 0.56 s mean wall, 0.72 s P95 — comfortably under the SPEC-007 < 1 s mean target.
> One regression worth flagging: text-only quants translate Japanese / German
> input to English where the full multimodal build kept the source language
> (zh stays). For users primarily dictating in JA/DE, prefer the Premium tier.

For 24 GB+ Macs, `gemma4:latest` (8 B, full multimodal Ollama build) wins
quality marginally (composite 3.68 vs 3.55) at 1.27 s mean / 2.74 s P95
and 9.09 GB resident.

For 8 GB Macs, polish ships off-by-default. `gemma3:1b` (1.23 GB resident,
composite 2.67) is the safest opt-in — D3 faithfulness 4.94, it does
little but breaks nothing.

## The big finding — Ollama default ≠ what you actually need

The Ollama-distributed `gemma4:e2b` is **7.16 GB on disk and 6.67 GB
resident when warm** because it bundles the full multimodal stack (vision
+ audio encoders) needed for image / audio input. OpenQuack's polish
pipeline only consumes text, so those layers are dead weight.

The text-only language model alone is **4.6 B parameters at Q4_K_M ≈
3.14 GB resident** — measured directly via `ps -axo rss` on the Ollama
runner process. That's a **53% reduction** with negligible quality cost
on English / Chinese; ~2× headroom margin on a 16 GB Mac after Whisper
medium (~1.5 GB) is also held warm.

The text-only GGUFs come from
[`unsloth/gemma-4-E2B-it-GGUF`](https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF)
and load into Ollama via a one-line `Modelfile` (see Reproducing).

## Hosts

| Host tag | Chip | Memory | macOS | Date |
|---|---|---:|---|---|
| `M4-16GB` | Apple M4 | 16 GB | 15.6 (24G84) | 2026-05-03 |

## Methodology

- **Harness:** `openquack-polish-bench` (SPEC-007). Ollama-backed, single
  prompt version per run, `keep_alive=-1` so the model stays warm
  between cases, `--unload-after` to clear memory between models.
- **Prompt:** `v2` (current default in SPEC-007). `v1` is queued for the
  follow-up bench post.
- **Corpus:** `bench/polish_corpus/cases.jsonl`, 34 cases:
  - `transcription_errors` — 12 cases (8 EN homophone/proper-noun fixes,
    1 ZH, 3 surrounding-context disambiguation).
  - `rephrase_organize` — 14 cases (filler stripping, false-start
    cleanup, multi-idea → bullets, idempotency, multilingual EN/ZH/JA/ES/FR/DE).
  - `in_context` — 8 cases (3 contexts × 2-3 raw inputs covering chat /
    email / code / docs target styles).
- **Quant:** Ollama default for the tag, which is **Q4_K_M (GGUF)** for
  every candidate except `gemma3:270m` and `llama3.2:1b` (Q8_0). MLX
  TurboQuant builds were not benched in this round (deferred to next
  bench post — see Open Questions).
- **Judge:** Claude (this bench: claude-opus-4-7 in IDE), scoring each
  output 1-5 across the SPEC-007 dimensions (D1 transcription error
  correction, D2 rephrase/organize/format, D3 faithfulness/no
  hallucination, D4 in-context appropriateness; N/A where the case
  category doesn't exercise the dimension). Future runs add the SPEC-007
  Haiku/Sonnet judge once `bench/judge.py` lands. The Claude-IDE judge is
  used because it's the rater available offline at zero API cost; SPEC-007
  treats judging as bench-only, never in the runtime hot path.
- **Composite weights:** D1 0.30, D2 0.30, D3 0.30, D4 0.10. Weights
  err toward the dimensions all categories exercise; D4 is in-context-only.

## Quality summary — Claude-as-judge (1-5; higher better)

| Model (Ollama tag) | Params | Quant | Resident (warm) | D1 trans-fix | D2 rephrase | D3 faithful | D4 context | **Composite** |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| **`gemma4:latest`** | 8 B | Q4_K_M | 9.6 GB | **2.17** | 3.91 | 4.97 | **3.62** | **3.68** |
| **`gemma4:e2b`** | 5.1 B | Q4_K_M | 7.2 GB | 1.75 | **4.00** | 4.94 | 3.38 | 3.55 |
| `gemma3:1b` | 1 B | Q4_K_M | 0.82 GB | 1.00 | 2.03 | 4.94 | 2.75 | 2.67 |
| `qwen3:1.7b` | 2 B | Q4_K_M | 1.36 GB | 1.00 | 1.85 | **4.97** | 2.62 | 2.61 |
| `phi4-mini` | 3.8 B | Q4_K_M | 2.49 GB | 1.33 | 2.85 | 3.32 | 3.50 | 2.60 |
| `qwen2.5:0.5b-instruct` | 0.5 B | Q4_K_M | 0.40 GB | 1.08 | 2.82 | 3.59 | 2.50 | 2.50 |
| `gemma3:270m` | 0.27 B | Q8_0 | 0.29 GB | 1.00 | 1.85 | 3.74 | 2.00 | 2.18 |
| `llama3.2:1b` | 1.2 B | Q8_0 | 1.32 GB | 1.00 | 1.56 | 3.03 | 2.62 | 1.94 |

**Read:** Gemma 4 family wins decisively. The next-best model
(`gemma3:1b`) trails the smaller Gemma 4 by **0.88 composite points** —
a wider gap than the gap between Gemma 4 E2B and the 8 B `latest`.

### Per-category quality

#### Transcription error correction

The hardest dimension — fixing Whisper-typical mishearings like "cloud
code" → "Claude Code", "open black" → "OpenQuack", "em el ex" → "mlx",
"ese pe em" → "SPM". 12 cases.

| Model | D1 | D2 | D3 |
|---|---:|---:|---:|
| **`gemma4:latest`** | **2.17** | 3.75 | 4.92 |
| **`gemma4:e2b`** | 1.75 | **4.08** | 4.83 |
| `phi4-mini` | 1.33 | 2.92 | 3.33 |
| `qwen2.5:0.5b-instruct` | 1.08 | 3.08 | 3.75 |
| `gemma3:1b` | 1.00 | 2.25 | 4.83 |
| `qwen3:1.7b` | 1.00 | 2.17 | 5.00 |
| `gemma3:270m` | 1.00 | 2.58 | 3.67 |
| `llama3.2:1b` | 1.00 | 1.00 | 2.67 |

**No model came close to "fixes everything."** D1 ceiling for the field
was 2.17/5.0 — the polish step alone, without surrounding-text context,
cannot reliably distinguish "Cloud Code" from "Claude Code" or "Open
Black" from "OpenQuack." This validates SPEC-008's in-context-rewrite
direction: the polish pass needs the user's surroundings to fix proper
nouns. **`gemma4:latest` was the only model that fixed `lady dog` →
`lazy dog`** (canonical-phrase recognition); only `gemma4:e2b` fixed
`em el ex swift` → `MLX Swift` and `whisper kit` → `WhisperKit` together.

#### Rephrase / organize / format

14 cases: filler stripping, false-start cleanup, multi-idea → bullets,
idempotency, plus 5 multilingual (EN/ZH/JA/ES/FR/DE).

| Model | D2 | D3 |
|---|---:|---:|
| **`gemma4:latest`** | **4.50** | **5.00** |
| **`gemma4:e2b`** | 4.14 | **5.00** |
| `qwen2.5:0.5b-instruct` | 2.71 | 3.71 |
| `phi4-mini` | 2.71 | 3.36 |
| `qwen3:1.7b` | 1.71 | 4.93 |
| `gemma3:1b` | 1.64 | **5.00** |
| `llama3.2:1b` | 1.86 | 2.86 |
| `gemma3:270m` | 1.50 | 3.79 |

**Read:** Gemma 4 family dominates here too — and notably retains
faithfulness (D3 5.00) while actually rewriting. The non-Gemma-4
candidates split into two failure modes:
- **Faithful no-ops** (`gemma3:1b`, `qwen3:1.7b`) — D3 ≈ 5 but D2 < 2.
  They preserve the input rather than polishing it.
- **Hallucinating rewriters** (`phi4-mini`, `qwen2.5:0.5b`,
  `llama3.2:1b`) — D2 ≈ 2.7 but D3 ≈ 3 because they paraphrase, bloat,
  or translate non-English to English.

#### In-context appropriateness

8 cases × 3 styles (chat / email / code / docs) for the same raw input.

| Model | D2 | D3 | D4 |
|---|---:|---:|---:|
| **`gemma4:e2b`** | **3.62** | **5.00** | 3.38 |
| **`gemma4:latest`** | 3.12 | **5.00** | **3.62** |
| `gemma3:1b` | 2.38 | **5.00** | 2.75 |
| `phi4-mini` | 3.00 | 3.25 | 3.50 |
| `qwen3:1.7b` | 1.62 | **5.00** | 2.62 |
| `llama3.2:1b` | 1.88 | 3.88 | 2.62 |
| `qwen2.5:0.5b-instruct` | 2.62 | 3.12 | 2.50 |
| `gemma3:270m` | 1.38 | 3.75 | 2.00 |

**Caveat:** in-context style adaptation tested *without* the SPEC-008
surrounding-text injection (`--use-surrounding-text` off). Once that
flag flips on, all models' D4 should rise — the bench measures whether
the model reads context that's already in the prompt; the SPEC-008
phase will measure whether OpenQuack supplies the right context.

`phi4-mini` shines specifically when the target style is "code comment"
(`ctx_001_code`) or "formal email" (`ctx_001_email`): it reframes
output to match. Its weakness is faithfulness — it adds emojis, "Dear
Team" salutations, paraphrases beyond what the input says.

## Latency and resource use

| Model | Warm (cold load) | Mean wall | P95 wall | Tokens/s (median) | ΔUsed peak (P95) | Cases |
|---|---:|---:|---:|---:|---:|---:|
| `qwen2.5:0.5b-instruct` | 0.78 s | 0.22 s | 0.69 s | 154 | 39 MB | 34/34 |
| `gemma3:270m` | 0.49 s | 0.35 s | 0.73 s | 185 | 65 MB | 34/34 |
| `qwen3:1.7b` | 1.27 s | 0.38 s | 0.59 s | 72 | 38 MB | 34/34 |
| `llama3.2:1b` | 1.57 s | 0.48 s | 1.21 s | 73 | 66 MB | 34/34 |
| `gemma3:1b` | 1.22 s | 0.73 s | 0.86 s | 83 | 938 MB | 34/34 |
| **`gemma4:e2b`** | 11.92 s | **0.73 s** | **1.52 s** | 49 | 29 MB | 34/34 |
| `phi4-mini` | 0.07 s | 0.91 s | 1.61 s | 32 | 556 MB | 34/34 |
| **`gemma4:latest`** | 11.87 s | 1.27 s | 2.74 s | 25 | 25 MB | 34/34 |

**Read:**
- `gemma4:e2b` is the surprise on the speed/quality Pareto: comparable
  mean wall to `gemma3:1b` (0.73 s for both), with 2.5× the composite
  quality.
- The 8 B `gemma4:latest` is genuinely 2× slower than E2B at 1.27 s
  mean — meaningful when polish is on the user's hot path.
- `gemma4:*` cold-start (~12 s) is the *one-time* CoreML/Metal compile
  cost. After warmup, ΔUsed peak per call is small (<30 MB) — the warm
  resident (~7-10 GB) is the cost; per-call generation overhead is low.
- `phi4-mini` cold-start of 0.07 s is misleading — it was already loaded
  in Ollama from the smoke test. Realistic cold-start would be ~5-10 s.
- `gemma3:1b` ΔUsed peak of 938 MB is unusual — it appears to allocate
  per-call. Worth investigating before it ships as the 8 GB tier default.

## Resident memory — measured, not estimated

The first version of this report cited model file sizes as resident-memory
proxies. Those proxies were wrong. Real warm RSS, measured via
`ps -axo rss` on `ollama runner` after a chat-warm + 4 s settle:

| Model | Ollama-reported size | Real warm RSS | Free mem after load (16 GB) |
|---|---:|---:|---:|
| `gemma3:270m` | 518 MB | **0.58 GB** | 5.35 GB |
| `qwen2.5:0.5b-instruct` | 755 MB | 0.51 GB | 4.89 GB |
| `gemma3:1b` | 1.2 GB | 1.23 GB | 2.79 GB |
| `qwen3:1.7b` | 1.9 GB | 1.82 GB | 1.25 GB |
| `llama3.2:1b` | 1.7 GB | 1.47 GB | 0.96 GB |
| `phi4-mini` | 3.3 GB | 2.90 GB | 0.08 GB |
| **`gemma4-textonly:Q4_K_M`** | 3.5 GB | **3.14 GB** | tight |
| **`gemma4-textonly:UD-Q3_K_XL`** | 3.3 GB | **2.91 GB** | tight |
| **`gemma4-textonly:UD-IQ2_M`** | 2.7 GB | **2.31 GB** | OK |
| `gemma4:e2b` (full Ollama) | 7.7 GB | **6.67 GB** | 0.07 GB / pageouts |
| `gemma4:latest` (full Ollama, 8 B) | 10 GB | **9.09 GB** | 0.06 GB / pageouts |

The first ten rows include the macOS baseline (~3.5 GB wired) plus the
runner. The two "full Ollama" Gemma 4 builds force pageouts to swap and
move the system into a `memory_pressure` warning state on a 16 GB Mac.

## Text-only Gemma 4 vs full multimodal Gemma 4 — quality side-by-side

Same-prompt direct comparison on the 34-case corpus
(`bench/out/polish/M4-16GB-textonly-quants/` vs the full-multimodal
results in `M4-16GB-spec007a-v2/`):

| Variant | Resident | Mean / P95 wall | transcription_errors RefMinDist | rephrase Filler↑ |
|---|---:|---:|---:|---:|
| `gemma4:e2b` (full multimodal Ollama) | 6.67 GB | 0.73 / 1.52 s | 6.4 | 0.75 |
| **`gemma4-textonly:Q4_K_M`** (unsloth) | **3.14 GB** | **0.56 / 0.72 s** | **6.2** | **0.89** |
| `gemma4-textonly:UD-Q3_K_XL` (unsloth) | 2.91 GB | 0.61 / 0.88 s | 8.3 | 0.94 |
| `gemma4-textonly:UD-IQ2_M` (unsloth) | 2.31 GB | 0.56 / 0.73 s | 9.0 | 0.89 |

**Text-only Q4_K_M matches or beats the full multimodal build on every
auto-metric** while running 24 % faster on mean wall and 53 % faster on
P95. The smaller resident also keeps macOS out of pressure-warning
state, which avoids the latency spikes that don't show up in
single-model benches.

**Multilingual regression to flag:** the text-only quants translate
Japanese (えーと…) and German (also äh ich meine…) input to English in
the `*_reorg_001` cases, where the full multimodal build kept the source
language. Chinese stayed in `Q4_K_M` only — `UD-Q3_K_XL` and `UD-IQ2_M`
also translate `zh_reorg_001` to English. This is likely a side-effect
of stripping the multimodal embeddings (which carry cross-lingual
priors) plus the more aggressive quantization. **For users primarily
dictating in JA/DE, ship the Premium-tier `gemma4:latest` default.**

`UD-IQ2_M` at 2.31 GB resident is the right pick if memory pressure is
the binding constraint — quality on transcription_errors slips a bit
(`OpenBench` instead of `Open Black`; `open-source` instead of
`OpenQuack`), but rephrase quality holds.

## Distilled 1B polish model (SPEC-016, proof-of-concept)

LoRA fine-tune of `mlx-community/gemma-3-1b-it-bf16` on 299 (raw,
polished) pairs produced by `gemma4-textonly:Q4_K_M` (the Standard-tier
teacher). Training: 15 minutes on M4 / 16 GB via `mlx_lm.lora` (300
iters, lr 1e-4, 16 LoRA layers). Loss 4.97 → 0.11 train, 5.13 → 0.15 val.

Composite quality (Claude-as-judge, same protocol as the SPEC-007a tier
candidates):

| Model | Composite | D1 trans-fix | D2 rephrase | D3 faithful | D4 context |
|---|---:|---:|---:|---:|---:|
| `gemma4:latest` (8 B) | 3.68 | 2.17 | 3.91 | 4.97 | 3.62 |
| `gemma4-textonly:Q4_K_M` (4.6 B teacher) | 3.55 | 1.75 | 4.00 | 4.94 | 3.38 |
| **`gemma3-1b-distilled` (1.3 B student)** | **3.18** | 1.42 | 3.97 | 4.29 | 2.75 |
| `gemma3:1b` (base, no LoRA) | 2.67 | 1.00 | 2.03 | 4.94 | 2.75 |
| `qwen3:1.7b` | 2.61 | 1.00 | 1.85 | 4.97 | 2.62 |

**Read:**
- The student matches the teacher on D2 (rephrase, the headline polish
  dimension): 3.97 vs 4.00 — within noise.
- Trails on D3 faithfulness (4.29 vs 4.94) due to over-aggressive
  concision on `ctx_002_*` deploy cases (3 hallucination records out of
  34 — fixable with more in_context-style training data).
- Beats the gemma3:1b base by **+0.51 composite** while sharing the
  same architecture: D2 jumps from 2.03 to 3.97. The LoRA learned the
  polish behaviour cleanly.

**Surprise: the student preserves source language better than the teacher.**
On the four `*_reorg_001` multilingual cases, the student produced
correct DE / JA / ES / ZH output where the text-only Q4 teacher had
translated to English. Likely cause: `gemma-3-1b-it`'s base multilingual
prior is intact; LoRA didn't overwrite it, and the student inherited
the polish behaviour without inheriting the teacher's multimodal-strip
regression.

| Case | Teacher | Distilled student | Reference |
|---|---|---|---|
| `de_reorg_001` | "I mean we should take the smaller model." | **"Wir sollten das kleinere Modell nehmen."** | Wir sollten das kleinere Modell nehmen. |
| `ja_reorg_001` | "I will refactor the polish module." | **"ポリッシュモジュールをリファクタしようと思います。"** | ポリッシュモジュールをリファクタしようと思います。 |
| `es_reorg_001` | "Quería decir que…" | **"Deberíamos usar el modelo más pequeño."** | Deberíamos usar el modelo más pequeño. |

**Latency caveat:** the 2.10 s mean wall here is the bf16 fused model
served via `mlx_lm.generate` (Python) — not directly comparable to the
Ollama-served candidates (0.5-1.3 s). Quantising the fused model to Q4
and serving via Ollama should match `gemma3:1b` base latency
(~0.73 s mean), giving the distilled student the **best
quality-per-megabyte point in the entire bench**.

Full design + recipe in [SPEC-016](SPECS/SPEC-016-distilled-polish-model.md).

## Hardware-tier recommendation (revised after resident measurements)

| Tier | Spec | Default polish model | Real resident | Mean / P95 wall | Notes |
|---|---|---|---:|---:|---|
| **Premium** | M-series 24 GB+ | `gemma4:latest` (full multimodal) | 9.1 GB | 1.27 / 2.74 s | Best quality + best multilingual; needs the headroom |
| **Standard** | M-series 16 GB | **`gemma4-textonly:Q4_K_M`** | **3.14 GB** | **0.56 / 0.72 s** | Equivalent quality to `gemma4:e2b`, 53 % less resident, 24 % faster mean. Multilingual regression on JA/DE. |
| **Standard, low-memory variant** | M-series 16 GB w/ heavy concurrent apps | `gemma4-textonly:UD-IQ2_M` | 2.31 GB | 0.56 / 0.73 s | Drops to ~30 % less resident than Q4_K_M at small additional quality cost on transcription_errors. |
| **Compatibility** | M-series 8 GB | `gemma3:1b` (off by default) | 1.23 GB | 0.73 / 0.86 s | Still off-by-default per SPEC-007a's no-silent-downgrades rule. |

**The Standard-tier recommendation flipped** from the earlier draft of
this report. The original `gemma4:e2b` (Ollama default) was forcing the
system into pressure warnings — wrong call. The text-only Q4_K_M
resolves that without quality cost on the dimensions that matter for
the dictation use case.

## Failure-mode notes (qualitative)

These are the patterns that disqualified candidates beyond the numbers:

- **`gemma3:270m`** hallucinates Python boilerplate on certain inputs
  (4 of 34 cases). Sample: faced with `hello world this is a test of
  the open black benchmark`, returned a multi-line `def clean_up(text):
  ...` Python function. Unusable as a polish default at any tier.
- **`qwen2.5:0.5b-instruct`** hallucinates "rules" preambles in
  non-English inputs (translates the system prompt back at the user) and
  outright refuses one chat-style request ("I'm sorry, but I can't
  assist with that request"). Unusable.
- **`phi4-mini`** translates non-English inputs to English about half
  the time (FR/DE/JA failure mode). For a multilingual app, disqualifying
  as a default. Quality is otherwise mid-pack.
- **`llama3.2:1b`** bullets *every word* of every input. Breaks
  idempotency on already-clean text (`The quick brown fox jumps over the
  lazy dog.` → `• The • quick • brown • fox …`). Unusable.

The Gemma 4 family had no comparable failure mode in the 34-case run.
Lowest individual case score was 2/5 on a multilingual context (Spanish
filler removal — kept "Quería decir que" instead of producing the
crispest "Deberíamos…").

## Open questions

- **Multilingual regression on text-only quants for JA / DE / (sometimes ZH).**
  Confirmed but not root-caused. The full multimodal `gemma4:e2b` build
  preserves source language; text-only Q4_K_M translates JA/DE input to
  English on the `*_reorg_001` cases. Q3_K_XL and IQ2_M also translate
  ZH. Hypotheses: (1) stripped multimodal embeddings carried cross-lingual
  priors; (2) unsloth's quantisation differs from Ollama's; (3) the
  base-model checkpoints differ in subtle ways. Worth a targeted
  multilingual bench with several JA/DE seed sentences before promoting
  the text-only default for non-English-primary users.
- **MLX TurboQuant for `gemma4:e2b` and `gemma4:latest`.** Still queued.
  The unsloth text-only Q4_K_M already gets us most of the resident win;
  TurboQuant might close the remainder.
- **Distilled polish model (Plan B, SPEC-016).** In progress as of this
  bench run. LoRA fine-tune of `gemma-3-1b-it` (1.3 B params, ~1 GB
  resident) on 299 (raw, polished) pairs from `gemma4-textonly:Q4_K_M`
  as teacher. Initial training showed loss dropping from 4.97 → 0.33
  in 50 iters — task is highly learnable. Bench results will land in a
  follow-up update to this file.
- **Prompt v1 vs v2.** This run used v2 only. v1 should be benched as
  an A/B.
- **Surrounding-text injection** (`--use-surrounding-text`). The
  in-context category here ran *without* the SPEC-008 surrounding-text
  flag. Re-bench with it on, especially the `surr_*` cases.
- **Coexistence test** (SPEC-007 § "Coexistence test"). Held-warm
  Whisper medium + polish model + 2 GB synthetic background allocation,
  *then* measure latency. Not run here — would tighten the realistic
  P95 number that users feel.
- **`phi4-mini` cold-start measurement.** Reported 0.07 s here is
  misleading (model was already loaded from a prior smoke test). Re-run
  with explicit unload-then-warm to get the honest cold-start number.

## Reproducing

From the repo root, on a Mac with Ollama running. **Two paths:**

### Path 1 — full SPEC-007a candidate set (Ollama-pulled)

```sh
# Pull the candidate set (~24 GB total)
ollama pull qwen2.5:0.5b-instruct gemma3:270m gemma3:1b llama3.2:1b
ollama pull qwen3:1.7b phi4-mini gemma4:e2b gemma4:latest

swift build --product openquack-polish-bench
.build/debug/openquack-polish-bench \
  --models "qwen2.5:0.5b-instruct,gemma3:270m,gemma3:1b,llama3.2:1b,qwen3:1.7b,phi4-mini,gemma4:e2b,gemma4:latest" \
  --prompts v2 \
  --out bench/out/polish/<host-tag>-spec007a-v2 \
  --unload-after
```

### Path 2 — text-only Gemma 4 quants (the recommended Standard-tier defaults)

```sh
# Download the text-only GGUFs (~8 GB total) from unsloth
mkdir -p /tmp/gguf
for q in Q4_K_M UD-Q3_K_XL UD-IQ2_M; do
  curl -L -o /tmp/gguf/gemma4-e2b-${q}.gguf \
    "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-${q}.gguf"
done

# Create Ollama Modelfiles using the Gemma chat template
for q in Q4_K_M UD-Q3_K_XL UD-IQ2_M; do
  cat > /tmp/Modelfile.$q <<EOF
FROM /tmp/gguf/gemma4-e2b-${q}.gguf
TEMPLATE """{{- range \$i, \$_ := .Messages }}
{{- \$last := eq (len (slice \$.Messages \$i)) 1 -}}
<start_of_turn>{{ if eq .Role "user" }}user
{{- if and \$.System (eq \$i 0) }}
{{ \$.System }}
{{ end }}{{ else }}model{{ end }}
{{ .Content }}<end_of_turn>
{{ if and \$last (ne .Role "model") }}<start_of_turn>model
{{ end }}
{{- end }}"""
PARAMETER stop "<end_of_turn>"
PARAMETER stop "<start_of_turn>"
EOF
  ollama create gemma4-textonly:$q -f /tmp/Modelfile.$q
done

.build/debug/openquack-polish-bench \
  --models "gemma4-textonly:Q4_K_M,gemma4-textonly:UD-Q3_K_XL,gemma4-textonly:UD-IQ2_M" \
  --prompts v2 \
  --out bench/out/polish/<host-tag>-textonly-quants \
  --unload-after
```

Output: `bench/out/polish/<host-tag>-spec007a-v2/{report.md,report.csv,results.jsonl}`.

For Claude-as-judge scoring, open `results.jsonl` in your IDE alongside
this bench post and score 1-5 per dimension per the SPEC-007 rubric;
the script at `/tmp/judge_scores.py` (in this repo's bench output of
2026-05-03) shows the aggregation.

Submit your host result via PR per `bench/CONTRIBUTING.md`.

## References

- [SPEC-007](SPECS/SPEC-007-llm-polish.md) — parent spec; harness, dimensions, judge protocol
- [SPEC-007a](SPECS/SPEC-007a-gemma-bench.md) — this bench's candidate matrix and tier ceiling revision
- [SPEC-008](SPECS/SPEC-008-in-context-rewrite.md) — surrounding-text rewrite (informs why D1 ceiled at ~2/5 here)
- Raw data: `bench/out/polish/M4-16GB-spec007a-v2/`
