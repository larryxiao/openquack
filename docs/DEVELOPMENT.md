# Development

For people building, hacking, or benchmarking OpenQuack. End-user install lives in [`INSTALL.md`](INSTALL.md).

## Build from source

Requires **Xcode 16+**. The Swift Package Manager from CommandLineTools alone won't compile some macro-using deps (e.g. `KeyboardShortcuts`).

```sh
git clone https://github.com/larryxiao/openquack.git
cd openquack
bash scripts/wrap_app.sh
open build/OpenQuack.app
```

`scripts/wrap_app.sh` builds the SwiftPM `openquack` executable, wraps it in a minimal `OpenQuack.app` bundle, and signs it. The script auto-picks a code-signing identity in this order:

1. `$OQ_SIGN_IDENTITY` (explicit override — for Developer ID distribution).
2. Any `Developer ID Application: …` in the keychain.
3. Any `Apple Development: …` in the keychain (free Xcode-managed dev cert).
4. `OpenQuack Dev` (manual self-signed cert if you've created one).
5. Ad-hoc fallback.

Stable signing matters: ad-hoc signing changes the Designated Requirement on every rebuild, which makes macOS TCC drop the Accessibility / mic grant. Any of options 2–4 keep the grant across rebuilds.

## Build a DMG

```sh
bash scripts/make_dmg.sh
# → build/OpenQuack-<version>.dmg
```

The script prints a sha256 — paste it into `Casks/openquack.rb` if you're preparing a release.

## CLI for ad-hoc transcription

```sh
swift run openquack-cli some-audio.wav
swift run openquack-cli some-audio.wav --engine lightning --model distil-large-v3
swift run openquack-cli some-audio.wav --json
```

Useful for trying engines / models on a one-off without the GUI.

## Bench framework

Measures WER / CER / RTF / RSS / cold-start across engines × models on your machine.

```sh
# Fetch / generate corpus
bash bench/corpus/fetch.sh                 # synthetic + multilingual TTS
N=20 bash bench/corpus/fetch_librispeech.sh  # real human speech (~337 MB)
.venv/bin/python bench/corpus/mix_noise.py   # noise-augmented variants

# Run
swift run openquack-bench \
  --engines whisperkit,lightning \
  --models tiny,small,medium,distil-large-v3 \
  --corpus bench/corpus \
  --verbose
```

Output lands in `bench/out/<host-tag>/`. Submit results from your hardware via PR — see [`bench/CONTRIBUTING.md`](../bench/CONTRIBUTING.md).

Synthesised numbers and the recommendation matrix live in [`BENCHMARKS.md`](BENCHMARKS.md).

## Tech stack

- **WhisperKit** ([argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)) — Apple Silicon Metal STT.
- **KeyboardShortcuts** ([sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)) — global hotkey registration with a SwiftUI Recorder.
- **swift-argument-parser** — CLI plumbing for `openquack-cli` and `openquack-bench`.
- *(planned)* **mlx-swift-lm** — in-process local LLMs for the LLM-polish step (M2.5) and the agent layer (M3).
- *(planned)* **Sparkle** — auto-update once Developer ID notarisation is set up.

References: [voxt](https://github.com/hehehai/voxt) (technical).

## Repo layout

```
local_quack/
├── apps/                          (reserved for the future Xcode workspace)
├── Sources/
│   ├── OpenQuackApp/              SwiftUI menu-bar app (the GUI)
│   ├── OpenQuackKit/              Library — audio, STT, hotkey, paste
│   ├── OpenQuackCLI/              Single-file transcribe CLI
│   └── OpenQuackBench/            Benchmark CLI
├── scripts/                       wrap_app.sh, make_dmg.sh, make_icon.swift, entitlements
├── bench/                         corpus, lightning runner, host reports
├── docs/                          ARCHITECTURE / BENCHMARKS / VISION / ROADMAP / INSTALL / DEVELOPMENT
├── Casks/openquack.rb             Homebrew cask
└── Package.swift                  SwiftPM manifest
```

Architecture write-up in [`ARCHITECTURE.md`](ARCHITECTURE.md). Contributor flow in [`AGENTS.md`](../AGENTS.md).
