# OpenQuack benchmarks

Living document. We add a row to the host matrix every time someone runs the bench and submits the result. Numbers below are real, reproducible from `bench/out/<host-tag>/`, and supersede earlier preliminary runs.

## TL;DR (M4 / 16 GB)

> **WhisperKit `medium` is the recommended v2 default for English on 16 GB+ Macs.**
> 2.6 % WER on LibriSpeech, 1.3 % on multi-voice English TTS, 6.3 % on noise-augmented speech.
> RTF 0.22–0.31× (≥3× realtime). Peak RSS 197 MB. Cold start 27 s (cache miss only — once per Mac).

For 8 GB Macs, `whisperkit small` is the practical choice (165 MB RSS, 4.1 % LibriSpeech WER, but degrades to 11 % on noise).

> **⚠️ Update (v2.0.0-alpha.17): the multilingual auto-detect numbers below are pre-fix.** The catastrophic >100 % WER was a configuration bug, not a model limitation — WhisperKit's `DecodingOptions.detectLanguage` defaults to `false` (it derives from `!usePrefillPrompt`, and prefill is on by default), so on the auto path the decoder never attempted detection and silently translated non-English speech to English. Enabling detection on the auto path (SPEC-021, [#63](https://github.com/larryxiao/openquack/pull/63)) drops WhisperKit `medium` multilingual auto-detect from **253.2 % → 16.7 % WER / 156.0 % → 3.7 % CER** — matching Lightning. English is unchanged (LibriSpeech 2.6 %). The full matrix below has **not** been re-benched (only `medium` was re-measured post-fix); treat the multilingual rows as the pre-fix baseline. See the [Multilingual](#multilingual-auto-detect-12-clips-zhjakoesfrde--2) section for the after table.

## Hosts

| Host tag | Chip | GPU | Memory | macOS | Date |
|---|---|---:|---:|---|---|
| `M4-16GB` | Apple M4 | 8-core | 16 GB | 15.6 (24G84) | 2026-04-26 |

## Methodology

- **Engines**: WhisperKit (`argmaxinc/argmax-oss-swift` 0.18+, primary) and Lightning (`lightning-whisper-mlx` 0.0.10 via long-running Python subprocess, comparison-only).
- **Corpus**: 177 WAV clips, 16 kHz mono PCM, across five buckets:
  - `librispeech/` — 20 real human read speech clips from LibriSpeech `dev-clean` (CC BY 4.0, openslr.org/12). The closest thing in this set to real-world dictation accuracy.
  - `voices/` — 20 multi-accent English TTS (Samantha US, Daniel UK, Karen AU, Fred US-robotic, 5 sentences each).
  - `noisy/` — 120 noise-augmented clips (the 20 voices × white + pink noise × 5 / 10 / 20 dB SNR).
  - `multilingual/` — 12 native-language clips (zh, ja, ko, es, fr, de × 2).
  - `short/` — 5 single-voice TTS sanity-check clips.
- **Models**: `tiny, base, small, medium, distil-large-v3`. (`large-v3-turbo` is unavailable in either engine under that name; tracked as an open question.)
- **Metrics**:
  - **WER** — Levenshtein over normalised whitespace tokens.
  - **CER** — same on characters. More meaningful for CJK; we report it everywhere for comparison.
  - **RTF** — wall_seconds ÷ audio_seconds.
  - **Cold start** — wall-clock from engine init to first transcribe ready (includes cache-miss download).
  - **Peak RSS** — sampled at 100 ms via `mach_task_basic_info`.
- **Auto-detect**: language was *not* hinted at the engine; auto-detect was used. This is the app's default path. (In the original runs this surfaced a config bug that made WhisperKit translate non-English to English; SPEC-021/alpha.17 fixes it — see the Multilingual section.)

## Per-bucket results — `M4-16GB` (2026-04-26)

### LibriSpeech (real human speech, English read) — 20 clips

| Engine | Model | WER | CER | RTF | Wall (avg) |
|---|---|---:|---:|---:|---:|
| whisperkit | `medium` | **2.6 %** | 1.3 % | **0.22×** | 1.98 s |
| lightning | `medium` | 2.8 % | 1.3 % | 0.34× | 2.47 s |
| whisperkit | `distil-large-v3` | 3.2 % | 1.3 % | 0.12× | 0.89 s |
| lightning | `distil-large-v3` | 3.2 % | 1.3 % | 0.48× | 3.27 s |
| whisperkit | `small` | 4.1 % | 1.7 % | 0.05× | 0.50 s |
| lightning | `small` | 4.6 % | 2.3 % | 0.10× | 0.74 s |
| lightning | `base` | 5.6 % | 2.8 % | 0.04× | 0.29 s |
| whisperkit | `base` | 5.9 % | 2.3 % | 0.02× | 0.20 s |
| whisperkit | `tiny` | 7.2 % | 3.0 % | 0.01× | 0.13 s |
| lightning | `tiny` | 8.7 % | 4.4 % | 0.02× | 0.18 s |

