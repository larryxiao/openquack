# Research Note: NetEase Youdao Confucius4-R2T2 Streaming ASR

**Document Standard:** ASD-STE100 (Simplified Technical English)
**Status:** Research Note (Implemented in [SPEC-046](../SPECS/SPEC-046-youdao-confucius4-r2t2.md))
**Date:** 2026-10-04
**Scope:** Evaluation of NetEase Youdao `Confucius4-R2T2` for `OpenQuack` transcription, Chinese punctuation normalization, and CJK chunk stitching.

## 1. Executive Summary

`Confucius4-R2T2` is a 1.7B-parameter streaming automatic speech recognition (ASR) model from NetEase Youdao. The model uses the `Qwen3-ASR` architecture (`Qwen/Qwen3-ASR-1.7B`).

`OpenQuack` adopts `Confucius4-R2T2` and `Qwen3-ASR` as an opt-in local engine (`YoudaoR2T2Engine`) under `SPEC-046`. `OpenQuack` also ports the Youdao context-aware CJK punctuation normalizer into `TextPolisher` and fixes CJK chunk stitching in `ChunkStitcher`.

## 2. Model Architecture and Streaming Mechanism

Primary source: [github.com/netease-youdao/Confucius4-R2T2](https://github.com/netease-youdao/Confucius4-R2T2) (`README.md`, `r2t2/r2t2_asr.py`, `MODEL_LICENSE`).

- **Base Architecture:** `Confucius4-R2T2` fine-tunes `Qwen3-ASR` (1.7B parameters). It loads weights through `qwen_asr.inference.qwen3_asr.Qwen3ASRModel`.
- **Longest Stable Prefix (LSP):** The training recipe uses forced alignment and token-level audio segmentation. Streaming inference emits append-only tokens and never revises committed text.
- **Chunk Latency:** The streaming decoder supports chunk sizes from 80 ms to 2,000 ms. Vendor benchmarks report 200 ms to 600 ms average latency.
- **Supported Languages:** The model targets Mandarin Chinese (`zh`), English (`en`), and Chinese-English code-switching. It also supports `fr`, `de`, `it`, `ja`, `ko`, `pt`, `ru`, `es`, and `ar`.
- **Encoder Cost on macOS:** The `streaming_transcribe()` method appends each audio chunk to `audio_accum` and re-encodes the full prefix. Encoder compute grows linearly with utterance duration.

## 3. Vendor Benchmark Data

The table below lists vendor-reported Word Error Rate (WER % for English) and Character Error Rate (CER % for Chinese). Lower values indicate higher accuracy. The `※` symbol marks pseudo-streaming decoders that revise prior tokens.

| Dataset | Qwen3-ASR※ (2 s) | Qwen3-ASR (160 ms) | **Confucius4-R2T2 (160 ms)** | Nemotron (160 ms) | Voxtral (160 ms) | Commercial B※ |
|---|---|---|---|---|---|---|
| LS-clean (en) | 1.67 | 22.30 | **2.13** | 3.71 | 2.49 | 1.25 |
| LS-other (en) | 3.54 | 25.74 | **4.88** | 8.27 | 7.15 | 2.48 |
| AMI (en) | 9.25 | 24.79 | **11.37** | 18.11 | 15.94 | 8.44 |
| TED-LIUM (en) | 2.33 | 19.18 | **3.34** | 5.11 | 4.60 | 3.30 |
| Wenet-net (zh) | 4.94 | 19.79 | **5.87** | 24.70 | 23.53 | 4.79 |
| Wenet-meeting (zh) | 5.97 | 20.38 | **7.27** | 20.18 | 60.54 | 3.75 |
| SPEECHIO-06 (zh) | 6.10 | 24.50 | **7.30** | 22.52 | 32.16 | 5.34 |
| CN-RealSI (zh) | 3.34 | 39.72 | **3.48** | 11.52 | 8.74 | 3.64 |

Key technical observations:

1. At 160 ms chunk size, `Confucius4-R2T2` reduces Chinese CER by 3x to 11x compared to unmodified `Qwen3-ASR`.
2. At 2 s chunk size, `Qwen3-ASR` achieves slightly lower CER/WER than `Confucius4-R2T2` at 160 ms.
3. Both `Confucius4-R2T2` and `Qwen3-ASR-1.7B` outperform Whisper `medium` (12.9% CER on `OpenQuack` 30 s Mandarin clips).

## 4. Chinese Punctuation and Sentence Segmentation Analysis

### 4.1 How Youdao R2T2 Normalizes Punctuation

`Confucius4-R2T2` implements two post-processing functions in `r2t2/r2t2_asr.py`:

- **Language Tag Extraction (`parse_language_output`):** The decoder emits a prefix tag such as `language Chinese<asr_text>`. The parser strips this prefix and extracts the transcript body.
- **Context-Aware Punctuation Normalization (`_normalize_punct_by_context`):** The decoder can emit mixed ASCII and full-width punctuation during code-switched speech. The normalizer inspects the preceding non-whitespace character for each punctuation mark:
  - If the preceding character is a CJK ideograph (`\u4e00`–`\u9fff`), the function maps `, . ! ? ; : ( )` to `， 。 ！ ？ ； ： （ ）`.
  - If the preceding character is ASCII alphanumeric or a quote, the function maps `， 。 ！ ？ ； ： （ ）` to `, . ! ? ; : ( )`.

### 4.2 Root Causes of Chinese Punctuation Defects in OpenQuack

Before `SPEC-046`, `OpenQuack` had three defects in Chinese punctuation and sentence segmentation:

1. **Mid-Sentence Half-Width Punctuation (`TextPolisher.swift`):** `TextPolisher` appended `。` only to the final character of a CJK utterance. It did not convert mid-sentence ASCII commas (`,`), periods (`.`), question marks (`?`), or exclamation marks (`!`) after CJK characters.
2. **Inter-CJK Whitespace (`TextPolisher.swift`):** Whisper and Qwen decoders occasionally emit ASCII spaces between Chinese clauses or after half-width commas. `TextPolisher` collapsed multiple spaces into one ASCII space instead of removing spaces between CJK characters.
3. **Chunk-Boundary Spaces and Duplicate Hanzi (`StreamingTranscriber.swift`):** `StreamingTranscriber.stitchChunks` joined all 20-second chunks with an ASCII space (`" "`). It also split boundary tokens by whitespace to deduplicate overlap. Chinese text does not use word spaces, so `stitchChunks` inserted invalid spaces (`"…材料。 蘋果公司…"`) and failed to deduplicate repeated boundary hanzi.

### 4.3 Resolution in SPEC-046

`SPEC-046` fixes all three defects directly in `OpenQuack`:

1. `TextPolisher` now includes `normalizeCJKPunctuation` (enabled by default in `Settings.standard`). It converts half-width punctuation after CJK characters to full-width Chinese punctuation and removes whitespace between CJK characters.
2. `ChunkStitcher` (`Sources/OpenQuackPlatform/ChunkStitcher.swift`) replaces the private `stitchChunks` helper. It joins adjacent CJK chunks without ASCII spaces and deduplicates repeated boundary CJK characters.
3. `YoudaoR2T2Engine` and `bench/engines/youdao_r2t2_runner.py` integrate `Confucius4-R2T2` and `Qwen3-ASR` with native punctuation normalization.

## 5. License Constraints

The `Confucius4-R2T2` source code uses the Apache-2.0 license. The model weights use the **NetEase Youdao Model Use License Agreement** (`MODEL_LICENSE`):

- Commercial use is free below 100 million Monthly Active Users (MAU) and below RMB 1 billion annual revenue.
- Section 3.4(c) prohibits using model outputs to train or distill non-R2T2 commercial models.
- Redistribution of weights or quantized derivatives requires attaching the license agreement and disclaimer.

Compliance rule for `OpenQuack`:

- Never bundle or redistribute `Confucius4-R2T2` weights in the signed `.app` or DMG.
- Keep WhisperKit as the default engine.
- Provide `YoudaoR2T2Engine` (`--engine youdao` and Settings opt-in) so users download weights directly from HuggingFace or ModelScope.
- Support Apache-2.0 `Qwen/Qwen3-ASR-1.7B` and `Qwen/Qwen3-ASR-0.6B` through the same engine runner.

## 6. References

- Upstream repository: https://github.com/netease-youdao/Confucius4-R2T2
- Qwen3-ASR technical report: https://arxiv.org/abs/2601.21337
- Implementation specification: [`SPEC-046`](../SPECS/SPEC-046-youdao-confucius4-r2t2.md)
