# Confucius4-R2T2 (NetEase Youdao) — should OpenQuack adopt it?

**Status:** research note (not a SPEC, not a commitment)
**Date:** 2026-10-03
**Scope:** NetEase Youdao's open-weights streaming ASR model, released late
September 2026, and whether it belongs in OpenQuack as a transcription engine.

> **Short answer:** not as a drop-in today, but it's a strong signal to add a
> **Qwen3-ASR engine** (the architecture R2T2 is built on). R2T2 itself then
> becomes a candidate model *inside* that engine, gated on our own bench and
> on users accepting a non-OSI weights license.

## What it is

Primary source: [github.com/netease-youdao/Confucius4-R2T2](https://github.com/netease-youdao/Confucius4-R2T2)
(README, `r2t2/r2t2_asr.py`, `r2t2_llama/README.md`, `MODEL_LICENSE`).
Weights: `netease-youdao/Confucius4-R2T2` (HF + ModelScope) and a
`Confucius4-R2T2-GGUF` repo with several quantisations.

- **Architecture:** a fine-tune of **Qwen3-ASR (1.7B class)** — the README and
  `pyproject.toml` describe it as "built on the Qwen3-ASR architecture"; it
  depends on the upstream `qwen-asr` package and loads through the same
  processor/model classes. NetEase's launch post says 1.7B parameters.
- **What's new:** a "Longest Stable Prefix" training recipe (stable-prefix data,
  forced alignment, token-level audio segmentation) so that streaming output is
  **append-only** — committed text is never revised. Chunk size is configurable
  from 80 ms to 2 s; README claims 200–600 ms average latency.