**Read:** 2.6 % WER on real human read speech is solid — close to what dictation feels like in practice. `medium` outperforms `distil-large-v3` here; `small` is acceptable but visibly less accurate.

### Voices (multi-accent English TTS) — 20 clips

| Engine | Model | WER | CER | RTF |
|---|---|---:|---:|---:|
| whisperkit | `medium` | **1.3 %** | 0.3 % | 0.31× |
| lightning | `medium` | 2.0 % | 0.4 % | 0.63× |
| whisperkit | `small` | 2.7 % | 1.2 % | 0.09× |
| lightning | `small` | 3.1 % | 1.6 % | 0.19× |
| whisperkit | `distil-large-v3` | 5.3 % | 0.7 % | 0.23× |
| lightning | `distil-large-v3` | 5.3 % | 0.7 % | 0.97× |
| whisperkit | `base` | 5.6 % | 2.1 % | 0.04× |
| lightning | `base` | 9.4 % | 3.7 % | 0.06× |
| lightning | `tiny` | 12.9 % | 5.1 % | 0.04× |
| whisperkit | `tiny` | 15.0 % | 5.8 % | 0.02× |

### Noisy (white/pink × 5/10/20 dB SNR over voices) — 120 clips

| Engine | Model | WER | CER | RTF |
|---|---|---:|---:|---:|
| whisperkit | `medium` | **6.3 %** | 2.7 % | 0.31× |
| lightning | `medium` | 6.3 % | 2.9 % | 0.63× |
| whisperkit | `distil-large-v3` | 9.4 % | 3.5 % | 0.23× |
| lightning | `distil-large-v3` | 10.0 % | 3.7 % | 0.98× |
| whisperkit | `small` | 11.4 % | 5.5 % | 0.10× |
| lightning | `small` | 11.8 % | 5.7 % | 0.19× |
| lightning | `base` | 22.8 % | 12.5 % | 0.06× |
| whisperkit | `base` | 24.0 % | 13.2 % | 0.04× |
| whisperkit | `tiny` | 27.3 % | 15.8 % | 0.03× |
| lightning | `tiny` | 28.7 % | 16.5 % | 0.04× |

**Read:** Once you add real-world noise, `medium` pulls clearly ahead of `small`. `tiny` and `base` collapse — they're not viable in any non-pristine environment.

### Multilingual (auto-detect, 12 clips: zh/ja/ko/es/fr/de × 2)

**Pre-fix (alpha.16 and earlier):**

| Engine | Model | WER | CER |
|---|---|---:|---:|
| lightning | `medium` | **16.7 %** | 3.7 % |
| lightning | `small` | 29.2 % | 5.0 % |
| lightning | `base` | 52.8 % | 8.1 % |
| lightning | `tiny` | 23.7 % | 8.1 % |
| whisperkit | `small` | 198.6 % | 107.8 % |
| whisperkit | `medium` | 253.2 % | 156.0 % |
| whisperkit | `base` | 284.3 % | 170.0 % |
| whisperkit | `tiny` | 303.3 % | 146.6 % |
| whisperkit | `distil-large-v3` | 231.9 % | 122.0 % |
| lightning | `distil-large-v3` | 352.6 % | 130.2 % |

**Post-fix (alpha.17, SPEC-021 — `medium` re-benched):**

| Engine | Model | WER | CER | Δ vs pre-fix |
|---|---|---:|---:|---|
| whisperkit | `medium` | **16.7 %** | **3.7 %** | −236 pp WER / −152 pp CER |

