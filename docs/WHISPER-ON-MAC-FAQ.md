# Whisper on Mac: practical FAQ

Findings from running OpenQuack's bench (5 model sizes × 2 engines × 177 clips on an M4 / 16 GB host) plus from shipping a real Mac dictation app on top of WhisperKit. Question-led; useful for anyone integrating Whisper on Apple Silicon, not just OpenQuack users.

If you spot something wrong, [open an issue](https://github.com/larryxiao/openquack/issues/new/choose) — we'd rather fix it than leave bad info up. Numbers are reproducible from [`bench/CONTRIBUTING.md`](../bench/CONTRIBUTING.md).

## Why does Whisper output English when I speak Spanish (or another non-English language)?

**If you saw this in OpenQuack: it's fixed as of v2.0.0-alpha.17.** This turned out to be a one-line configuration bug, not a Whisper limitation — and the fix is worth knowing if you're integrating WhisperKit yourself.

The symptom: with auto-detect on, every WhisperKit configuration produced **>100% WER on a 2-second non-English clip** — the model emitted a fluent English translation of audio it never transcribed. Lightning-Whisper-MLX, on the *same* Whisper weights, got 16.7% WER on the same audio. Same weights, very different output, so it had to be the decoder config.

The cause: **WhisperKit's `DecodingOptions.detectLanguage` defaults to `false`.** It derives from `!usePrefillPrompt`, and prefill is on by default, so unless you set it yourself, the decoder skips language detection entirely — it just prefills the English language token and decodes (which, on non-English audio, means *translating*). Lightning runs a language-detect pass by default, which is the entire difference. (Verified in `argmax-oss-swift` 0.18: `Configurations.swift` init, consumed at `TranscribeTask.swift`'s `if … options.language == nil, options.detectLanguage` guard.)

**The fix, if you're integrating WhisperKit:** when you have no pinned language, set `options.detectLanguage = true`. The in-decoder detect reuses the already-computed encoder output, so it's nearly free (no second audio encode). With it on, WhisperKit `medium` drops from **253% → 16.7% WER** on our multilingual bench — matching Lightning. In OpenQuack this is automatic; an explicit Settings → Language picker remains available and is zero-overhead when you'd rather skip detection (e.g. you only ever dictate in one language).

