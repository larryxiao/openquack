# Vision

OpenQuack is a **privacy-first local AI agent interface, accessed via voice.**

## What this is

OpenQuack lets you **speak to your machine and have an agent do the thing** — fix a bug, open a PR, run a command, summarise a document, write the docs — without sending your voice or your work to anyone's cloud.

Voice input is the surface. The product is what happens after.

## What this isn't

- Not just dictation — other tools type what you said, OpenQuack does what you said.
- Not a cloud product. Audio never leaves your machine. Agents *may* call cloud APIs (e.g. Claude through Claude Code), but only because *you* configured them to — and the default agent backend is local-only.

## Why use it

Three things, in priority order:

1. **Local.** Recording, transcription, polishing — all on your Mac. Audio never leaves the machine. There's nothing to leak: no cloud upload, no telemetry, no signup. Confidential work stays confidential by construction, not by promise. Detailed [privacy contract](#privacy-contract) below.
2. **Fast.** WhisperKit on Apple Silicon hits roughly 2.6% word-error rate on real human speech at ~0.22× realtime on a baseline M4 / 16 GB. Faster than typing in most cases, accurate on natural conversation. Numbers in [BENCHMARKS.md](BENCHMARKS.md); contributions of bench results from other Macs welcome.
3. **Open.** MIT-licensed. Every line is auditable; every change happens in public. The version in your menu bar is the version in this repo. No tracking pixels, no analytics, no remote toggle that can change the rules.

## Quality bar

The transcript has to be **good enough to send without re-reading**. If the user has to scan and fix typos before pressing return on a Claude Code prompt, OpenQuack is a worse keyboard, not a better interface. Two things have to be true:

1. **Whisper transcription is correct on real speech**, including words it doesn't know. "Claude Code" should never come out as "cloud code." This is what Whisper's prompt-token bias and the post-transcription LLM polish step (M2.5) are for: domain terms get resolved, not hoped at.
2. **The polished transcript reads like a written sentence**, not a raw dictation. Filler words trimmed, capitalisation and punctuation right, false starts cleaned up. Polishing happens locally; the user keeps the option to see the raw version.

Benchmarking this is part of the work — `openquack-bench` already measures WER; M2.5 adds a domain-term accuracy metric and a "send-confidence" delta with vs without polish.

## How it works

```
hotkey ─→ record (mic, local) ─→ Whisper (Apple Silicon, local) ─→ agent
                                                                      │
                                                                      ├─→ Claude Code (your CLI, your key, your repos)
                                                                      ├─→ Ollama / MLX-LM (pure local agent)
                                                                      └─→ paste at cursor (dictation fallback)
```

1. **Hotkey** triggers recording from the system mic.
2. **WhisperKit** transcribes locally, on Apple Silicon, in seconds (small model: ~0.08× realtime on M4).
3. The transcript is **dispatched to a configured agent**:
   - **`claude-code`** — spawn the user's local Claude Code CLI in their workspace; pipe the utterance; surface the result.
   - **`ollama`** — call a local Ollama model for tasks that fit local capability.
   - **`passthrough`** — paste at cursor (dictation parity, default until an agent is configured).
4. Agent acts. Output (if any) lands at cursor or in a result panel.

## Why now

We built [the bench](BENCHMARKS.md) before writing any of this prose. On a baseline Apple M4 / 16 GB:

- WhisperKit `small` hits ~1 % WER on real speech at **0.08× realtime**.
- MLX-LM runs Qwen3 / Llama 3 family models entirely on-device at usable speeds.
- Claude Code makes "agent over your repo" a single CLI install.
- Privacy regulation, user trust, and pure preference all point local-first.

The pieces have shipped. OpenQuack is the surface that ties them together.

## Audience

- **Developers** who already use Claude Code or want to.
- **Confidentiality-sensitive users** (legal, medical, journalists) who'd dictate but won't ship audio off their machine.
- **Multilingual users** — Whisper handles 99 languages; the agent layer follows.

## Privacy contract

1. **Audio never leaves the machine.** Capture → transcription is fully local. Always. No telemetry of audio or transcripts.
2. **Default agent does no network IO.** `passthrough` (paste-at-cursor) is the out-of-the-box behaviour.
3. **Network-using agents are explicitly opt-in.** Switching from `passthrough` to `claude-code` triggers a clear consent prompt naming the destination ("this routes your transcripts to Anthropic via Claude Code").
4. **Per-agent network indicator** is visible in the recording overlay any time a network-using agent is active.
5. **No analytics in the default build.** A future opt-in telemetry build for crash reports may exist, never on by default.

## Status

- v0.1 — Python prototype, frozen at tag `v0.1.0`.
- v2 — SwiftUI rewrite is now on `main`. Bench framework, dictation MVP (record → Whisper → paste), onboarding, settings, DMG packaging are live; see [BENCHMARKS.md](BENCHMARKS.md). LLM transcript polish (M2.5) and the agent layer (M3) are next.

## Tagline

> *Other tools type what you said. OpenQuack does what you said.*
