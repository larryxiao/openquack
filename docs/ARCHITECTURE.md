# Architecture

> Living doc. Filling in as the rewrite lands.

## Layout

```
local_quack/                      (root, on v2 branch)
├── apps/OpenQuack/               Xcode project (Phase 3+)
├── Sources/
│   ├── OpenQuackKit/             Library — UI-free brain
│   │   ├── Audio/                AVAudioEngine capture (Phase 4)
│   │   ├── Transcription/        Engines: WhisperKit, Lightning
│   │   ├── Hotkey/               KeyboardShortcuts wrapper (Phase 4)
│   │   ├── Output/               Pasteboard + ⌘V (Phase 4)
│   │   ├── Permissions/          Mic + Accessibility (Phase 4)
│   │   ├── Metrics/              WER, CER, RTF, TTFT, RSS, host info
│   │   └── Polish/               LLM cleanup (Phase 6)
│   └── OpenQuackBench/           CLI: drive engines × models → reports
├── Tests/OpenQuackKitTests/      Library unit tests
├── bench/
│   ├── corpus/{short,medium,long,multilingual}/   Audio + reference text
│   └── engines/lightning_runner.py                 Python helper for v0.1 baseline
├── docs/
└── Package.swift
```

## Why split SPM + Xcode

The library and the bench CLI are SPM targets at the repo root, so:

- `swift run openquack-bench` works without Xcode.
- `swift test` runs library tests headlessly.
- The Xcode app (Phase 3+) consumes the local SPM package as a thin shell over `OpenQuackKit`.

## Phasing

Phase ordering is **measure-first**. The bench (Phase 1) and characterisation run (Phase 2) precede the app (Phase 3+) so default model and supported-hardware decisions come from data, not assumption.

See `README.md` for the high-level roadmap, or the plan file referenced above for full detail.
