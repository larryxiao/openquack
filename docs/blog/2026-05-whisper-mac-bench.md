# What I learned benchmarking Whisper on Apple Silicon for a Mac dictation app

I needed to pick a default Whisper size for a Mac dictation app I built, and I didn't trust the published numbers. Most Whisper benchmarks publish one WER on one corpus on one machine. The choice of model size, the choice of engine implementation, and the kinds of audio someone actually feeds a dictation app — none of that gets crossed in a single matrix.

So I built one. Five Whisper sizes (`tiny`, `base`, `small`, `medium`, `distil-large-v3`), two engines (WhisperKit and Lightning-Whisper-MLX), and 177 clips spanning real human speech, multi-accent English TTS, six non-English languages, and noise-augmented variants at three SNRs. Single host, M4 / 16 GB / macOS 15. The numbers and the raw CSVs are all in the repo.

This post is what I learned. There were three findings I didn't expect.

## Methodology, briefly

The corpus is 177 WAV files, 16 kHz mono PCM, partitioned into five buckets:

- **LibriSpeech** (20 clips). Real human read speech from `dev-clean` (CC BY 4.0, openslr.org/12). The closest thing in the set to what dictation feels like in practice.
- **Voices** (20 clips). Multi-accent English TTS — Samantha (US), Daniel (UK), Karen (AU), Fred (US robotic). Five sentences per voice. Useful as the noise-clean baseline and as a way to vary accent without varying the speaker count.
- **Noisy** (120 clips). The 20 voices, augmented with white and pink noise at 5, 10, and 20 dB SNR. Closer to what people actually dictate near: A/C, café chatter, an open window.
- **Multilingual** (12 clips). Two clips each in Mandarin, Japanese, Korean, Spanish, French, German. Auto-detect was on; no language hint to the engine. Worst-case scenario for a dictation app that defaults to "figure it out yourself."
- **Short** (5 clips). Single-voice TTS sanity-check.

Engines: WhisperKit (`argmaxinc/argmax-oss-swift` 0.18+) and Lightning (`lightning-whisper-mlx` 0.0.10 driven from a long-running Python subprocess). Models: the five sizes above. Metrics: WER, CER, RTF (wall / audio), cold start (engine init to first transcribe), and peak RSS sampled at 100 ms via `mach_task_basic_info`.

What this bench doesn't cover: real conversational speech with overlap, very long clips under sustained system load, anything but one host. Single-host data has an obvious ceiling. The bench script smoke-passes in CI; if you have a non-M4 Mac, PRs to `bench/out/` are the most useful contribution this project can take right now.

## The headline number

WhisperKit `medium`, on M4 / 16 GB, on real human speech:

| Bucket | WER | CER | RTF | Peak RSS |
|---|---:|---:|---:|---:|
| LibriSpeech (real human) | 2.6 % | 1.3 % | 0.22x | 197 MB |
| Voices (multi-accent TTS) | 1.3 % | 0.3 % | 0.31x | 197 MB |
| Noisy (white + pink, 5-20 dB SNR) | 6.3 % | 2.7 % | 0.31x | 197 MB |

That's the row I'd quote. RTF 0.22x means transcription runs roughly five times faster than the audio plays, on a baseline laptop chip. Cold start is 27 seconds the first time, then never again — model caches to disk after the download.

