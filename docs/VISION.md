# Vision

OpenQuack is a **privacy-first local AI agent interface, accessed via voice.**

## What this is

OpenQuack lets you **speak to your machine and have an agent do the thing** — fix a bug, open a PR, run a command, summarise a document, write the docs — without sending your voice or your work to anyone's cloud.

Voice input is the surface. The product is what happens after.

## What this isn't

- Not just dictation — other tools type what you said, OpenQuack does what you said.
- Not a cloud product. Audio never leaves your machine. Agents *may* call cloud APIs (e.g. Claude through Claude Code), but only because *you* configured them to — and the default agent backend is local-only.

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

- v0.1 — Python prototype on `main`, tagged `v0.1.0`. Frozen.
- v2 — Swift + agent integration on `v2`. Bench framework + first characterisation are live; see [BENCHMARKS.md](BENCHMARKS.md). App + agent layer are next.

## Tagline

> *Other tools type what you said. OpenQuack does what you said.*
