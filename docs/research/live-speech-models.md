# Live / streaming multimodal speech models — landscape research

**Status:** research note (not a SPEC, not a commitment)
**Date:** 2026-05-04
**Scope:** what's available today for on-device, streaming, system-prompt-conditioned speech models, and what's plausible 6–18 months out.

> This document exists to answer one question for OpenQuack:
> **Should we replace WhisperKit + Ollama-polish with a single multimodal speech model?**
>
> Short answer for May 2026: **no, not yet.** Add Parakeet-TDT-0.6B-v3 as a second
> STT backend behind a flag if WhisperKit ever becomes a constraint. Track Voxtral
> Realtime + Canary-Qwen successor for a re-evaluation in Q4 2026.

## TL;DR

No on-device, open-weights model gives all three of:
1. true streaming output,
2. arbitrary system-prompt conditioning of transcription style,
3. Mac-feasible memory simultaneously.

The two halves exist separately:

- **Streaming + open weights + Mac**: Voxtral-Mini-4B-Realtime, Parakeet-TDT-0.6B-v3, Moshi 7B, Qwen3-ASR-0.6B/1.7B.
- **System-prompt conditioning of audio**: Canary-Qwen-2.5B (SALM pattern), Phi-4-Multimodal, Qwen2.5-Omni.

Voxtral-Mini-3B's HF card states it plainly: *"System prompts are not yet supported."*
Voxtral does ship **context biasing** (≤100 vocabulary terms), but that is not the same
thing as "preserve self-corrections" or "format as bullets" — those need real
instruction-following over the audio path. Intersection is ~12–18 months out.

## Per-model summaries

### 1. Moshi (Kyutai)

- **Architecture.** RQ-Transformer = 7B Temporal Transformer + small Depth
  Transformer over Mimi codec tokens (RVQ, 12.5 Hz frames, 1.1 kbps, semantic +
  acoustic codebooks). Models two parallel audio streams (user + Moshi) plus an
  "inner monologue" text stream — text-as-anchor for audio generation.
- **Streaming.** Full-duplex, ~160 ms theoretical / ~200 ms practical on L4 GPU.
- **System prompt.** Not documented; persona conditioning via voice embeddings,
  not text instructions.
- **On-device.** Official MLX checkpoints (int4/int8/bf16), Rust/Candle.
- **License.** Code MIT/Apache, weights CC-BY-4.0.
- **Verdict.** Built for two-way speech, not dictation. Wrong shape for OpenQuack.

