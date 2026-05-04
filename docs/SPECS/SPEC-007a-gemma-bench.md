# SPEC-007a — Gemma 4 polish bench addendum

**Status:** draft (M2.5 — Wave 2 candidate, target ship 2026-05-18)
**Owner:** `OpenQuackKit/Polish/` — extends [SPEC-007](SPEC-007-llm-polish.md), no new harness
**Last updated:** 2026-05-03

## Goal

Settle SPEC-007's open question — *"Default model — settle once we
benchmark the candidate set on the three-dimension corpus above"* — with
**Gemma 4 added as a first-class candidate**, benched at multiple
quantisation tiers across the M-series Mac hardware spectrum.

The deliverable is two artefacts:

1. A per-tier default model recommendation (8 GB / 16 GB / 24 GB+).
2. A public bench post — `docs/BENCHMARKS-polish.md` — that can ship
   alongside a Wave-2 release one day before Google I/O 2026 keynote
   (2026-05-19, 10:00 PT).

This is an **addendum, not a new spec.** SPEC-007 already defines:
the harness (`openquack-polish-bench`), the three quality dimensions,
the LLM-as-judge scoring (Haiku 4.5 primary, Sonnet 4.6 adversarial,
Opus 4.7 tiebreak), the latency / memory-pressure protocol, the corpus
shape. None of that changes. This addendum only:

- Adds Gemma 4 E2B / E4B as candidates.
- Promotes quantisation level from a hidden variable to a benched axis.
- Adds a hardware-tier dimension to the recommendation output.
- Raises the implicit ≤ 2 GB cap to a tier-aware threshold (see below).

## Why now

Three signals align:

- **Gemma 4 launched 2026-04-02 under Apache 2.0** — clean downstream
  fit for OpenQuack's MIT app (no copyleft, no patent-retaliation).
- **Google I/O is 2026-05-19 / 20.** A pre-I/O drop catches the
  amplification window; the same integration shipped a week later
  competes with everything else announced at I/O.
- **No mainstream Mac dictation app currently ships fully-local Gemma
  polish.** SuperWhisper and VoiceInk both punt to cloud APIs; MacWhisper
  does no polish at all. The MIT-app + Apache-weights + verifiable-local
  combo is uncontested in this niche today and won't be after I/O.

The original SPEC-007 candidate list (`gemma3:1b`, `gemma3:4b-it-qat`,
`qwen2.5:*`, `llama3.2:*`, `gemma3n:e2b` reference) predates Gemma 4 by
weeks. Refreshing it now is the cheap part; the marketing-window
alignment is the asymmetric upside.

## Non-goals

- **Replacing Whisper with Gemma's audio.** Gemma 4 E2B/E4B accept audio
  input but cap at 30 seconds and post WER ~13 % vs Whisper's ~4 %
  (per published comparisons). Whisper stays. Polish only.
- **A new harness.** SPEC-007's `openquack-polish-bench` runs unchanged;
  this addendum extends its candidate matrix.
