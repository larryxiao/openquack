# OpenQuack

> **Speak to your machine. Have an agent do the thing. Privately.**

OpenQuack is a privacy-first **local AI agent interface, accessed via voice**, for macOS. Hold a hotkey, say what you want, and a configured agent — Claude Code, a local Ollama, or whatever you plug in — does the work. Audio never leaves your machine.

```
hotkey ─→ record ─→ Whisper (Apple Silicon, local)
                              │
                              ▼
                      ┌──────────────┐
                      │ Agent        │
                      ├──────────────┤
                      │ Claude Code  │   →  fix the bug, open a PR, write the test
                      │ Ollama       │   →  draft the email, summarise the meeting
                      │ Passthrough  │   →  paste at cursor (dictation parity)
                      └──────────────┘
```

> *Other tools type what you said. OpenQuack does what you said.*

---

## Status

- **v0.1** — Python prototype, on `main`, tagged `v0.1.0`. Frozen.
- **v2** — SwiftUI + agent integration, on `v2`. Bench framework + first hardware characterisation are live (see [BENCHMARKS](docs/BENCHMARKS.md)). App + agent layer are next (see [ROADMAP](docs/ROADMAP.md)).

This README is the front door. The serious docs are:

| | |
|---|---|
| [`docs/VISION.md`](docs/VISION.md) | What OpenQuack is, what it isn't, the privacy contract |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Milestones M1–M4 with PR-sized atomic tasks |
| [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md) | Per-host accuracy / latency / memory matrix |
| [`docs/SPECS/`](docs/SPECS/) | Component specs (one PR cites one spec) |
| [`AGENTS.md`](AGENTS.md) | How AI agents (and humans) contribute |

## Privacy contract (TL;DR)

1. Audio never leaves your machine. Capture → Whisper transcription is fully local. Always.
2. The default agent does no network IO.
3. Switching to a network-using agent (e.g. Claude Code) requires explicit one-time consent naming the destination.
4. The recording overlay shows a network indicator any time a network agent is active.

Full text in [`docs/VISION.md`](docs/VISION.md#privacy-contract).

## Running the bench

The fastest way to feel OpenQuack is to run the bench. It downloads / generates a small corpus and characterises every supported (engine, model) combination on your Mac.

```sh
# 1. Generate the synthetic corpus (multi-voice TTS + multilingual sentences).
bash bench/corpus/fetch.sh

# 2. Optional: real human speech (~337 MB one-time download from openslr.org).
N=20 bash bench/corpus/fetch_librispeech.sh

# 3. Optional: noise-augmented variants.
.venv/bin/python bench/corpus/mix_noise.py --source bench/corpus/voices

# 4. Run the bench.
swift run openquack-bench \
  --engines whisperkit,lightning \
  --models tiny,small,medium,distil-large-v3 \
  --corpus bench/corpus \
  --verbose
```

Output lands in `bench/out/<host-tag>/`. Submit your numbers via PR — see [`bench/CONTRIBUTING.md`](bench/CONTRIBUTING.md).

## Quick experiment with one file

```sh
# Default: whisperkit small
swift run openquack-cli path/to/audio.wav

# Pick engine + model
swift run openquack-cli path/to/audio.wav --engine lightning --model distil-large-v3

# JSON output for piping
swift run openquack-cli path/to/audio.wav --json
```

## Built on

- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) — Apple Silicon Metal speech-to-text.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkey registration.
- [`mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm) (planned) — for in-process local LLM agents.
- [`swift-argument-parser`](https://github.com/apple/swift-argument-parser) — CLI plumbing.

Reference projects: [voxt](https://github.com/hehehai/voxt) (technical pattern).

## Contribute

OpenQuack is built to be **AI-native open source** — the roadmap is structured for coding agents to claim atomic tasks, cite a spec, and ship PRs at scale. Humans are equally welcome and have to follow the same conventions.

Start with [`AGENTS.md`](AGENTS.md), then pick a 🔵 task in [`docs/ROADMAP.md`](docs/ROADMAP.md).

## License

Apache 2.0 — see [LICENSE](LICENSE).
