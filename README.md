<div align="center">

# OpenQuack 🦆

**Speak. Watch it type. Privately.**

Voice dictation for macOS that runs entirely on your Mac. Audio never leaves the machine.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](docs/INSTALL.md)
[![Status](https://img.shields.io/badge/status-alpha-yellow.svg)](docs/ROADMAP.md)

</div>

---

## What it is

OpenQuack is a tiny menu-bar app for macOS. Press a hotkey, speak, press it again — your transcript appears at the cursor. Wherever you can type, you can talk.

Speech recognition happens on your Mac. No cloud, no account, no signup, no telemetry.

> *Other tools type what you said. OpenQuack does what you said.*

The duck has bigger plans — a longer write-up of where this is going lives in [`docs/VISION.md`](docs/VISION.md).

## What you get

- **One-key dictation.** Pick a hotkey (default ⌃⇧Space). Toggle or push-to-talk.
- **All local.** Speech recognition runs on your Mac. No internet needed for dictation.
- **Auto-paste at the cursor** in any app. (Falls back to your clipboard if you'd rather paste yourself.)
- **Smart formatting** — capitalisation, end-punctuation, "um/uh" cleanup.
- **Custom dictionary** — teach it the proper nouns and project names you actually use.
- **Auto-stop after silence.** Finish speaking, OpenQuack wraps up on its own.
- **Live mic-level overlay** so you can see it's listening.
- **Quick first-launch setup** — permissions, hotkey, done in a minute.
- **Tiny.** A 3 MB menu-bar app; the speech model is the only thing you download.
- **Open source**, MIT.

## Privacy, in one screen

1. **Audio never leaves your machine.** Recording and transcription are fully local. Always.
2. **No network calls during dictation.**
3. **No analytics, no telemetry, no signup.**

The full privacy contract is in [`docs/VISION.md`](docs/VISION.md#privacy-contract).

## Install

The recommended path once the first release ships is Homebrew:

```sh
brew install --cask openquack
```

For now — DMG download, manual install, or building from source — see [`docs/INSTALL.md`](docs/INSTALL.md).

## Roadmap

| Milestone | What | Status |
|---|---|---|
| **M1** | Foundations | ✅ |
| **M2** | Voice → Action MVP | 🟡 in progress |
| **M3** | Local AI agents, signed builds, auto-update | ⚪ |
| **M4** | Meeting mode, multilingual UI, cross-platform | ⚪ |

Detailed task list in [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Contribute

OpenQuack is built to be **AI-native open source** — every PR cites a SPEC, atomic tasks are picked from the roadmap, the workflow is friendly to coding agents at scale. Humans equally welcome on the same path.

Start with [`AGENTS.md`](AGENTS.md), pick a 🔵 task in [`docs/ROADMAP.md`](docs/ROADMAP.md), open a draft PR.

## Under the hood

For builders, hackers, and anyone running the bench:

- [`docs/INSTALL.md`](docs/INSTALL.md) — install paths and permissions.
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — build from source, signing, CLI, and the benchmark framework.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — module layout and design notes.
- [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md) — measured accuracy and speed across hardware.
- [`docs/VISION.md`](docs/VISION.md) — what OpenQuack is becoming.

## License

MIT — see [LICENSE](LICENSE).