**Read:** The pre-fix WhisperKit numbers were not a model limitation — auto-detect was *disabled* in our `DecodingOptions` (see the TL;DR callout). With detection enabled (SPEC-021, [#63](https://github.com/larryxiao/openquack/pull/63)), WhisperKit `medium` now matches Lightning `medium` exactly (16.7 % WER / 3.7 % CER): every clip detects its true language (de/es/fr/ja/ko/zh) instead of being mislabelled `en` and translated. zh_001 went 350 % → 0.0 % WER. A long-form Mandarin clip (30.8 s) detects `zh` at 12.9 % CER (most of that is number normalisation, `三点` → `3点`, not recognition error). The other WhisperKit sizes have not been re-benched but are expected to improve similarly; PRs welcome. **Auto-detect is now a sound default**; an explicit Settings → Language picker remains available and is zero-overhead when set.

### Cold start + memory

| Engine | Model | Cold start | Peak RSS |
|---|---|---:|---:|
| lightning | `tiny` | 1.92 s | 53 MB |
| lightning | `small` | 1.10 s | 37 MB |
| lightning | `medium` | 1.17 s | 27 MB |
| lightning | `distil-large-v3` | 1.23 s | 23 MB |
| whisperkit | `tiny` | 6.06 s | 103 MB |
| whisperkit | `small` | 22.41 s | 165 MB |
| whisperkit | `medium` | 27.44 s | 197 MB |
| whisperkit | `distil-large-v3` | 23.12 s | 111 MB |

Cold-start values include first-run model download. Warm-cache loads are 1–10 s typically.

## Recommendation matrix

| Memory tier | Default model | Why |
|---|---|---|
| 8 GB | `whisperkit small` | 4.1 % WER on real speech, 11 % on noisy (acceptable), 165 MB peak — leaves 6+ GB for the agent backend |
| **16 GB (this Mac)** | **`whisperkit medium`** | 2.6 % LibriSpeech WER, 1.3 % multi-voice, 6.3 % noisy. RTF 0.22–0.31× (≥3× realtime), 197 MB. Best balance. |
| 24+ GB | `whisperkit medium` (same) | No 24 GB host benched yet; revisit when one ships data |

**Engine default:** WhisperKit. Native Swift, zero Python sidecar, faster on Apple Silicon. Lightning stays as the bench baseline.

**Multilingual users:** auto-detect now works (alpha.17, SPEC-021). Setting Settings → Language explicitly is still supported and is zero-overhead — useful if you dictate in one fixed language and want to skip the detection pass entirely.

## Open questions / next runs

1. **`large-v3-turbo`** — neither engine accepts the obvious model name. Discover the right one via `WhisperKit.fetchAvailableModels()` and rerun. Turbo's promise is "approaches large-v3 quality at small-ish cost"; if real, it could displace `medium` as the default.
2. **Re-bench the full multilingual matrix post-fix.** SPEC-021 re-measured only WhisperKit `medium` (253 % → 16.7 %). The other sizes (`tiny`/`base`/`small`/`distil`) still show pre-fix numbers above and should be re-run with detection enabled.
3. **Real-world noise types.** Synthetic white/pink is a baseline; the M3 corpus should add curated environmental clips (cafe babble, traffic, keyboard) under permissive licensing.
4. **Cross-host coverage.** 8 GB and 24+ GB tiers are still empty. M1, M2, M3 results all welcome — see `bench/CONTRIBUTING.md`.
5. **Warm-cache cold-start.** This run measures cache-miss cold-start. Add a second run that pre-warms each model and reports the warm cold-start (it's the one users feel after the first launch).

## Quality + responsiveness improvements that this data motivates

These feed into M2/M3 specs:

- **Pre-warm the chosen model on app launch.** 27 s cache-miss cold-start is the worst number; after that it's ~5–10 s warm. Hide it behind onboarding's "first dictation test" and the user never sees it.
- **VAD-trimmed audio** at the recorder boundaries — drop leading/trailing silence before transcribe; smaller window = lower latency.
- **User language preference** in Settings → General — shipped; now optional (auto-detect works as of alpha.17) but still speeds up transcription by skipping the detection pass when you dictate in one fixed language.
- **Custom-words bias.** Power users and proper-noun-heavy domains (legal, medical, dev) deserve `initial_prompt` injection from a user dictionary.
- **Streaming.** WhisperKit's `transcribeWithResults` supports a callback. M3 spec should expose progressive transcripts to the overlay so longer utterances feel snappier.

## Reproducing

From the repo root, on the `v2` branch:

```sh
# Synthetic corpus (multi-voice TTS + multilingual sentences).
bash bench/corpus/fetch.sh

# Real human speech (~337 MB one-time download, openslr.org).
N=20 bash bench/corpus/fetch_librispeech.sh

# Noise-augmented variants (white + pink × 5/10/20 dB SNR).
.venv/bin/python bench/corpus/mix_noise.py --source bench/corpus/voices

# Run the matrix.
swift run openquack-bench \
  --engines whisperkit,lightning \
  --models tiny,base,small,medium,distil-large-v3 \
  --corpus bench/corpus \
  --verbose
```

Output: `bench/out/<host-tag>/{report.md,report.csv,host.json}`. Submit yours via PR per `bench/CONTRIBUTING.md`.