- **Cloud Gemma.** Gemma is available on Vertex AI / AI Studio; we don't
  care. Local-only by construction (SPEC-007 non-goal #1).
- **Shipping bigger Gemmas.** 26B-A4B and 31B-Dense are research-tier on
  consumer Macs (~16 GB and ~20 GB resident respectively at Q4); they
  bench-only. Defaults ship from E2B/E4B.

## Candidate matrix

Four models × three quant tiers × three Mac hardware tiers. Many cells
are NA (model + quant > available memory after Whisper); realistic cell
count is ~20.

### Models

| Model | Native | Q4 (TurboQuant / GGUF) | Q5_K_M (GGUF) | Why included |
|---|---|---|---|---|
| **Gemma 4 E2B** | ~10 GB | ~3.2 GB | ~4.0 GB | Marketing-aligned hero candidate |
| **Gemma 4 E4B** | ~16 GB | ~5.0 GB | ~6.2 GB | Quality ceiling within reach |
| **Phi-4-mini** (3.8 B) | ~7.6 GB | ~2.4 GB | ~3.0 GB | Reasoning-tuned competitor |
| **Qwen 3 (3 B)** | ~6 GB | ~1.9 GB | ~2.4 GB | Multilingual competitor |

The original SPEC-007 list (`gemma3:1b`, `gemma3:4b-it-qat`,
`qwen2.5:1.5b-instruct`, `qwen2.5:3b-instruct`, `llama3.2:1b`,
`llama3.2:3b`, `gemma3n:e2b` reference) is **kept as historical baseline
in `bench/out/polish/historical/`** but does not inform the M2.5 default
choice. Newer weights, newer instruction-tuning, newer judge calibration
make a fresh run the honest comparison.

### Quant formats

- **TurboQuant (MLX)** — primary path. Per Apple/MLX docs: ~4× less
  active memory than naive Q4 at parity accuracy on Apple Silicon.
  Native Apple Silicon, fastest decode. Default ship target.
- **Q4_K_M (GGUF, llama.cpp)** — fallback path. Universal compatibility,
  well-tested. Bench so we know the gap.
- **Q5_K_M (GGUF)** — quality-leaning option for users with memory
  headroom. Bench only where it fits.

Q3 / Q2 not benched in this round. Polish is structurally a constrained
task (filler strip + light rewrite), so Q3 may hold up — but adding it
expands the matrix beyond what's testable in the May 6–17 window. Defer
to a follow-up bench post.

### Hardware tiers

| Tier | Spec | Headroom for polish | Default candidate ceiling |
|---|---|---|---|
| **Compatibility** | M-series 8 GB | ~5 GB free w/ Whisper medium loaded | Q4 ≤ 2.5 GB |
| **Standard** | M-series 16 GB | ~12 GB free | Q4 ≤ 5 GB |
| **Premium** | M-series 24 GB+ | ~20 GB free | Q5 ≤ 7 GB; tier opens up E4B Q5 |

Auto-detect at first launch; override available in Settings → Polish.

## Cap revision: tier-aware ceiling supersedes SPEC-007's implicit ≤ 2 GB

SPEC-007 §"Recommendation hierarchy" reads *"Smaller-that-clears-quality
> faster > more accurate"* with an implicit ≤ 2 GB cap that a v0.1
heuristic produced. Gemma 4 E2B Q4 at ~3.2 GB busts this on the
Compatibility tier and fits comfortably on Standard / Premium.

**Resolution:** the ≤ 2 GB ceiling applies to the **Compatibility tier
only**. Standard and Premium tiers default to whatever the bench
identifies as the quality-per-MB Pareto winner within their headroom
budget. SPEC-007's hierarchy ordering still holds *within each tier*.

If the Compatibility tier has no candidate that clears the quality bar
under 2.5 GB — i.e. all candidates require ≥ 3 GB to score acceptably —
the tier ships with polish off by default and a Settings toggle to
enable a degraded-quality polish at the user's choice. We do not
silently downgrade quality on hardware that can't host it.

## Coexistence test (mandatory, reuse SPEC-007 §"Coexistence test")

The single-most-important test, copied from SPEC-007 verbatim:

> Hold WhisperKit medium + polish model warm, idle 60 s with a
> synthetic background allocation (~2 GB) to simulate a user's other
> apps, *then* measure polish latency on a fresh utterance.

For Gemma E2B Q4 on a Standard tier (M-series 16 GB) with Whisper
medium warm + 2 GB synthetic load + Cursor / Mail open: the test
target is < 1.2 s mean polish latency on a 50-word utterance. If
P95 exceeds 2.5 s the candidate is disqualified for that tier.

## Output: `docs/BENCHMARKS-polish.md`

Mirror the structure of `docs/BENCHMARKS.md`. Required sections:

1. **Headline numbers** — winner per tier, one sentence each.
2. **Per-tier recommendation table** — model × quant × resident × P95.
3. **Quality matrix** — judge scores per dimension per (model, quant).
4. **Quality vs size Pareto frontier** — chart, exported to PNG for
   the launch post.
5. **Methodology** — pointer to SPEC-007 + this addendum.
6. **Reproducing** — exact CLI invocation per host tag.
7. **Open questions** — what next bench should test.

## Connection to the launch arc

This bench is the technical substrate for OpenQuack's Wave 2 launch.
Pacing:

| Date | Action |
|---|---|
| 2026-05-06 | SPEC-007a merged; bench harness expanded with new candidates |
| 2026-05-06 → 09 | Bench runs across host tags; Gemma + Phi + Qwen |
| 2026-05-10 | Quality scores compiled; tier defaults selected |
| 2026-05-11 → 14 | Integration into `MLXLMPolishEngine`; Settings UI |
| 2026-05-15 → 17 | Dogfood, polish post drafted, viral assets generated |
| 2026-05-18 | Ship `v0.2.0-polish` with default model per tier |
| 2026-05-19 | Wave 2 launch — bench post + integration tweet, Google I/O day |

The bench post is publishable regardless of which model wins. If Gemma
wins, Wave 2 leads with Google amplification mechanics
(@osanseviero, @awnihannun, Gemmaverse submission). If Gemma loses,
Wave 2 leads with the comparison data itself — *"we benched four
2-4 B models across three quant formats on three Mac tiers, here's
the Pareto frontier"* — and Gemma ships as a supported alternative
rather than the default. Either path produces a durable artefact.

## Risks

| Risk | Mitigation |
|---|---|
| Gemma loses to Phi/Qwen on polish quality | Ship the winner; bench post still publishes; Gemma stays as a Settings option |
| Compatibility tier (8 GB) has no viable Q4 candidate | Polish ships off-by-default at that tier; Settings toggle exists |
| TurboQuant builds for Gemma 4 unstable on M-series at bench time | Fall back to Q4_K_M GGUF + GGUF runner; document the gap; revisit |
| Apache-2.0 model files redistributed by us trigger bundle-size concerns | Models download on first polish use, not bundled. Same pattern as Whisper. |
| Bench harness can't load all four models in the May 6–10 window | Drop Llama 4 (already not in candidate set); keep Gemma + Phi + Qwen |
| I/O timing slips (delayed announcement, etc.) | Wave 2 detaches from I/O calendar; ships when ready, loses the timing bonus only |

## Open questions

- **Should `mlx-vlm` or `mlx-lm` be the runtime?** SPEC-007 picked
  `mlx-swift-lm`. Gemma 4 is multimodal so `mlx-vlm` is the canonical
  loader, but for text-only polish `mlx-lm` may suffice and avoid a
  fatter dependency. Settle during integration.
- **Streaming polish output?** SPEC-007 punted to "no streaming."
  Re-evaluate if Gemma E2B's ~100 tok/s on M3 makes streaming feel
  responsive enough to surface in the overlay.
- **Publish the bench corpus publicly?** SPEC-007's
  `bench/polish_corpus/cases.jsonl` is currently in-tree. Worth
  promoting to a separate `openquack/polish-corpus` repo for
  community contribution? Defer to a v0.3+ decision.
- **A "Powered by Gemma" Settings line?** Subtle attribution that
  makes the integration legible to a curious user. Lean: yes, with
  a click-through to the bench post. Avoid surfacing in the menu bar.

## References

- [SPEC-007](SPEC-007-llm-polish.md) — parent spec; harness + dimensions
- [Gemma 4 model card](https://ai.google.dev/gemma/docs/core/model_card_4)
- [Gemma 4 launch — blog.google](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/)
- [Welcome Gemma 4 — HuggingFace blog](https://huggingface.co/blog/gemma4)
- [Gemma 4 on Apple Silicon — SudoAll benchmarks](https://sudoall.com/gemma-4-31b-apple-silicon-local-guide/)
- [Whisper vs Gemma audio — Medium / Ajjay K](https://medium.com/@ajjay.ferrari/one-model-or-two-my-on-device-speech-stack-debate-whisper-vs-gemma-3n-audio-scribe-4aca133258ff)
- [Google I/O 2026](https://io.google/2026/) — May 19–20
- [Gemmaverse showcase](https://deepmind.google/models/gemma/gemmaverse/)