Reproducer: `bench/corpus/multilingual/` plus `swift run openquack-bench --models medium --corpus bench/corpus/multilingual` (before/after the fix). See SPEC-021 and [#63](https://github.com/larryxiao/openquack/pull/63).

## What Whisper model should I pick for my Mac?

Per our M4 / 16 GB bench (full matrix in [`docs/BENCHMARKS.md`](BENCHMARKS.md)):

| Memory tier | Recommended | Why |
|---|---|---|
| 8 GB | `small` | `medium` works but pressure shows up under real load (browser + Slack + dictation). `tiny` and `base` collapse under noise. |
| 16 GB | `medium` | Best accuracy/speed/memory tradeoff on our bench. ~2.6% WER on LibriSpeech, RTF 0.22-0.31×, 197 MB peak RSS. |
| 24 GB+ | `medium` or `large-v3` | `large-v3` is more accurate; `medium` is fast enough that the marginal gain may not be worth the cold-start cost. |

We don't have first-hand bench data for non-M4 Macs yet; if you have an M1/M2/M3 or Intel Mac, the bench script ([`bench/CONTRIBUTING.md`](../bench/CONTRIBUTING.md)) takes ~10 minutes and the resulting PR helps everyone choosing a model.

**What about distil-large-v3?** Faster than `medium`, but consistently less accurate in our bench: 3.2% vs 2.6% on LibriSpeech, and a much wider gap on multi-voice TTS (5.3% vs 1.3%). The "distilled ≈ same quality, much faster" marketing didn't hold up. Useful when latency dominates and the speech is clean; not a free upgrade.

**What about `tiny` and `base`?** Their clean-speech numbers (5-7% WER) are misleading; they collapse on noise (24-28% WER). Not viable outside a quiet room. They're useful for testing pipelines, not for production dictation.

## When does streaming actually help?

Streaming chunks the audio while recording so each chunk gets transcribed during the recording. When the user stops, only the trailing chunk needs to finish — wait time post-stop is roughly constant in clip length above the chunk threshold.

From our bench (`bench/out/stream/M4-16GB-paced/report.md`):

| Length | Offline wall | Streaming post-stop | Speedup |
|---|---:|---:|---:|
| 2-min | 13.76 s | 2.41 s | 5.7× |
| 5-min | 34.44 s | 2.77 s | 12.4× |

The crossover is somewhere around 30 seconds — for utterances shorter than that, the offline path is faster end-to-end (no chunk-stitching overhead), and the user-perceived wait is short either way. For long-form (anything past ~60 seconds), streaming wins decisively because the offline path's wait scales linearly with clip length while streaming's stays constant.

If you're transcribing recorded files (not live audio), streaming doesn't help — offline is fine and simpler. Streaming is specifically the win for "user dictates, then stops, expects fast paste."

The implementation contract is in [`docs/SPECS/SPEC-012-streaming-transcription.md`](SPECS/SPEC-012-streaming-transcription.md). The chunk size, overlap, and re-emission strategy matter — naïve "transcribe each chunk independently" produces bad seams. Argmax's "LocalAgreement" decoder strategy handles this well.

## Why does the first transcription take so much longer than subsequent ones?

Cold start on Apple Silicon is dominated by:
1. **CoreML model load** — a ~1.5 GB `medium` model loads via mmap and the working set faults in over the first few seconds. Subsequent inferences hit warm pages.
2. **ANE warmup** — the first compute on the Neural Engine is typically slower than the steady state.
3. **First decoder pass** — KV-cache initialization and beam-search setup.

In our experience, the first transcription takes ~10-30 s even on `medium`; the next one is sub-second on the same audio length. This is normal Apple Silicon behavior, not a bug. Workaround: warm the model on app launch (OpenQuack does this — see `AppDelegate.warmTranscriber`), so by the time the user presses the hotkey, the engine is ready.

**About RSS:** `medium` is ~1.5 GB on disk but peak RSS during transcription is ~200 MB. That's mmap doing its job — the resident set tracks active pages, not file size. Don't be alarmed by the disk number; the active memory cost is much smaller.

## How do I prevent silence-induced hallucinations?

Whisper occasionally produces fluent text for silent audio — e.g. "Thanks for watching!" or "Subtitles by [name]" from Whisper's training data leaking through. Causes and mitigations:

1. **VAD prefilter.** Strip silence before sending to Whisper. OpenQuack's auto-stop-after-silence uses a simple energy threshold; production systems use Silero VAD or similar. Strip leading and trailing silence; on long clips, strip mid-recording silence too.
2. **`no_speech_threshold` parameter.** Whisper exposes a probability threshold below which it returns empty. Default is around 0.6; you can raise it to 0.8 or higher if hallucinations are frequent.
3. **`logprob_threshold` parameter.** When the model's average log probability for a chunk drops below this, treat the output as suspect.
4. **Clip-length lower bound.** Audio shorter than ~0.5 s often produces nonsense regardless. Reject sub-half-second clips at the application layer.

Whisper-mini-tier models hallucinate more under silence than the larger ones; if you're seeing this on `tiny` or `base`, model size may be a faster fix than parameter-tuning.

## Can I bias Whisper toward specific words (proper nouns, jargon, project names)?

Yes — Whisper's `initial_prompt` parameter accepts a string that biases decoding toward those tokens. WhisperKit exposes this via `decodingOptions.prefixTokens` (or similar; verify the current API). Practical guidance from running this in production:

- **What works:** seed the prompt with proper nouns, technical terms, and project names that show up in the user's domain. e.g. for a Mac dev: "Claude Code, WhisperKit, Apple Silicon, MLX". Whisper biases toward these tokens during decoding.
- **What doesn't work:** dumping a paragraph of text expecting Whisper to "learn" — the prompt is decoder bias, not training. Useful at the word/phrase level, not the sentence level.
- **Length:** keep the prompt short (<200 tokens). Longer prompts dilute the bias.
- **Order:** Whisper biases more toward earlier tokens in the prompt — put the most-important domain terms first.

OpenQuack exposes a custom dictionary (Settings → General → Custom dictionary) that maps to `initial_prompt`; the implementation is in [`Sources/OpenQuackKit/Transcription/`](../Sources/OpenQuackKit/Transcription/).

## Why is my streaming bench number different from yours?

Bench numbers are sensitive to:
- **Hardware** — M4 is faster than M3 is faster than M2 is faster than M1. Intel Macs are much slower.
- **Memory pressure** — peak RSS is reported, but the latency you measure depends on what else is running. Closing other heavy apps before benching matters.
- **Thermals** — sustained transcription on long clips throttles when the chassis heats up. Run the bench from cold (let the machine sit for 5 min before starting) for comparable numbers.
- **Audio characteristics** — speech speed, accent, background noise all affect WER and RTF. Our corpus has 177 clips spanning real human speech (LibriSpeech), multi-voice TTS, six non-English languages, and 120 noise-augmented variants at 3 SNRs to cover the range.
- **Whisper engine** — `WhisperKit` and `Lightning-Whisper-MLX` get different numbers on the same weights because of decoder differences.

If your numbers differ materially, the most useful thing is to PR your `bench/out/<host-tag>/` directory back. We aggregate them into [`docs/BENCHMARKS.md`](BENCHMARKS.md).

## Where to learn more

- **WhisperKit (Argmax)**: https://github.com/argmaxinc/WhisperKit — the engine. Their issues are the right place for bug reports specific to their decoder.
- **OpenAI Whisper**: https://github.com/openai/whisper — the model family.
- **Lightning-Whisper-MLX**: https://github.com/mustafaaljadery/lightning-whisper-mlx — MLX-based implementation we benchmark against.
- **Mimi codec / Moshi**: https://kyutai.org/codec-explainer — relevant if you're going beyond Whisper into audio-codec land.

If a question above doesn't match your situation, [open a Discussion](https://github.com/larryxiao/openquack/discussions) — chances are someone else hit the same thing.
