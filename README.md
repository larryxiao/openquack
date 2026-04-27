<div align="center">

# OpenQuack 🦆

**Speak. Have an agent do it. Privately.**

Privacy-first dictation for macOS — and (soon) a voice interface to your local AI agents. Audio never leaves your machine.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](#install)
[![WhisperKit](https://img.shields.io/badge/STT-WhisperKit-orange.svg)](https://github.com/argmaxinc/argmax-oss-swift)
[![Status](https://img.shields.io/badge/v2-alpha-yellow.svg)](docs/ROADMAP.md)

</div>

---

## What it is

OpenQuack is a small menu-bar app for macOS. Press a hotkey, speak, press it again — your transcript pastes at the cursor. Wherever you can type, you can talk.

It runs Whisper locally (`WhisperKit medium` by default). No cloud, no account, no signup, no telemetry. Your voice stays on your Mac.

The bigger plan is for OpenQuack to be a **voice interface to local AI agents** — speak to your Mac, have Claude Code (or your local Ollama, or your own agent) act on it. The dictation experience is shipping first; agent integration follows once the foundation is solid. See [`docs/VISION.md`](docs/VISION.md) for the full pitch and [`docs/ROADMAP.md`](docs/ROADMAP.md) for the milestone schedule.

> *Other tools type what you said. OpenQuack does what you said.*

## What's in v0

- **One-key dictation** — global hotkey (default ⌃⇧Space), toggle or push-to-talk.
- **Local Whisper** — WhisperKit `medium` for English (configurable to `tiny`…`large-v3`); 0.22× RTF on M4 / 16 GB.
- **Auto-paste** at the cursor in any app (clipboard fallback).
- **Smart formatting** — capitalisation, end-punctuation, filler-word cleanup.
- **Custom dictionary** — bias the model toward proper nouns and jargon.
- **VAD auto-stop** — finish speaking, OpenQuack finalises automatically.
- **Floating overlay** with a live level meter while you record.
- **First-launch onboarding** — permissions, hotkey, done.
- **Settings** for everything above.
- **Bench framework** — measure WER / RTF / RSS across engines and models on your hardware (`swift run openquack-bench`).
- **Open source**, MIT.

## Privacy

1. Audio never leaves your machine. Capture → Whisper transcription is fully local. Always.
2. The default agent does no network IO.
3. Network-using agents (e.g. Claude Code, when that lands) require explicit per-agent consent and a visible network indicator.
4. No analytics, no telemetry, no signup.

Full text in [`docs/VISION.md`](docs/VISION.md#privacy-contract).

## Install

> Homebrew cask is the recommended path once the first release is published. Until then, build from source — it's a one-liner.

### Homebrew (once v0 is released)

```sh
brew install --cask openquack
```

### From source

Requires **Xcode 16+** (the Swift Package Manager from CommandLineTools alone won't compile some macro-using deps):

```sh
git clone https://github.com/OpenQuack/openquack.git
cd openquack
git checkout v2
bash scripts/wrap_app.sh
open build/OpenQuack.app
```

The first launch downloads the WhisperKit `medium` model (~700 MB) and walks you through a 5-step setup.

## Quick experiments without the app

A small CLI for ad-hoc transcription:

```sh
swift run openquack-cli some-audio.wav
swift run openquack-cli some-audio.wav --engine lightning --model distil-large-v3
swift run openquack-cli some-audio.wav --json
```

A bench that measures WER / RTF / RSS across engines × models on your Mac:

```sh
bash bench/corpus/fetch.sh                 # synthetic + multilingual TTS
N=20 bash bench/corpus/fetch_librispeech.sh  # real human speech (~337 MB)
.venv/bin/python bench/corpus/mix_noise.py   # noise-augmented variants

swift run openquack-bench \
  --engines whisperkit,lightning \
  --models tiny,small,medium,distil-large-v3 \
  --corpus bench/corpus \
  --verbose
```

Output lands in `bench/out/<host-tag>/`. Submit your numbers via PR — see [`bench/CONTRIBUTING.md`](bench/CONTRIBUTING.md).

## Roadmap

| Milestone | What | Status |
|---|---|---|
| **M1** | Bench framework + characterisation | ✅ |
| **M2** | Voice → Action MVP (this release path) | 🟡 in progress |
| **M3** | Local agents (Ollama, MLX-LM), code signing, auto-update | ⚪ |
| **M4** | System-audio capture, multilingual UI, cross-platform | ⚪ |

The detailed task list with PR-sized atomic items lives in [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Contribute

OpenQuack is built to be **AI-native open source** — every PR cites a SPEC, atomic tasks are picked from the roadmap, the workflow is friendly to coding agents at scale. Humans equally welcome on the same path.

Start with [`AGENTS.md`](AGENTS.md), pick a 🔵 task in [`docs/ROADMAP.md`](docs/ROADMAP.md), open a draft PR.

## Tech

- **WhisperKit** ([argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)) — Apple Silicon Metal STT
- **KeyboardShortcuts** ([sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)) — global hotkey registration
- **swift-argument-parser** — CLI plumbing
- (planned) **mlx-swift-lm** — in-process local LLMs for the agent layer
- (planned) **Sparkle** — auto-update

References: [voxt](https://github.com/hehehai/voxt) (technical).

## Honest numbers

Benchmarked on Apple M4 / 16 GB across 177 clips (multi-voice TTS, multilingual native speech, real LibriSpeech samples, noise-augmented variants):

| Bucket | Best engine + model | WER | RTF |
|---|---|---:|---:|
| Real human speech | whisperkit `medium` | **2.6 %** | 0.22× |
| Multi-accent English | whisperkit `medium` | **1.3 %** | 0.31× |
| Noise-augmented | whisperkit `medium` | **6.3 %** | 0.31× |

Full matrix and methodology in [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

## License

MIT — see [LICENSE](LICENSE).
