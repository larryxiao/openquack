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
| 🟢 | Floating recording-state pill (top-centre, click-through) | SPEC-004 | M |
| 🟢 | CGEvent ⌘V auto-paste at cursor (Accessibility prompt + clipboard fallback) | SPEC-005 | S |
| 🔵 | Agent session protocol + `PassthroughAgent` + conversation panel | SPEC-006 | M |
| 🔵 | `ClaudeCodeAgent` — long-lived subprocess, streaming events | SPEC-006 | M |
| 🔵 | Approval prompt UX (overlay morph + buttons) | SPEC-006 | S |
| 🟢 | Onboarding flow (Welcome → Mic → Paste → Hotkey → Done) | — | M |
| 🟢 | Settings scene MVP (General / Models / Shortcut / About) | — | M |
| 🔵 | Settings — Privacy + Agent panes (lands with SPEC-006 impl) | SPEC-006 | S |
| 🟢 | Smart text post-processing (capitalise, punct, fillers) | — | S |
| 🟢 | Live level meter + push-to-talk | SPEC-001 ext | S |
| 🟢 | VAD auto-stop + sounds + custom dictionary | — | S |
| 🟢 | App icon (procedural cream-gradient duck) | — | S |
| 🟢 | DMG + Homebrew cask + README polish | — | S |

**M2 done when:** fresh user installs, completes onboarding, presses hotkey, says *"open a PR for this branch"* in a Claude-Code-configured repo, and a PR appears.

---

## M2.5 — LLM transcript polish _(next-priority chunk after v0 launch)_

User-flagged priority on 2026-04-27. Stronger transcript cleanup via a
small local LLM, off by default but a one-toggle opt-in. Goal: a transcript
the user can press send on without re-reading. Lays the LLM infra that
SPEC-006 (agent dispatch) builds on.

| | Task | Spec | Effort |
|---|---|---|---|
| 🔵 | `TextPolishEngine` protocol + `OllamaPolishEngine` (HTTP) | SPEC-007 | S |
| 🔵 | `MLXLMPolishEngine` (in-process via mlx-swift-lm) | SPEC-007 | M |
| 🔵 | Settings → Polish pane (engine picker, model picker) | SPEC-007 | S |
| 🔵 | Bench polish WER delta + latency on `openquack-bench` | SPEC-007 | S |
| 🔵 | Domain-term accuracy bench (e.g. "Claude Code" not "cloud code") | SPEC-007 | S |
| 🔵 | "Send-confidence" bench: % of utterances clean enough to ship as-is | SPEC-007 | S |

## M3 — Agents + polish

| | Task | Spec | Effort |
|---|---|---|---|
| ⚪ | `OllamaAgent` (local HTTP) | SPEC-006 ext | S |
| ⚪ | `MLXLMAgent` (in-process via mlx-swift-lm) | SPEC-006 ext | M |
| ⚪ | Active-app context: feed the foreground app + focused input field's surrounding text into Whisper's prompt bias and the polish/agent prompt, so domain terms resolve correctly and the agent has the same context the user does (sequenced after M2.5) | new SPEC | M |
| 🔵 | Stream transcription for long audio (>~30s): chunk while recording so wait time after stop stays flat. Perf-oriented; user never sees partials. | SPEC-012 | L |
| ⚪ | Live partial transcripts in the pill/popover while speaking — UX-facing (lets the user see what's being captured, catch mistakes early). Distinct from the perf streaming above; could share infra. | new SPEC | M |
| 🔵 | Usage stats pane: words dictated via OpenQuack, time saved (vs. typing baseline), total audio processed. Local-only, opt-in display. | SPEC-013 | S |
| 🔵 | Local audio + transcript history: keep recent recordings on disk so a crash/failure mid-long-utterance doesn't force the user to repeat 1–2 minutes of speech. Local-only, retention cap, easy purge. Privacy selling point — works offline, nothing leaves the device. | SPEC-014 | M |
| ⚪ | Code signing + notarisation | — | S |
| ⚪ | Sparkle auto-update | — | S |
| ⚪ | Demo gif + landing page (GitHub Pages) | — | S |

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
