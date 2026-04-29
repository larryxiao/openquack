# Architecture

A practical map of where things live and why. For why OpenQuack
exists, see [`VISION.md`](VISION.md); for the state of work, see
[`ROADMAP.md`](ROADMAP.md).

## Layout

```
local_quack/
├── Package.swift              SPM manifest — one library, three executables
├── Sources/
│   ├── OpenQuackKit/          Library — UI-free brain, used by all three exes
│   │   ├── Audio/             AVAudioEngine capture, 16 kHz mono float32
│   │   ├── Transcription/     WhisperKit engine + model manager
│   │   ├── Hotkey/            KeyboardShortcuts wrapper
│   │   ├── Output/            NSPasteboard + CGEvent ⌘V
│   │   ├── Polish/            Optional LLM cleanup (M2.5, opt-in)
│   │   ├── Metrics/           WER / CER / RTF / TTFT / RSS / host info
│   │   └── Updates/           Sparkle integration
│   ├── OpenQuackApp/          The menu-bar app — pure AppKit shell
│   ├── OpenQuackBench/        `openquack-bench` — characterisation CLI
│   └── OpenQuackCLI/          `openquack-cli` — headless dictation/transcribe
├── Tests/OpenQuackKitTests/   Library unit tests
├── bench/
│   ├── corpus/                Audio + reference text (audio gitignored)
│   ├── engines/               Helper scripts for non-Swift engines
│   └── out/                   Per-host benchmark reports
└── docs/
```

## Why one library, three executables

The library (`OpenQuackKit`) owns capture, transcription, polish, and
metrics. Everything UI-free. Three thin executables consume it:

- **`openquack`** (the menu-bar app) — AppKit, hotkey + overlay +
  Settings. Pure surface; no domain logic.
- **`openquack-bench`** — drives engines × models against the corpus,
  emits `report.md` / `report.csv` / `host.json`. Headless, runs in
  CI, runs on contributor Macs.
- **`openquack-cli`** — same library, command-line dictation /
  transcription. Useful for scripting and for repro'ing app issues
  without the GUI.

The split keeps GUI noise out of the bench, lets contributors run
characterisation without launching an app, and makes it easy to add
future surfaces (a LaunchBar action, a Shortcuts intent) without
duplicating the brain.

## Why no Xcode project

Pure SPM. `swift build`, `swift test`, `swift run openquack-bench` all
work from a clean checkout with just the toolchain — no Xcode required
beyond what SwiftPM itself needs (and even that is only because some
deps include `#Preview` blocks). The signed `.app` is assembled by
`scripts/wrap_app.sh`, which wraps the SPM build product in a minimal
bundle. See [`DEVELOPMENT.md`](DEVELOPMENT.md) for the full build
flow.

## Measure-first

The bench was built before the app. Default model, minimum supported
Mac, and what shows up in Settings → Speech-to-text are all decided
from numbers in [`BENCHMARKS.md`](BENCHMARKS.md), not assumption. Same
discipline applies to M2.5 (LLM polish) and beyond — each new model
or engine lands in `OpenQuackBench` first.
