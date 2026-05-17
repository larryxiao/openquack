---
title: OpenQuack — Local-only voice dictation for macOS
description: Free, open-source Mac dictation app. Press a hotkey, speak, transcript appears at your cursor. WhisperKit on Apple Silicon, 99 languages, no cloud, no telemetry, MIT licensed.
image: https://github.com/larryxiao/openquack/raw/main/docs/images/banner.png
twitter:
  card: summary_large_image
  image: https://github.com/larryxiao/openquack/raw/main/docs/images/banner.png
---

# OpenQuack

**Local-only voice dictation for macOS.** Press a hotkey, speak, the transcript appears at your cursor. Nothing leaves your device — audio, text, telemetry, nothing.

- **MIT licensed** — every line is auditable
- **All local** — Whisper runs on Apple Silicon via WhisperKit; no cloud, no account, no subscription
- **Fast** — ~2.6% word-error rate on real human speech, ~3 seconds post-stop wait even on 5-minute clips
- **99 languages** — English, Chinese, Japanese, Korean, Spanish, French, German, and 92 more
- **Tiny** — ~8 MB menu-bar app plus the speech model on first run

[**View the repository on GitHub →**](https://github.com/larryxiao/openquack)

## Install

```sh
brew tap larryxiao/openquack https://github.com/larryxiao/openquack
brew install --cask openquack
```

Or [download the DMG](https://github.com/larryxiao/openquack/releases) and drag into Applications. macOS 13+ on Apple Silicon (M1 or newer).

## Got stuck? Want a feature?

Drop a comment in **[Discussions](https://github.com/larryxiao/openquack/discussions/43)** — it's the lowest-friction way to reach me. Bugs, feature ideas, "I'm using it for X" workflow stories, or quick questions about Whisper / model choice all welcome.

## Documentation

- [Install guide](INSTALL.md)
- [Five-minute tutorial](TUTORIAL.md)
- [Benchmark matrix](BENCHMARKS.md) — five Whisper sizes × two engines × 177 clips on M4 / 16 GB
- [Architecture](ARCHITECTURE.md)
- [Roadmap](ROADMAP.md)
- [Vision and privacy contract](VISION.md)
- [Contribute (`AGENTS.md`)](https://github.com/larryxiao/openquack/blob/main/AGENTS.md)

## Blog

- [What I learned benchmarking Whisper on Apple Silicon](blog/2026-05-whisper-mac-bench.md) — three findings that changed the product, May 2026

## FAQ

**Is OpenQuack a free alternative to Wispr Flow, SuperWhisper, or MacWhisper?**
Yes. OpenQuack is MIT-licensed and free. Wispr Flow, SuperWhisper, and MacWhisper require subscriptions or one-time purchase fees; OpenQuack does not.

**Does it work completely offline?**
Yes, after the first run. On first launch, the Whisper speech model downloads from Hugging Face (~500 MB for 16 GB Macs, ~250 MB for 8 GB Macs). After that, no internet connection is needed for dictation — ever.

**What Mac do I need?**
macOS 13 (Ventura) or later on Apple Silicon (M1 or newer). Intel Macs are not supported.

**How accurate is it?**
On real human speech, ~2.6% word-error rate with the default model on an M4 / 16 GB Mac. In realistic office noise: ~6.3% WER. Full benchmark matrix in [BENCHMARKS.md](BENCHMARKS.md).

**Does it send my audio or transcripts anywhere?**
No. Audio is recorded, transcribed, and discarded entirely on your Mac. No analytics, no telemetry, no account, no API calls in the dictation path. Source is MIT-licensed and auditable.

**How is this different from the built-in macOS Dictation?**
macOS Dictation sends audio to Apple's servers by default. OpenQuack runs fully local, supports 99 languages with no toggle, uses Whisper rather than Apple's proprietary model, and is open source.

**How do I use it for typeless coding workflows?**
OpenQuack pastes at wherever your cursor is — including the prompt bars of Claude Code, Cursor, Windsurf, or any terminal. Press the hotkey, speak the prompt, press again, and it appears.

**What languages does it support?**
99 Whisper languages. English is the default; to switch, open Settings → Language. Auto-detect works best on clips longer than 3 seconds and is most reliable when paired with a configured fallback language.

**Why does the first launch take a long time?**
The speech model downloads once on first run and is cached permanently in `~/Library/Application Support/OpenQuack/models/`. Every subsequent launch is instant.

**Is there a Windows or Linux version?**
Not currently. OpenQuack uses WhisperKit and CoreML, which are Apple-platform technologies.

## License

MIT. See [LICENSE](https://github.com/larryxiao/openquack/blob/main/LICENSE) in the repository.
