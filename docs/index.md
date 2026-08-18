---
title: OpenQuack — Local-first voice dictation for macOS
description: Free, open-source Mac dictation app. Press a hotkey, speak, transcript appears at your cursor. WhisperKit on Apple Silicon, 99 languages, no cloud, no telemetry, MIT licensed.
image: https://github.com/larryxiao/openquack/raw/main/docs/images/banner.png
twitter:
  card: summary_large_image
  image: https://github.com/larryxiao/openquack/raw/main/docs/images/banner.png
---

# OpenQuack

**Local-first voice dictation for macOS.** Press a hotkey, speak, the transcript appears at your cursor. Nothing leaves your device by default — audio, text, telemetry, nothing.

- **MIT licensed** — every line is auditable
- **Local by default** — Whisper runs on Apple Silicon via WhisperKit; no cloud, no account, no subscription
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
Not by default. Audio is recorded, transcribed, and discarded entirely on your Mac — no analytics, no telemetry, no account, no API calls in the dictation path. The one opt-in exception: you can point transcription at your own OpenAI-compatible endpoint, and the overlay shows whenever that's in use. Source is MIT-licensed and auditable.

**How is this different from the built-in macOS Dictation?**
macOS Dictation sends audio to Apple's servers by default. OpenQuack runs fully local, supports 99 languages with no toggle, uses Whisper rather than Apple's proprietary model, and is open source.

**How do I use it for typeless coding workflows?**
OpenQuack pastes at wherever your cursor is — including the prompt bars of Claude Code, Cursor, Windsurf, or any terminal. Press the hotkey, speak the prompt, press again, and it appears.

**What languages does it support?**
99 Whisper languages with reliable auto-detect as of [v2.0.0-alpha.17](https://github.com/larryxiao/openquack/releases/tag/v2.0.0-alpha.17) — speak Mandarin, Cantonese, Japanese, Korean, French, Spanish, or any of the 99, and OpenQuack identifies and transcribes it correctly without manual selection. Mixed-language dictation (e.g. "*Mon dieu, this PR has 一百 comments*") also works. If you want extra accuracy on very short clips or have a fixed working language, pick it explicitly in Settings → Language.

**Why does the first launch take a long time?**
The speech model downloads once on first run and is cached permanently in `~/Library/Application Support/OpenQuack/models/`. Every subsequent launch is instant.

**Why is my transcript just "You.", "Thank you.", or "Thanks for watching"?**
That short, oddly generic output is Whisper hallucinating on *silent* audio — those exact phrases leak from its training data when it's given little or no speech. It almost always means OpenQuack recorded silence instead of your voice. Check, in order: (1) while recording, watch the level meter in the recording overlay — if the bars don't move when you talk, no audio is reaching the app; (2) open **System Settings → Privacy & Security → Microphone** and make sure OpenQuack is listed and enabled (after granting it, restart OpenQuack so the grant takes effect); (3) confirm your active input device under **System Settings → Sound → Input** is the mic you're actually speaking into, not a silent virtual device. To hear exactly what was captured, play back the last recording at `~/Library/Application Support/OpenQuack/last-recording.wav`.

**Is there a Windows or Linux version?**
Not currently. OpenQuack uses WhisperKit and CoreML, which are Apple-platform technologies.

## License

MIT. See [LICENSE](https://github.com/larryxiao/openquack/blob/main/LICENSE) in the repository.