Refs: [arXiv 2410.00037](https://arxiv.org/html/2410.00037v2), [GitHub](https://github.com/kyutai-labs/moshi).

### 2. GPT-4o Realtime / gpt-realtime / gpt-realtime-1.5

Closed weights. Bidirectional WebSocket / WebRTC / SIP (SIP added late 2025),
native audio I/O with token interleaving. Pricing implies a unified token-stream
architecture (audio in $100/M tokens, audio out $200/M tokens). System prompts
work as for any GPT-4o session. **Informative for direction only** — confirms
unified text+audio token streams are the production-grade pattern.

**Naming note.** OpenAI keeps the realtime line decoupled from the GPT-N
text-frontier line: there is **no `gpt-5-realtime`**. The current model is
`gpt-realtime-1.5` (released **2026-02-23**), succeeding `gpt-realtime-2025-08-28`.
The text frontier `gpt-5.5-2026-04-23` is reasoning/text only — no realtime
variant. Same separation pattern as the transcription line
(`gpt-4o-mini-transcribe-2025-12-15`). For us this argues against assuming a
future Gemma-N text release will automatically have a usable voice sibling —
voice gets its own training run, its own quantization, its own deployment.

**`gpt-realtime-1.5` deltas vs prior snapshot:** +5 % on Big Bench Audio
reasoning, +10.23 % alphanumeric transcription accuracy, +7 % instruction
following. Pricing unchanged. **Reported regression**: voice expressiveness
and accent quality on Dutch, Flemish, French, Hebrew, and Japanese; intonation
described as "robotic" and "flat"; the model occasionally says "laugh"
*instead of producing laughter* — a control-mismatch failure where text-anchor
behaviour leaks back into native audio. *Engineering data point: cross-lingual
voice quality is hard to non-regress across versions.* For OpenQuack: argues
strongly for **version-pinning the polish model and bench-validating per
language before any silent upgrade.**

**A mini-tier exists.** Late-2025 OpenAI shipped `gpt-realtime-mini-2025-12-15`
(plus `gpt-4o-mini-transcribe`, `gpt-4o-mini-tts`, `gpt-audio-mini`). Mirrors
the WhisperKit pattern of "ship multiple sizes, let the integrator pick." Bench
gains in the mini-tier release: **+18.6 pp instruction-following** on
speech-to-speech, +12.9 pp tool-calling, ~35 % lower TTS WER on Common Voice
and FLEURS. Failure modes named explicitly: *"long conversations or with edge
cases like silence, and tool-driven flows."* The persisting "silence ⇒
hallucination" failure is the most actionable lesson — see §J below.

Refs: [Introducing gpt-realtime](https://openai.com/index/introducing-gpt-realtime/),
[Updates for developers building with voice (2025-12-22)](https://developers.openai.com/blog/updates-audio-models),
[gpt-realtime-1.5 announcement (community)](https://community.openai.com/t/gpt-realtime-1-5-is-live-in-realtime-api/1374919),
[gpt-realtime-1.5 regression report (community)](https://community.openai.com/t/gpt-realtime-1-5-major-regression-in-voice-expressiveness-and-accent-quality/1377222),
[Latent Space manual](https://www.latent.space/p/realtime-api).

### 3. Gemini 2.5 / 3.1 Flash Live

Closed weights, native audio-to-audio (no STT→LLM→TTS cascade), 16 kHz PCM in /
24 kHz PCM out, full-duplex with barge-in over WSS. The current GA-preview is
**Gemini 3.1 Flash Live** (released **2026-03-26**). There is no separate
"Gemini 3 Pro Live" — only Flash. Naming jumped 2.5 → 3.1 with no 3.0.

Specs worth knowing for OpenQuack:

- **>90 languages** in Gemini 3.1 Flash Live — a 4× expansion over the 24
  languages quoted for the 2.5 generation. Largest cloud realtime-voice
  language footprint by a wide margin.
- **131,072-token input context, 65,536-token output** — ~4× and ~16× the
  gpt-realtime-1.5 budget (32 k context, 4 k output).
- **Configurable `thinking` levels** (minimal / low / medium / high) on the
  Live model — speculative implication: a "transcribe + briefly think + emit"
  flow gets first-class API support inside Gemini Live before any other
  vendor exposes it.
- **No caching, no structured outputs, no batch API, no code execution.**
  Function calling synchronous-only.
- **Headline benchmarks Google publishes**: 90.8 % ComplexFuncBench Audio,
  36.1 % Audio MultiChallenge, "twice as long" conversation thread retention
  vs Gemini 2.5 Flash Native Audio. Better acoustic-nuance recognition (pitch,
  pace). All audio is SynthID-watermarked.

For OpenQuack: still **informative only** (cloud, closed). But the >90-language
footprint changes the answer if we ever add a "Polish via cloud LLM" backend
for languages where local models lag.

Refs: [Gemini 3.1 Flash Live blog](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-1-flash-live/),
[Build real-time conversational agents with Gemini 3.1 Flash Live](https://blog.google/innovation-and-ai/technology/developers-tools/build-with-gemini-3-1-flash-live/),
[Gemini 3.1 Flash Live model card](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-live-preview),
[Gemini Live API overview](https://ai.google.dev/gemini-api/docs/live-api).

### 4. Voxtral (Mistral) — most relevant to OpenQuack

Three SKUs as of May 2026: **Mini-3B** (offline, July 2025), **Small-24B**
(offline), **Mini-4B-Realtime-2602** (Feb 2026, streaming).

- **Architecture (Realtime).** ~970M custom *causal* audio encoder + ~3.4B
  Ministral-derived LLM, sliding-window attention end-to-end → genuine
  streaming, not chunked.
- **Streaming.** Configurable 80 ms–2.4 s delay; sub-200 ms achievable; ~1–2 %
  WER at 480 ms; >12.5 tokens/s on minimal HW.
- **System prompt.** Explicitly **not yet supported** on Mini-3B HF card; same
  chat-template family applies to Realtime.
- **Context biasing.** Up to 100 terms (English best, others experimental).
- **On-device Mac.** Mistral spec ≥16 GB GPU memory bf16; **community MLX 4-bit
  ports exist** (`mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit`,
  `mzbac/mlx.voxtral`, `T0mSIlver/voxmlx`).
- **License.** Apache 2.0. **Languages:** 13.
- **Competitor reference.** A community macOS dictation app `localvoxtral`
  already ships with optional LLM polish — the most direct comparable to
  OpenQuack and worth studying / benchmarking against.

Refs: [Voxtral Realtime HF](https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602),
[Voxtral Mini-3B HF](https://huggingface.co/mistralai/Voxtral-Mini-3B-2507),
[Mistral news](https://mistral.ai/news/voxtral-transcribe-2),
[localvoxtral](https://github.com/T0mSIlver/localvoxtral),
[voxtral.c](https://github.com/antirez/voxtral.c).

### 5. Parakeet TDT 0.6B v2 / v3 (NVIDIA)

- **Architecture.** 24-layer FastConformer encoder + Token-and-Duration
  Transducer (RNN-T variant). 600M params, 8 192-token SentencePiece vocab. v3
  adds 25 European languages.
- **Streaming.** Native, configurable left/right context.
- **System prompt.** None — it's a transducer, not an LLM. Context biasing via
  predictor prefilling exists in NeMo but not yet in MLX port.
- **MLX port.** [`senstella/parakeet-mlx`](https://github.com/senstella/parakeet-mlx)
  is the de-facto Mac route; runs on 8 GB MacBook Air; auto-selects MLX backend
  on Apple Silicon.
- **License.** Apache 2.0.
- **Verdict.** The honest "Whisper replacement" — faster, smaller, similar
  quality, zero polish capability.

Refs: [Parakeet v3 HF](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3),
[arXiv 2509.14128](https://arxiv.org/html/2509.14128v2).

### 6. WhisperKit (Argmax)

Mature Swift / CoreML framework; modified the Whisper architecture so the
encoder supports streaming and the decoder yields progressive results. ICML 2025
paper reports **2.2 % WER** with Large v3 Turbo on the Neural Engine at
real-time streaming latency. 99 languages. No prompt conditioning beyond
Whisper's existing 224-token decoder prompt (used today for vocabulary biasing).
Apache-style license. **The current OpenQuack base — and still SOTA for
streaming Whisper on Mac.**

Refs: [WhisperKit ICML paper](https://arxiv.org/html/2507.10860v1),
[GitHub](https://github.com/argmaxinc/WhisperKit).

### 7. AudioPaLM / SpeechGPT / AudioLM

Architecturally informative ancestors. Established the "audio-tokens-as-language"
pattern (RVQ codecs → discrete tokens → standard LM training). Every model in
this list inherits from that lineage. Not deployable today.

### 8. Qwen2-Audio / Qwen2.5-Omni / Qwen3-ASR / Qwen3-Omni

- **Qwen2.5-Omni-7B.** Thinker-Talker dual-track architecture, 2-second audio
  blocks with block-wise attention, sliding-window DiT for streaming audio out,
  TMRoPE for AV sync. Truly streaming. 7B param footprint.
- **Qwen3-ASR (0.6B / 1.7B).** AuT (attention-encoder-decoder) ASR head + Qwen3-Omni
  foundation; 52 languages; vLLM streaming supported (no batch-stream + timestamps
  simultaneously); RL-trained for noise robustness; supports **text "background"
  priming** for vocabulary — closer to the user ask but still not a full system
  prompt. Apache 2.0. No mature MLX port yet.

Refs: [Qwen3-ASR HF](https://huggingface.co/Qwen/Qwen3-ASR-1.7B),
[arXiv tech report](https://arxiv.org/html/2601.21337v2),
[vLLM recipe](https://docs.vllm.ai/projects/recipes/en/latest/Qwen/Qwen3-ASR.html).

### 9. GLM-4-Voice / MiniCPM-o 2.6

- **MiniCPM-o 2.6.** 8B end-to-end omnimodal (SigLip-400M + Whisper-medium +
  ChatTTS + Qwen2.5-7B). Time-Division Multiplexing for streaming. Phone-class
  deployment claimed. Bilingual EN/ZH.
- **GLM-4-Voice.** GLM-4 family extension to speech I/O.

Both strong on full-duplex chat, weaker on the dictation+instruction use case.

Ref: [MiniCPM-o GitHub](https://github.com/OpenBMB/MiniCPM-o).

### 10. Phi-4-Multimodal / Canary / Canary-Qwen-2.5B

- **Phi-4-Multimodal.** 5.6B (3.8B Phi-4-Mini + 460M audio LoRA + 370M vision
  LoRA), mixture-of-LoRAs. Top of OpenASR leaderboard at 6.14 % WER (Feb 2025).
  **Streaming not natively supported** — only incremental decoding. MIT license.
  No MLX port. Audio max ≈40 s for general tasks.
- **Canary-1B-v2 / Parakeet v3** (same paper). FastConformer + Transformer
  decoder; Canary-1B-v2 hits 7.15 % WER at **749 RTFx** vs Whisper-large-v3 at
  145 RTFx. 25 European languages. Chunked + streaming inference supported;
  CC-BY-4.0.
- **Canary-Qwen-2.5B** — *the most architecturally interesting for OpenQuack.*
  SALM (Speech-Augmented LM) = FastConformer + frozen Qwen3-1.7B + linear
  projection + LoRA. Two modes: **ASR mode** (audio-conditioned) and **LLM mode**
  (`disable_adapter()` then prompt the Qwen for summarization / QA over the
  transcript). The closest published thing to what we actually want — but
  English-only, not streaming, CC-BY-4.0.

Refs: [Phi-4-MM HF](https://huggingface.co/microsoft/Phi-4-multimodal-instruct),
[Canary-Qwen HF](https://huggingface.co/nvidia/canary-qwen-2.5b).

## Chinese-ecosystem live voice models (supplement)

Doubao + Chinese-ecosystem coverage. A few notable absences first:

- **Yi-Audio (01.AI)**: does not exist as a public artefact. 01.AI restructured
  in early 2025 (joint lab with Alibaba on LLMs; Wanzhi enterprise platform;
  spin-offs). Yi remained text-only. Treat the slot as empty.

### A. Doubao Realtime Voice (豆包) — ByteDance

- **Architecture.** End-to-end Speech2Speech model (not cascaded). ByteDance
  describes it as "native" speech-text — understanding and generation share one
  backbone. Param count unpublished. Volcengine WSS endpoint
  (`wss://openspeech.bytedance.com/api/v3/realtime/dialogue`).
- **Streaming.** Full-duplex; barge-in supported; ~700 ms naked-model latency.
  Partial transcripts + token streams + audio frames concurrently.
- **System prompt.** Persona / voice / pacing controls exposed; session-level
  system prompts and tool-calling per Volcengine docs.
- **On-device.** None. Closed weights, Volcengine-hosted only.
- **License.** Closed / proprietary.
- **Multilingual.** Chinese-first (Mandarin + dialects via FireRedASR2 sibling).
  English supported but ByteDance notes "does not yet accommodate multilingual
  conversations" — no first-class within-utterance code-switching at the
  realtime model level. (FireRedASR2 ASR product does support Mandarin↔English
  code-switching, but that's separate from the realtime S2S model.)
- **Current state.** Live since Jan 2025 in the Doubao consumer app and on
  Volcengine.

Refs: [Doubao Realtime Voice — Seed](https://seed.bytedance.com/en/realtime_voice),
[EQ-IQ blog](https://seed.bytedance.com/en/blog/doubao-realtime-voice-model-is-available-upon-release-high-eq-and-iq).

### B. Step-Audio 2 / Step-Audio 2-mini — StepFun

- **Architecture.** End-to-end audio LLM. Mini = audio encoder + audio adapter +
  Qwen2.5-7B decoder + audio detokenizer; ~8B class. Audio tokenizer S3Tokenizer
  @ 50 Hz; diffusion vocoder to 24 kHz. Optional retrieval head + tool-calling.
- **Step-Audio R1 / R1.1 (Realtime).** Separate, more recent variant: Qwen2-based
  audio encoder + Qwen2.5-32B decoder (~33B); R1.1-Realtime "Dual-Brain"
  Formulation/Articulation split for "thinking while speaking."
- **Streaming.** Yes — Mini is real-time S2S; R1.1-Realtime emphasises low TTFT.
- **System prompt.** Instruction-tuned for "fluid conversations." Tool-calling
  exposed (weather/search/date examples). Schema inferred from chat-template.
- **On-device.** Mini at 8B is the most plausible candidate. **HF card lists
  CUDA-only requirements** (PyTorch 2.3-cu121, ONNX Runtime, s3tokenizer,
  diffusers). No MLX/GGUF/llama.cpp port published. R1/R1.1 at 33B is too large.
- **License.** Apache 2.0 across the mini family + R1.
- **Multilingual.** English, Chinese (Cantonese + 6 dialect/accent test sets),
  Japanese, Arabic. Strong English ASR (see synthesis).
- **Current state.** Mini released Aug 29 2025; R1 / R1.1-Realtime late November
  2025; EditX (3B audio editor) Nov 2025. Most aggressively open Chinese
  audio-LLM family.

### C. Hunyuan Voice — Tencent

End-to-end (Tencent's framing), tailored for low-latency communication. No
published parameter count or architecture paper. Soft-launched inside Yuanbao
(Tencent's consumer assistant) with planned realtime video-call integration.
Quoted ~1.6 s response lag (slower than Doubao's 700 ms claim and slower than
OpenAI/Gemini realtime). No open weights for Hunyuan **Voice** specifically as
of this research date — treat as closed product.

### D. Covo-Audio — Tencent (open weights, March 2026) — added

- **Architecture.** End-to-end audio LLM at 7B. Stack: Whisper-large-v3 encoder
  @ 50 Hz → adapter (downsampled to 6.25 Hz) → Qwen2.5-7B-Base LLM → WavLM-large-derived
  speech tokenizer (16 384-codebook discrete tokens @ 25 Hz) → Flow-Matching +
  BigVGAN vocoder @ 24 kHz. Full-duplex variant **Covo-Audio-Chat-FD** uses
  0.16 s chunk streaming with **THINK / SHIFT / BREAK control tokens** for
  turn-taking and barge-in.
- **Streaming.** Explicitly full-duplex. 160 ms audio chunks. Notable for
  explicit turn-control tokens rather than implicit VAD.
- **System prompt.** Standard chat-template via Qwen2.5 backbone; THINK
  reasoning tokens are model-native.
- **On-device.** 7B Qwen2.5 backbone is ~4 GB at Q4 and trivially MLX-portable,
  but Whisper-large-v3 encoder (~3 GB fp16 / ~1.5 GB Q4) + WavLM tokenizer +
  Flow-Matching/BigVGAN decoder add several GB. No MLX/GGUF port published yet.
- **License.** Disputed in secondary sources (CC-BY-4.0 vs Tencent custom
  research license). **Read the LICENSE file in-repo before any commercial use.**
- **Multilingual.** Whisper-v3 encoder gives strong multilingual ASR coverage;
  Mandarin emphasised in eval.
- **Current state.** Open-sourced March 26 2026. Most recent of the bunch and
  the most architecturally interesting because of the explicit chunk-streaming +
  control-token design — closest fit to OpenQuack's voice-input target of any
  Chinese-ecosystem model.

Refs: [Covo-Audio paper coverage (MarkTechPost)](https://www.marktechpost.com/2026/03/26/tencent-ai-open-sources-covo-audio-a-7b-speech-language-model-and-inference-pipeline-for-real-time-audio-conversations-and-reasoning/),
[GitHub](https://github.com/Tencent/Covo-Audio),
[HF weights](https://huggingface.co/tencent/Covo-Audio-Chat).

### E. Baichuan-Audio — Baichuan Inc.

- **Architecture.** Three-component end-to-end: Baichuan-Audio Tokenizer
  (Whisper-Large encoder → Mel features → 8-layer RVQ @ 12.5 Hz), audio LLM
  (text+audio interleaved generation with modality-switching special tokens),
  flow-matching audio decoder → 24 kHz waveform. Backbone is Baichuan's own
  ~1.5B-parameter pre-trained LLM continued-pretrained for audio — *substantially*
  smaller than the 7–8B-class peers.
- **Streaming.** Real-time interaction is the explicit design goal; 12.5 Hz
  frame rate chosen to reduce token volume for streaming. No TTFT numbers in
  the paper.
- **System prompt.** Standard chat template via the Baichuan instruction model.
- **On-device.** **Most attractive of this entire list for M-series.** 1.5B
  backbone at fp16 is ~3 GB; at Q4 ~1 GB. Plus Whisper-Large encoder (~1.5 GB
  Q4) and a flow-matching decoder. Total Q4 budget plausibly ~3–4 GB — fits
  comfortably on 8 GB M-series. **However, no MLX/GGUF port published**;
  PyTorch + custom code on the original repo.
- **License.** Apache 2.0 (code and weights).
- **Multilingual.** Bilingual Chinese↔English by design. CoVoST2 S2TT zh↔en
  evaluated. Strong on Chinese dialect ASR.
- **Current state.** Released February 2025. Less aggressively iterated than
  Step-Audio's family; LibriSpeech 8.64 % vs Step-Audio 2's 1.17 % — quality
  lag is significant for English. **Architectural value is the small backbone,
  not state-of-the-art quality.**

Refs: [paper (arXiv 2502.17239)](https://arxiv.org/abs/2502.17239),
[GitHub](https://github.com/baichuan-inc/Baichuan-Audio),
[Instruct HF](https://huggingface.co/baichuan-inc/Baichuan-Audio-Instruct).

## Synthesis

### A. Architectural patterns converging vs diverging

**Converging:**

1. **Audio-tokens-as-language** via RVQ codecs (Mimi, Mistral in-house, EnCodec,
   S3Tokenizer, WavLM-derived). Every full-duplex model uses this.
2. **Streaming-first encoders** with causal / sliding-window attention (Voxtral
   Realtime, Moshi, Qwen2.5-Omni, Covo-Audio). The non-causal Whisper encoder
   is the legacy, not the future.
3. **LLM backbone + audio adapter** (Voxtral on Ministral, Canary-Qwen on
   Qwen3-1.7B, Phi-4-MM on Phi-4-Mini, Qwen3-ASR on Qwen3-Omni, Step-Audio /
   Covo-Audio on Qwen2.5-7B). The LM stays roughly intact; the audio path is an
   adapter. Chinese ecosystem standardised on Qwen2.5-7B as the recipe.
4. **Hierarchical / dual decoders** for joint text+audio output (Moshi
   RQ-Transformer, Qwen2.5-Omni Thinker-Talker, Step-Audio R1.1 Dual-Brain).
5. **Explicit turn-control tokens** (Covo-Audio's THINK / SHIFT / BREAK) as a
   cleaner abstraction than implicit VAD-driven barge-in.

**Diverging:**

- **Whether to interleave generated audio at all.** Voxtral Realtime: no (text
  out only, leaner). Moshi / Qwen-Omni / Gemini Live / Doubao: yes (full-duplex).
  *For dictation, text-out-only is the right bet.*
- **How to expose conditioning.** Control tokens (Canary's 1 162 special
  tokens), text "background" priming (Qwen3-ASR), context biasing lists (≤100
  terms in Voxtral), full chat-style system messages (Canary-Qwen LLM mode,
  Doubao). No standard yet.
- **Backbone size.** Baichuan-Audio's 1.5B backbone is the small-backbone
  outlier. Everyone else converged on 7B+. For a "smallest model that clears
  quality" memory-headroom rule, this is the only entry explicitly aimed at the
  right size class — but quality lag is the catch.

### B. Bilingual / code-switching ASR

Question: *Do Chinese-ecosystem models have **better English ASR** than
English-first models when running with mixed-language input?*

Short answer: **on monolingual English ASR, Step-Audio 2 narrowly beats
Whisper-large-v3 (3.14 % vs 4.18 % avg WER on the StepFun English suite). On
code-switching specifically, the published evidence is incomplete but the
structural argument favours the Chinese-ecosystem models.**

Concrete numbers from primary sources:

| Model | LibriSpeech-clean | English avg | Notes |
|---|---|---|---|
| Whisper-large-v3 | — | 4.18 % | StepFun's reported baseline |
| Step-Audio 2 | 1.17 % | 3.14 % | LS-other 2.42 %, FLEURS-en 3.03 %, CV-en 5.95 % |
| Step-Audio 2-mini (8B) | 1.33 % | — | |
| Baichuan-Audio | 8.64 % | — | Significantly worse than Whisper-v3 — *do not use Baichuan-Audio for English-quality reasons* |
| Covo-Audio | n/a | n/a | Not benchmarked on standard ASR sets in the announcement |

On code-switching: no Chinese-ecosystem audio LLM has published clean
Mandarin↔English CS WER vs Whisper-v3 in the material reachable. Two structural
facts make the argument anyway:

- Whisper-v3 is known to drop significantly on Mandarin↔English CS (it segments
  by language).
- Chinese-ecosystem models train on substantial code-switched data because the
  training distribution naturally contains it.
- Qwen3-ASR (sibling of Qwen3-Omni) explicitly advertises mid-utterance
  language switching.
- Step-Audio 2 and Covo-Audio inherit from Qwen2.5 + Whisper-v3 encoder, so
  they should ≥ Whisper-v3 on CS by construction.

**For OpenQuack's bilingual-dictation case:** if Chinese is in the user mix,
Step-Audio 2 is the strongest open candidate. Whisper-large-v3 stays preferred
for English-only or English-dominant noisy/accented audio (a known Whisper
strength that StepFun's English-only WER win does not necessarily generalise
to in-the-wild mic input).

### C. On-device M-series viability ranked

| Model | Backbone | Total Q4 runtime mem (all components) | MLX/GGUF port today? | Verdict |
|---|---|---|---|---|
| Baichuan-Audio | 1.5B | ~3–4 GB | No | Best fit *on paper*. Smallest backbone. Quality lag (LibriSpeech 8.64 %) is the catch — would not pass our polish-bench English bar. |
| Step-Audio 2-mini | 8B | ~7–9 GB | No | Best quality-feasible candidate. Fits 16 GB with headroom; tight on 8 GB. CUDA-only today; community MLX port would be substantial work. |
| Covo-Audio | 7B | ~7–9 GB | No | Architecturally best for streaming; license needs verification; quality TBD. |
| Voxtral-Mini-4B-Realtime | 4B | ~2.5–4 GB at MLX 4-bit; activations on long audio push real RAM higher | **Yes** (community MLX 4-bit) | **Closest single-model solution.** No system-prompt support yet. |
| Parakeet-TDT-0.6B-v3 | 0.6B | ~2 GB unified-memory floor | **Yes** ([parakeet-mlx](https://github.com/senstella/parakeet-mlx)) | Drop-in WhisperKit replacement. Zero polish capability. |
| Step-Audio R1.1 / R1.1-Realtime | 33B | >24 GB even at Q4 | No | Too large for any M-series target. |
| Doubao / Hunyuan Voice | n/a | n/a | n/a (closed) | Not on-device feasible. |

**Hard takeaway.** No Chinese-ecosystem model is *simultaneously* (a) small
enough for 8 GB M-series, (b) ported to MLX/GGUF, and (c) at quality parity
with Whisper-large-v3 on English. Step-Audio 2-mini is the closest, but a
community MLX port doesn't exist yet. Per the memory-headroom rule, the right
play is to **track Step-Audio 2-mini and Covo-Audio for a future MLX port, not
to bet a pipeline on them today.**

### D. What's feasible for OpenQuack 2026–2027

Three to track, in priority order:

1. **Voxtral-Mini-4B-Realtime + community MLX 4-bit.** Closest single-model
   solution. Ships streaming today, Apache 2.0, multilingual (13). Risks:
   system prompts unsupported (only context biasing); 4 B at 4-bit ≈ 2.5–3 GB
   weights but activations on long audio push real RAM higher — **needs
   measurement on M-series before committing** (memory-headroom rule).
   `localvoxtral` already exists as a reference implementation to benchmark
   against.

2. **Parakeet-TDT-0.6B-v3 via parakeet-mlx.** Drop-in **WhisperKit replacement**,
   not a polish replacement. Smaller (~2 GB unified-memory floor), faster,
   25 languages, streaming-native. Keep Ollama polish on top. Lowest-risk
   migration if WhisperKit ever becomes a constraint; biggest win is RAM
   headroom for the polish LLM.

3. **Canary-Qwen-2.5B successor (or any future SALM that gets streaming +
   multilingual + MLX).** This is the architecture that *would* unify
   transcribe + polish in one model — frozen LLM + audio adapter + two
   operating modes. Today: English-only, non-streaming, CUDA-only. Track NeMo
   releases; this is the most likely shape of the eventual unified model.

**Trade-off vs current WhisperKit + Ollama.** The current stack is two models
worth ~4–6 GB combined, with a clean separation that lets us swap either side.
A single unified streaming + prompted model would cut latency by ~200–500 ms
(no polish round-trip) and simplify state, but loses (a) the ability to A/B
different polish prompts independently, (b) the bench harness already built,
and (c) WhisperKit's 99-language coverage. **Don't migrate yet.**

### E. Where the Chinese-ecosystem changes our decision space

- **Realtime conversational tier (cloud, not on-device).** Doubao Realtime
  Voice is now the most credible non-Western realtime API. Worth including as
  a fallback for Chinese-language dictation if a user explicitly prefers a
  China-hosted endpoint, but it's a product/API integration story, not on-device.
- **On-device dictation tier.** Unchanged from the main 10. Whisper-large-v3 /
  Parakeet still win on portability; the Chinese-ecosystem models are
  watch-list, not pick-list.
- **Bilingual user (Mandarin-English code-switching) tier.** Step-Audio 2
  (cloud-deployed by us, open-weights) is the strongest forward bet. If we
  ever serve a self-hosted dictation endpoint, this is the model that beats
  Whisper-v3 in that scenario. Add it to the SPEC-007-style benchmark suite
  once a Chinese test corpus is in scope.

### F. Research directions worth following

- **Speculative decoding for ASR.** SpecASR (DAC 2025) reports 3.04–3.79×
  speedup; Apple's Speculative Streaming gives 1.8–3.1×. Combination plausibly
  relevant once SALM-style models get streaming.
- **Causal-fied Whisper.** CarelessWhisper (arXiv 2508.12301) and similar
  LoRA-causal-fication papers — incremental wins for the existing Whisper
  ecosystem.
- **Codec compression.** 12.5 Hz / 1.1 kbps (Mimi) is the current low-water
  mark; expect sub-1 kbps codecs that maintain semantic fidelity.
- **Sliding-window-attention encoders trained from scratch** (Voxtral
  Realtime's approach) vs retrofitting non-causal encoders — the former wins
  on quality where compute exists.

### G. Realistic timeline to swap stack

- **Now.** Don't. Voxtral Realtime is closest but unprompted; Canary-Qwen is
  prompted but unstreamed. Picking either trades away half of what we
  currently have.
- **6 months (≈Q4 2026).** Voxtral Realtime v2 or Qwen3-ASR-with-instructions
  plausibly add minimal system-prompt support. At that point: prototype a
  parallel pipeline, run the existing polish bench against both stacks. Risk:
  model maturity (Voxtral Realtime is 3 months old as of May 2026); MLX ports
  are community-maintained and could lag a major release by weeks.
- **12–18 months (≈Q4 2027).** A SALM-pattern model with streaming +
  multilingual + MLX-native is realistic — likely from NVIDIA (Canary-Qwen
  successor), Mistral (Voxtral 3), Alibaba (Qwen3.5-ASR), or Tencent
  (Covo-Audio v2). Migration becomes worth it.
- **Risk to plan around.** The polish prompt is *the* OpenQuack differentiator
  (per the bench work). A unified model that can't cleanly express our prompt
  versions kills the A/B harness. Insist on real chat-template system-prompt
  support before migrating, not just context biasing.

### H. Concrete near-term action

Add **Parakeet-TDT-0.6B-v3 (parakeet-mlx)** as a second STT backend behind a
flag. Low-risk; frees memory for a larger polish model; gives a comparison
point when unified models mature.

## Sources

Primary, ordered roughly by architectural load-bearing-ness:

- [Voxtral-Mini-4B-Realtime HF](https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602) ·
  [Voxtral-Mini-3B HF](https://huggingface.co/mistralai/Voxtral-Mini-3B-2507) ·
  [Voxtral Transcribe 2](https://mistral.ai/news/voxtral-transcribe-2)
- [Moshi paper (arXiv 2410.00037)](https://arxiv.org/html/2410.00037v2) ·
  [Moshi GitHub](https://github.com/kyutai-labs/moshi)
- [Parakeet-TDT-0.6B-v3 HF](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) ·
  [parakeet-mlx](https://github.com/senstella/parakeet-mlx) ·
  [Canary+Parakeet paper](https://arxiv.org/html/2509.14128v2)
- [Canary-Qwen-2.5B HF](https://huggingface.co/nvidia/canary-qwen-2.5b)
- [WhisperKit paper (arXiv 2507.10860)](https://arxiv.org/html/2507.10860v1)
- [Qwen2.5-Omni GitHub](https://github.com/QwenLM/Qwen2.5-Omni) ·
  [Qwen3-ASR HF](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) ·
  [Qwen3-ASR tech report](https://arxiv.org/html/2601.21337v2)
- [Phi-4-Multimodal HF](https://huggingface.co/microsoft/Phi-4-multimodal-instruct)
- [MiniCPM-o GitHub](https://github.com/OpenBMB/MiniCPM-o)
- [GPT-4o Realtime](https://openai.com/index/introducing-gpt-realtime/) ·
  [Gemini 3.1 Flash Live](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-1-flash-live/)
- [Doubao Realtime Voice — Seed](https://seed.bytedance.com/en/realtime_voice)
- [Step-Audio 2 paper (arXiv 2507.16632v3)](https://arxiv.org/html/2507.16632v3) ·
  [Step-Audio 2 GitHub](https://github.com/stepfun-ai/Step-Audio2) ·
  [Step-Audio R1 GitHub](https://github.com/stepfun-ai/Step-Audio-R1)
- [Tencent Covo-Audio (MarkTechPost)](https://www.marktechpost.com/2026/03/26/tencent-ai-open-sources-covo-audio-a-7b-speech-language-model-and-inference-pipeline-for-real-time-audio-conversations-and-reasoning/) ·
  [Covo-Audio GitHub](https://github.com/Tencent/Covo-Audio) ·
  [Covo-Audio-Chat HF](https://huggingface.co/tencent/Covo-Audio-Chat)
- [Baichuan-Audio paper (arXiv 2502.17239)](https://arxiv.org/abs/2502.17239) ·
  [Baichuan-Audio GitHub](https://github.com/baichuan-inc/Baichuan-Audio)
- [SpecASR (DAC 2025)](https://dl.acm.org/doi/10.1109/DAC63849.2025.11132579) ·
  [Apple Speculative Streaming](https://machinelearning.apple.com/research/llm-inference) ·
  [CarelessWhisper](https://arxiv.org/html/2508.12301v1)
- Reference competitor: [localvoxtral macOS dictation app](https://github.com/T0mSIlver/localvoxtral)
