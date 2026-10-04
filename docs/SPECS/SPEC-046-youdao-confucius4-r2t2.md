# SPEC-046 — Youdao Confucius4-R2T2 Engine and CJK Punctuation Normalization

**Document Standard:** ASD-STE100 (Simplified Technical English)
**Status:** Ratified — implemented 2026-10-04
**Owner:** `Sources/OpenQuackKit/Transcription/YoudaoR2T2Engine.swift`, `Sources/OpenQuackKit/Polish/TextPolisher.swift`, `Sources/OpenQuackPlatform/ChunkStitcher.swift`, `bench/engines/youdao_r2t2_runner.py`
**Last updated:** 2026-10-04

## Goal

Enable the NetEase Youdao `Confucius4-R2T2` and `Qwen3-ASR` speech recognition models in `OpenQuack`. Fix Chinese mid-sentence punctuation normalization and streaming chunk stitching across all transcription engines.

## Background

`OpenQuack` users who dictate Mandarin Chinese or Chinese-English code-switched speech encounter three quality problems:

1. Whisper `medium` exhibits a 12.9% Character Error Rate (CER) on 30-second Mandarin benchmark clips (`SPEC-021`).
2. `TextPolisher` only appends a trailing `。` to CJK utterances. It leaves mid-sentence ASCII commas (`,`), periods (`.`), and inter-CJK spaces unnormalized.
3. `StreamingTranscriber` joins 20-second audio chunks with an ASCII space (`" "`). This inserts invalid spaces inside Chinese sentences and fails to deduplicate repeated boundary hanzi.

NetEase Youdao `Confucius4-R2T2` (`netease-youdao/Confucius4-R2T2`, built on `Qwen3-ASR-1.7B`) achieves 3.48% to 7.30% CER on Mandarin streaming benchmarks. Its upstream `r2t2/r2t2_asr.py` module also defines a deterministic, context-aware punctuation normalizer (`_normalize_punct_by_context`).

## Architecture and Mechanism

### 1. Context-Aware CJK Punctuation Normalization (`TextPolisher`)

Add `normalizeCJKPunctuation: Bool` to `TextPolisher.Settings` (default `true` in `.standard`, `false` in `.off`).

When `normalizeCJKPunctuation` is `true`, `TextPolisher` executes two deterministic passes:

1. **Inter-CJK Whitespace Removal:** Remove horizontal whitespace between two CJK characters, or between a CJK character and CJK full-width punctuation (`，。！？；：、（）《》「」『』`).
2. **Context-Aware Punctuation Width Conversion:** Port `_normalize_punct_by_context` from `r2t2/r2t2_asr.py`:
   - Inspect the preceding non-whitespace character before each punctuation mark in `, . ! ? ; : ( )` and `， 。 ！ ？ ； ： （ ）`.
   - When the preceding character is a CJK character, convert half-width `, . ! ? ; : ( )` to full-width `， 。 ！ ？ ； ： （ ）`.
   - Remove any trailing ASCII space immediately after a newly converted full-width punctuation mark when the next character is CJK.
   - Preserve ASCII decimal points and version numbers between digits (for example, `3.14` or `v2.0`).

### 2. CJK-Aware Streaming Chunk Stitching (`ChunkStitcher`)

Extract chunk-stitching logic from `StreamingTranscriber` into `public enum ChunkStitcher` inside `Sources/OpenQuackPlatform/ChunkStitcher.swift`:

- When both the trailing character of the accumulated transcript and the leading character of the next chunk are CJK (or trailing CJK punctuation followed by CJK):
  - Join the chunks with an empty separator (`""`) instead of an ASCII space (`" "`).
  - Deduplicate 1 to 3 overlapping CJK characters at the chunk boundary (for example, `"今天天气"` + `"气真好"` becomes `"今天天气真好"`).
- When either boundary character is Latin or ASCII:
  - Preserve the existing `" "` separator and case-insensitive single-word deduplication.

### 3. `YoudaoR2T2Engine` and Python Subprocess Runner

Add `case youdao` to `EngineKind` (`Sources/OpenQuackKit/Transcription/TranscriptionEngine.swift`) and implement `YoudaoR2T2Engine` (`Sources/OpenQuackKit/Transcription/YoudaoR2T2Engine.swift`):

- **Model Resolution:**
  - Map `"confucius4-r2t2"`, `"r2t2"`, `"youdao"`, or `"default"` to `"netease-youdao/Confucius4-R2T2"`.
  - Map `"qwen3-asr-1.7b"` or `"qwen3-asr"` to `"Qwen/Qwen3-ASR-1.7B"`.
  - Map `"qwen3-asr-0.6b"` to `"Qwen/Qwen3-ASR-0.6B"`.
  - Pass custom HuggingFace repository IDs or local filesystem paths through unchanged.
- **Subprocess Protocol (`bench/engines/youdao_r2t2_runner.py`):**
  - Start one persistent Python subprocess per engine instance.
  - Send `LOAD <model_id>` on startup and wait for `READY`.
  - Send `TRANSCRIBE\t<wav_path>\t<language_or_->\t<context_or_->` for each audio file.
  - Read `OK\t<audio_seconds>\t<detected_language>\t<text>` from standard output.
  - Support three backend loaders in priority order:
    1. `r2t2` (`R2T2ASR` from `netease-youdao/Confucius4-R2T2` when installed).
    2. `qwen_asr` (`Qwen3ASRModel.from_pretrained` for macOS MPS/CPU or CUDA).
    3. `transformers` (`AutoModelForSpeechSeq2Seq` / `AutoProcessor` fallback).
- **CLI, Bench, and App Integration:**
  - Accept `--engine youdao` (and aliases `r2t2`, `qwen3-asr`) in `openquack-cli` and `openquack-bench`.
  - Add `"Youdao Confucius4-R2T2 (local Python, experimental)"` (`tag("youdao")`) to the `Transcription` picker in `SettingsView.swift` and `OpenQuackApp.swift`.

## License and Privacy Contract

- **No Bundled Weights:** `Confucius4-R2T2` weights use the NetEase Youdao Model Use License Agreement. `OpenQuack` never bundles or redistributes these weights.
- **Opt-In Local Execution:** WhisperKit remains the default engine. `YoudaoR2T2Engine` runs locally on the user's Mac only when the user selects it.
- **No Network Telemetry:** `YoudaoR2T2Engine` performs zero runtime network calls after HuggingFace or ModelScope weight caching completes.

## Acceptance Criteria

- [x] `TextPolisher.polish` converts half-width `, . ! ? ; : ( )` after CJK characters to full-width `， 。 ！ ？ ； ： （ ）` (unit tests in `TextPolisherTests.swift`).
- [x] `TextPolisher.polish` removes spaces between adjacent CJK characters while preserving spaces around English words and decimal numbers (unit tests in `TextPolisherTests.swift`).
- [x] `ChunkStitcher.stitch` joins CJK chunks without inserting ASCII spaces and deduplicates 1 to 3 overlapping boundary CJK characters (unit tests in `ChunkStitcherTests.swift`).
- [x] `ChunkStitcher.stitch` preserves space-separated joining and case-insensitive single-word deduplication for Latin chunks (unit tests in `ChunkStitcherTests.swift`).
- [x] `YoudaoR2T2Engine` resolves model aliases, parses `<asr_text>` language tags, formats subprocess commands, and parses runner responses (unit tests in `YoudaoR2T2EngineTests.swift`).
- [x] `bench/engines/youdao_r2t2_runner.py` compiles cleanly and passes protocol self-tests.
- [x] `swift build` and `swift test` pass on macOS CI (`macos-15`).