The full per-engine, per-model, per-bucket matrix is in [`docs/BENCHMARKS.md`](https://github.com/larryxiao/openquack/blob/main/docs/BENCHMARKS.md). What follows is what I'd missed before I ran it.

## Finding 1: Auto-detect on short non-English clips is broken

This is the one that changed the product.

The multilingual bucket has 12 short clips (averaging ~3 seconds) in six languages, with auto-detect on. Lightning's `medium` got 16.7% WER across the set: degraded but usable. WhisperKit's `medium` got **253.2%** WER. WhisperKit's `base` got 284.3%. Same Whisper weights, very different output.

A WER of 253% means the transcript is almost three times longer than the reference. The model isn't failing to recognise; it's hallucinating. Spot-checking the per-clip CSVs, the most common failure mode is: a 2-second Spanish clip produces a paragraph of fluent English that has nothing to do with the audio. The same audio fed to Lightning at the same model size produces "el camión está aquí" or close to it.

Same weights, very different multilingual robustness. That makes this an implementation difference, not a fundamental Whisper limitation. The decoder parameters are the prime suspect: `suppress_tokens`, `no_speech_threshold`, language-token forcing, sample length. I haven't traced it down yet. If anyone has shipped a LangID pre-pass in production or has a working WhisperKit decoder config for short multilingual audio, I'd like to compare notes (issue or PR welcome).

The pragmatic fix shipped before the explanation did. The Settings pane now surfaces an explicit Language picker; auto-detect is off by default for users who have configured a language. The bench result was load-bearing for that decision. Without it, the natural default was "let Whisper figure it out", which would have been unusable for anyone outside English.

## Finding 2: Distilled is not a free upgrade

`distil-large-v3` is faster than `medium` and the marketing around it suggests "same quality, better latency." On real human speech it's close: 3.2% WER vs 2.6% for `medium`, RTF 0.12x vs 0.22x. Faster, with a small accuracy hit.

On multi-accent English TTS the gap widens: 5.3% vs 1.3%. Four times the WER, for the same audio family. The Voices bucket is synthetic, but it's also the cleanest signal we have for accent robustness — you control everything except the voice.

The take I came away with: distil is the right pick when latency dominates and the speech is clean. `medium` is the right pick when accuracy matters and the domain has unfamiliar terms (proper nouns, project names, transcription of speech that isn't from a podcast host). For a dictation app that runs in the background of normal work, `medium` won. For a real-time captioning scenario, distil might. They aren't interchangeable.

## Finding 3: `tiny` and `base` collapse on noise

The clean-speech numbers for `tiny` and `base` look workable: 7-9% WER on LibriSpeech, 12-15% on Voices. You could read those and think "fine for an 8 GB Mac if accuracy isn't critical."

Then add 10 dB SNR of pink noise:

| Model | LibriSpeech WER | Noisy WER |
|---|---:|---:|
| `medium` | 2.6% | 6.3% |
| `small` | 4.1% | 11.4% |
| `base` | 5.9% | 24.0% |
| `tiny` | 7.2% | 27.3% |

`tiny` and `base` go from "marginal" to "unusable" the moment you introduce real-world noise. People dictate near A/C, in cafés, with HVAC running. Quoting only the clean-speech number for these sizes would have been misleading. The OpenQuack default for 8 GB Macs is `small`, not `base` — that's the smallest size that survives the noisy bucket with WER under 12%.

## What this changed

Three concrete decisions came out of the bench:

- **Default model per hardware tier.** `medium` for 16 GB+, `small` for 8 GB. Earlier defaults followed model-size ergonomics; the bench made it about ceiling accuracy.
- **Explicit language picker in Settings.** Auto-detect is too fragile on short non-English audio for an app that has to feel reliable on the first try.
- **Streaming for long audio.** Once `medium` was the default, the end-of-dictation wait got bad on long clips. A 5-minute clip finishes offline in 34.4 seconds wall-clock; without streaming the user experience was 30 seconds of staring at a "transcribing..." indicator.

That last one is its own measurement. Streaming the audio in chunks while you speak, then finalising the tail when you stop, gave:

| Length | Offline | Post-stop | Speedup |
|---|---:|---:|---:|
| 30s | 4.36s | 1.55s | 2.8x |
| 1-min | 7.03s | 1.65s | 4.3x |
| 2-min | 13.76s | 2.41s | 5.7x |
| 5-min | 34.44s | **2.77s** | **12.4x** |

The post-stop wait stops growing with length. The 12x speedup at 5 minutes is what's interesting; at 30 seconds the speedup is modest (you can't beat a fast clip by much), but as audio gets long, streaming dominates more and more. WER delta vs offline is within +/- 0.5 pp across all length buckets.

## What's next

The local-LLM polish step — taking a raw transcript and tightening it into something you'd press send on, without a cloud round-trip — is on the bench list. Same methodology: engines, models, corpus, matrix. I'll post when the numbers land.

## Reproduce or contribute

- Full per-engine, per-model, per-bucket matrix: [`docs/BENCHMARKS.md`](https://github.com/larryxiao/openquack/blob/main/docs/BENCHMARKS.md)
- Raw CSVs per host: [`bench/out/M4-16GB/`](https://github.com/larryxiao/openquack/tree/main/bench/out)
- Streaming bench detail: [`bench/out/stream/M4-16GB-paced/report.md`](https://github.com/larryxiao/openquack/blob/main/bench/out/stream/M4-16GB-paced/report.md)
- Corpus composition + how to reproduce: [`bench/corpus/`](https://github.com/larryxiao/openquack/tree/main/bench/corpus)

If you have a non-M4 Mac (M1, M2, M3, Intel, 8 GB, 24 GB+), the bench script smoke-passes in CI and the corpus is checked in. PRs to `bench/out/` are the most useful contribution this project can take. The matrix is one host wide right now; it should be many.
