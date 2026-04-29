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

## Why

**Local.** Recording and transcription run entirely on your Mac. Audio never leaves the machine — nothing to leak, no telemetry, no signup. Confidential work stays confidential, by construction.

**Fast.** Whisper on Apple Silicon transcribes in roughly a fifth of the time you spent speaking. ~2.6% word-error rate on real human speech on a baseline M4 / 16 GB. Faster than typing in most cases. Full bench matrix in [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

**Open.** MIT-licensed. Every line is auditable; every change happens in public. The version running in your menu bar is the version in this repo.

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

## Coming next

A peek at what's queued up. Both build on the dictation foundation that ships today.

**In-context transcription.** OpenQuack will read the surrounding text where you're about to paste — the line above the cursor, the function you're inside, the chat thread you're replying to — and feed it to the speech model as context. Domain terms get disambiguated by what you're actually doing ("cloud code" turns into "Claude Code" when you're in a terminal, not the other way around). Less custom-dictionary tinkering needed.

**Thinking mode.** A second pass after transcription, run through a small local LLM, that turns a raw spoken sentence into a written one you'd actually press send on. Filler trimmed, structure tightened, the right capitalisation on words that matter. Off by default, one-toggle opt-in. Fully local — Ollama or MLX-LM, your pick.

Schedule and SPEC details in [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Install

Two paths today. Both manual until the cask lands in the official `homebrew-cask` (waiting on Apple Developer ID + notarisation — on the roadmap).

### Option A · Homebrew

```sh
brew tap larryxiao/openquack https://github.com/larryxiao/openquack
brew install --cask openquack
```

### Option B · DMG

Download `OpenQuack-<version>.dmg` from the [latest release](https://github.com/larryxiao/openquack/releases), open it, drag **OpenQuack** into **Applications**.

First launch needs a one-time bypass: right-click `OpenQuack.app` → **Open** → **Open**. That's macOS Gatekeeper holding pre-notarised builds at arm's length; subsequent launches work normally.

### After either path

Launch the app, grant **Microphone** (required) and **Accessibility** (optional, for auto-paste at cursor) when macOS asks, then pick a hotkey in **Settings → Shortcut**. Default is ⌃⇧Space.

### Hand it to your AI agent

Works with Claude Code, Codex, opencode, Hermes, and other coding-agent CLIs. Paste this verbatim — the agent will pick whichever path fits your machine and walk you through the permission grants:

```text
Install OpenQuack on this Mac.

Pick one path:

  Homebrew (preferred if `brew` is available):
    brew tap larryxiao/openquack https://github.com/larryxiao/openquack
    brew install --cask openquack

  DMG (manual): open https://github.com/larryxiao/openquack/releases,
    download the latest OpenQuack-*.dmg, mount it, drag OpenQuack.app
    into /Applications. First open: right-click → Open → Open to bypass
    the unidentified-developer prompt.

After either path, launch /Applications/OpenQuack.app, grant Microphone
(required) and Accessibility (optional, for auto-paste) when macOS
prompts, then pick a hotkey in Settings → Shortcut. Default is ⌃⇧Space.
```

Full install paths, uninstall, and "what gets downloaded on first run" in [`docs/INSTALL.md`](docs/INSTALL.md).

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

---

> The duck has bigger plans — a longer write-up of where this is going lives in [`docs/VISION.md`](docs/VISION.md).