- **Languages:** optimised for Chinese + English, incl. code-switch; also
  fr/de/it/ja/ko/pt/ru/es/ar. Supports context/hotword prompting (inherited from
  Qwen3-ASR's text "background" priming).
- **Inference stacks shipped:** vLLM (primary; streaming is "vLLM backend
  only"), HF Transformers (offline), and a llama.cpp route (`r2t2_llama`) whose
  only prebuilt binaries are **Linux x86_64 + CUDA, CPython 3.12**. No macOS,
  MLX, or Core ML path is provided.

### How streaming actually works (matters for a Mac)

`streaming_transcribe()` appends each new chunk to `audio_accum` and **re-feeds
all audio seen so far** to the encoder, then decodes with the previous text
(minus the last `unfixed_token_num` tokens) as a forced prefix. That is simple
to port, but encoder cost grows with utterance length — on a GPU server it's
fine; on an M-series Mac for 30–60 s dictations it needs measuring before we
promise sub-second partials.

## Published accuracy (their numbers, not ours)

WER % (en) / CER % (zh), lower is better. ※ = pseudo-streaming (may revise
emitted text). Column order verified against the README's raw HTML table.

| Dataset | Qwen3-ASR※ 2 s | Qwen3-ASR 160 ms | **R2T2 160 ms** | Nemotron 160 ms | Voxtral 160 ms | Commercial B※ |
|---|---|---|---|---|---|---|
| LS-clean | 1.67 | 22.30 | **2.13** | 3.71 | 2.49 | 1.25 |
| LS-other | 3.54 | 25.74 | **4.88** | 8.27 | 7.15 | 2.48 |
| AMI | 9.25 | 24.79 | **11.37** | 18.11 | 15.94 | 8.44 |
| TED-LIUM | 2.33 | 19.18 | **3.34** | 5.11 | 4.60 | 3.30 |
| Wenet-net (zh) | 4.94 | 19.79 | **5.87** | 24.70 | 23.53 | 4.79 |
| Wenet-meeting (zh) | 5.97 | 20.38 | **7.27** | 20.18 | 60.54 | 3.75 |
| SPEECHIO-06 (zh) | 6.10 | 24.50 | **7.30** | 22.52 | 32.16 | 5.34 |
| CN-RealSI (zh) | 3.34 | 39.72 | **3.48** | 11.52 | 8.74 | 3.64 |

Reading it honestly:

1. The headline win is **true streaming at 160 ms**: R2T2 is ~4–10× better than
   naively running Qwen3-ASR at the same chunk size, and clearly ahead of the
   other open true-streaming models, especially on Chinese.
2. **Qwen3-ASR with 2 s pseudo-streaming beats R2T2 on every row.** R2T2's README
   publishes no offline (whole-utterance) numbers.
3. All numbers are vendor-run. Nothing here is on our corpus or our hardware.

## Fit with OpenQuack

| Question | Answer |
|---|---|
| Does our product need append-only streaming? | **Not today.** OpenQuack transcribes after hotkey release; SPEC-012 chunks long audio but "the user never sees partials". R2T2's core advantage only pays off once the ⚪ *Live partial transcripts* backlog item ships. |
| Would it fix our weak spot? | Very likely yes for **Mandarin** (#17 / SPEC-021): Whisper `medium` sits at 12.9 % CER on our 30 s zh clip; the Qwen3-ASR family is in a different league on zh. But for record-then-transcribe the right comparator is **offline Qwen3-ASR-1.7B**, which the table suggests is at least as accurate. |
| Can it run on a Mac today? | **No official path.** vLLM/CUDA or Linux-CUDA llama.cpp only. Because it is architecturally Qwen3-ASR, existing Swift/MLX Qwen3-ASR ports (`soniqo/speech-swift`, `mlx-audio-swift` STT) are the plausible route after an MLX weight conversion — unverified. |
| Footprint | 1.7B params ≈ 3.4 GB bf16, ~1 GB at 4-bit. Comparable to Whisper `large-v3` (~3 GB) at bf16; smaller once quantised. |
| Privacy contract | Fine if run locally (same as WhisperKit). |

## License — the real blocker

Code is Apache-2.0, but the **weights are under the "NetEase Youdao Model Use
License Agreement"**, which is not an OSI license:

- Free, royalty-free use — **unless** the user/affiliates exceed 100 M MAU or
  RMB 1 B annual revenue, in which case they need a separate written license.
  An individual OpenQuack user at a large company could trip this.
- Every copy must carry the agreement + notices; redistributors must bind
  downstream recipients; quantised/converted weights are "Derivative Works"
  that need a prescribed disclaimer.
- §3.4(c): outputs may not be used to **improve any other AI model** except
  R2T2 derivatives or non-commercial models — keep R2T2 transcripts out of any
  future training/distillation pipeline (cf. SPEC-016).
- Governed by PRC law, CIETAC arbitration; licence revocable on breach.

Consequence: OpenQuack must **never bundle or re-host** the weights, and should
never make R2T2 the default. If offered, it is an opt-in download from the
upstream repo, with the license shown and accepted in-app. Qwen3-ASR itself is
Apache-2.0 and has none of these issues.

## Recommendation

1. **Now (no code):** none needed in-app. Note: R2T2's bundled server is a
   custom WebSocket protocol, not OpenAI-compatible, so it does **not** plug into
   SPEC-044's remote endpoint as-is. Whether `vllm serve` exposes
   `/v1/audio/transcriptions` for this checkpoint (as it does for upstream
   Qwen3-ASR) is untested.
2. **Next (spec):** write a spec for a local **`Qwen3ASREngine`** behind
   `TranscriptionEngine`, MLX-backed via an existing Swift port (dependency note
   required per AGENTS.md). Acceptance: on `bench/corpus/multilingual` zh clips +
   `short`, CER/WER and RTF vs WhisperKit `medium` / `large-v3` on an M4-16GB.
   This is the most direct path to the Mandarin quality fix.
3. **Then (bench):** with the engine in place, load R2T2 weights (MLX-converted
   locally by the user / at download time) as a model option and bench it
   against stock Qwen3-ASR-1.7B on our corpus — offline mode and SPEC-012 chunked
   mode. Ship it as an opt-in model only if it wins, with in-app license
   acceptance.
4. **Later:** revisit R2T2's append-only streaming when *Live partial
   transcripts* is picked up — it is currently the best open option for that UX,
   pending a measurement of its re-encode cost on Apple Silicon.

## Sources

- R2T2 repository (README, code, `MODEL_LICENSE`): https://github.com/netease-youdao/Confucius4-R2T2
- NetEase launch post (1.7B, 80 ms–2 s chunks): https://x.com/NetEase_Global/status/2100220446004429217
- Qwen3-ASR tech report: https://arxiv.org/abs/2601.21337
- Swift/MLX Qwen3-ASR ports: https://github.com/soniqo/speech-swift, https://github.com/Parassharmaa/mlx-audio-swift
- Prior landscape note: [`live-speech-models.md`](live-speech-models.md)
