# Roadmap

Phased milestones with PR-sized atomic tasks. Every task cites a SPEC. Agent contributors should claim a task by opening a draft PR; see [AGENTS.md](../AGENTS.md).

## Status legend

- 🔵 **spec** — `docs/SPECS/<id>.md` exists; ready to claim
- 🟡 **in progress** — there is a draft PR or open issue
- 🟢 **done** — merged
- ⚪ **idea** — not specced yet, scope deliberately vague

---

## M1 — Foundation _(current)_

Bench framework + first characterisation. Establishes ground truth before product decisions.

| | Task | Spec | Notes |
|---|---|---|---|
| 🟢 | SPM scaffolding (Kit + bench + CLI) | — | `Package.swift`, three targets |
| 🟢 | WhisperKit engine | SPEC-002 | primary; Apple Silicon Metal |
| 🟢 | Lightning engine (Python subprocess) | SPEC-002 | bench-only baseline |
| 🟢 | Metrics: WER / CER / RTF / RSS / cold-start | SPEC-002 | `OpenQuackKit/Metrics/` |
| 🟢 | Corpus: 177 clips (TTS / multilingual / LibriSpeech / noise-aug) | — | `bench/corpus/` |
| 🟢 | Bench rerun on enriched corpus → BENCHMARKS.md | — | M4/16GB matrix landed |
| 🟢 | `openquack-cli` (single-file transcribe) | SPEC-002 | quick experiments |
| 🟢 | Vision + roadmap + AGENTS.md + spec scaffold | — | foundation in place |

---

## M2 — Voice → Action MVP

Goal: a working "speak → agent acts" loop on macOS, hotkey to action. Ships an installable but unsigned `.app`.

| | Task | Spec | Effort |
|---|---|---|---|
| 🟢 | App shell — SwiftPM target, menu bar, About panel | SPEC-010 | S |
| 🟢 | Audio capture — AVAudioEngine → 16 kHz mono WAV | SPEC-001 | S |
| 🟢 | Global hotkey (⌃⇧Space toggle, KeyboardShortcuts pkg) | SPEC-003 | S |
| 🟢 | Record → WhisperKit `medium` (en) → transcript in popover + clipboard | SPEC-002 | S |
| 🔵 | Floating recording overlay (waveform / level meter) | SPEC-004 | M |
| 🔵 | CGEvent ⌘V auto-paste at cursor (dictation fallback) | SPEC-005 | S |
| 🔵 | Agent dispatch abstraction + `PassthroughAgent` | SPEC-006 | M |
| 🔵 | `ClaudeCodeAgent` — subprocess to local `claude` CLI | SPEC-006 | M |
| ⚪ | Onboarding flow (Welcome → Permissions → Hotkey → First test) | — | M |
| ⚪ | Settings scene (General / Models / Shortcut / Privacy / Agent / About) | — | M |
| ⚪ | App icon + `Assets.xcassets` | — | S |

**M2 done when:** fresh user installs, completes onboarding, presses hotkey, says *"open a PR for this branch"* in a Claude-Code-configured repo, and a PR appears.

---

## M3 — Local agents + polish

| | Task | Spec | Effort |
|---|---|---|---|
| ⚪ | `OllamaAgent` (local HTTP) | SPEC-006 ext | S |
| ⚪ | `MLXLMAgent` (in-process via mlx-swift-lm) | SPEC-006 ext | M |
| ⚪ | Custom dictionary (custom-words bias) | new SPEC | S |
| ⚪ | "App Branch" context awareness (foreground app → prompt) | new SPEC | M |
| ⚪ | Streaming partial transcripts | new SPEC | L |
| ⚪ | Code signing + notarisation | — | S |
| ⚪ | DMG + Homebrew cask | — | S |
| ⚪ | Sparkle auto-update | — | S |

---

## M4 — Beyond MVP

| | Task | Notes |
|---|---|---|
| ⚪ | System-audio capture (meeting mode) | ScreenCaptureKit |
| ⚪ | Multilingual UI strings | follow Whisper language menu |
| ⚪ | Action confirmation UI for high-risk agent calls | privacy gate |
| ⚪ | Per-agent transcripts history pane (opt-in) | local-only |
| ⚪ | Linux / Windows ports | post-2.0 conversation |

---

## How to claim a task

1. Pick a 🔵.
2. Open an issue using *Agent Task* template; mark yourself as owner.
3. Read the cited SPEC.
4. Open a draft PR within ~24h naming the task in the title.
5. Follow [AGENTS.md](../AGENTS.md) for PR shape and required tests.
