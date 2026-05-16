# Roadmap

Atomic tasks — every item cites a SPEC and maps to a PR. Agent contributors should claim a task by opening a draft PR; see [AGENTS.md](../AGENTS.md).

## Status

- 🟡 **in progress** — draft PR or open issue
- 🔵 **spec** — `docs/SPECS/<id>.md` exists; ready to claim
- ⚪ **idea** — not specced yet
- 🟢 **done** — merged

---

## Adoption focus (current priority)

The product has a working foundation. The current cycle is about removing first-launch friction, fixing visible quality issues, and improving the surfaces new users land on — **not building more features**. Pick from this band first.

| | Task | Spec | Notes |
|---|---|---|---|
| 🔵 | Code signing + notarisation — kill first-launch Gatekeeper "right-click → Open" dance | SPEC-025 | S; biggest install-success unlock |
| 🔵 | Sparkle auto-update — existing users stay on latest without reinstalling | SPEC-026 | S; pairs with the brew cask path |
| 🔵 | README demo gif + landing-page polish — strong first-impression artifact | SPEC-027 | S |
| 🟡 | Mandarin auto-detect fix: visible quality bug surfaced by issue #17 | SPEC-021 | PR #20 (bench) draft |
| ⚪ | Submission tracking for awesome-mac / awesome-llm / awesome-swift lists | — | quiet but durable inbound |
| ⚪ | Quarterly bench refresh — durable artifact + monthly relaunch hook | — | leverages existing 5×2×177 bench |

## Feature backlog (deferred until adoption signal improves)

These have SPECs and are ready to claim, but we're **holding new feature scope** until install + retention pipelines are strong enough to justify the surface area. Pick from here only when Adoption focus is empty.

| | Task | Spec | Notes |
|---|---|---|---|
| 🟡 | Custom dictionary auto-learn (PR-A in flight as #32; PR-B/C deferred) | SPEC-022 | M |
| 🔵 | Agent session protocol + `PassthroughAgent` + conversation panel | SPEC-006 | M |
| 🔵 | `ClaudeCodeAgent` — long-lived subprocess, streaming events | SPEC-006 | M |
| 🔵 | Approval prompt UX (overlay morph + buttons) | SPEC-006 | S |
| 🔵 | Settings — Privacy + Agent panes | SPEC-006 | S; lands with agent impl |
| 🔵 | `TextPolishEngine` protocol + `OllamaPolishEngine` (HTTP) | SPEC-007 | S |
| 🔵 | `MLXLMPolishEngine` (in-process via mlx-swift-lm) | SPEC-007 | M |
| 🔵 | Settings → Polish pane (engine picker, model picker) | SPEC-007 | S |
| 🔵 | Bench polish WER delta + latency on `openquack-bench` | SPEC-007 | S |
| 🔵 | Domain-term accuracy bench (e.g. "Claude Code" not "cloud code") | SPEC-007 | S |
| 🔵 | "Send-confidence" bench: % of utterances clean enough to ship as-is | SPEC-007 | S |
| 🔵 | Per-app tone profiles | SPEC-024 | M; needs SPEC-007 first |
| ⚪ | `OllamaAgent` (local HTTP) | SPEC-006 ext | S |
| ⚪ | `MLXLMAgent` (in-process via mlx-swift-lm) | SPEC-006 ext | M |
| ⚪ | Active-app context: feed foreground app + focused field text into Whisper prompt bias and polish/agent prompt | — | M |
| ⚪ | Investigate streaming for medium-length (15–30s) audio: bench WER vs. wall-time at lower `targetChunkSeconds` | SPEC-012 ext | S |
| ⚪ | Live partial transcripts in pill/popover while speaking | — | M |
| ⚪ | System-audio capture (meeting mode) | — | ScreenCaptureKit |
| ⚪ | Multilingual UI strings | — | follow Whisper language menu |
| ⚪ | Action confirmation UI for high-risk agent calls | — | privacy gate |
| ⚪ | Per-agent transcript history pane (opt-in, local-only) | — | — |
| ⚪ | Linux / Windows ports | — | post-2.0 |

## Done

| | Task | Spec | Notes |
|---|---|---|---|
| 🟢 | Dictation distribution + personal performance stats (Longest dictation, avg realtime ×, length histogram) | SPEC-028 | merged in #45 |
| 🟢 | `fn` / Globe key as a bindable hotkey (bare fn or fn+key) — closes #23 | SPEC-003a | merged in #28 |
| 🟢 | Launch at login (SMAppService toggle in Settings → General) — closes #29 | SPEC-023 | merged in #33 (reconcile) + #39 (UI) |
| 🟢 | Recording overlay follows the cursor across monitors — closes #25 | SPEC-004 | merged in #27 |
| 🟢 | Send-feedback menu item — one click from status item to GitHub issue chooser | SPEC-018 | merged in #5 |
| 🟢 | Usage stats pane: words dictated, time saved, audio processed — local-only | SPEC-013 | merged in c91da06 |
| 🟢 | Local audio + transcript history — local-only, retention cap | SPEC-014 | merged in c91da06 |
| 🟢 | Stream transcription for long audio (>~30s) — chunk while recording | SPEC-012 | perf; user never sees partials |
| 🟢 | App shell — SwiftPM target, menu bar, About panel | SPEC-010 | — |
| 🟢 | Audio capture — AVAudioEngine → 16 kHz mono WAV | SPEC-001 | — |
| 🟢 | Global hotkey (⌃⇧Space toggle, KeyboardShortcuts pkg) | SPEC-003 | — |
| 🟢 | Record → WhisperKit `medium` (en) → transcript in popover + clipboard | SPEC-002 | — |
| 🟢 | Floating recording-state pill (top-centre, click-through) | SPEC-004 | — |
| 🟢 | CGEvent ⌘V auto-paste at cursor (Accessibility prompt + clipboard fallback) | SPEC-005 | — |
| 🟢 | Onboarding flow (Welcome → Mic → Paste → Hotkey → Done) | — | — |
| 🟢 | Settings scene MVP (General / Models / Shortcut / About) | — | — |
| 🟢 | Smart text post-processing (capitalise, punct, fillers) | — | — |
| 🟢 | Live level meter + push-to-talk | SPEC-001 ext | — |
| 🟢 | VAD auto-stop + sounds + custom dictionary | — | — |
| 🟢 | App icon (procedural cream-gradient duck) | — | — |
| 🟢 | DMG + Homebrew cask + README polish | — | — |
| 🟢 | WhisperKit engine | SPEC-002 | primary; Apple Silicon Metal |
| 🟢 | Lightning engine (Python subprocess) | SPEC-002 | bench-only baseline |
| 🟢 | Metrics: WER / CER / RTF / RSS / cold-start | SPEC-002 | `OpenQuackKit/Metrics/` |
| 🟢 | Corpus: 177 clips (TTS / multilingual / LibriSpeech / noise-aug) | — | `bench/corpus/` |
| 🟢 | Bench rerun on enriched corpus → BENCHMARKS.md | — | M4/16GB matrix |
| 🟢 | `openquack-cli` (single-file transcribe) | SPEC-002 | — |
| 🟢 | SPM scaffolding (Kit + bench + CLI) | — | `Package.swift`, three targets |
| 🟢 | Vision + roadmap + AGENTS.md + spec scaffold | — | — |

---

## How to claim a task

1. **Pick from Adoption focus first.** Move to Feature backlog only if Adoption is empty.
2. Open an issue using the *Agent Task* template; mark yourself as owner.
3. Read the cited SPEC.
4. Open a draft PR within ~24h naming the task in the title.
5. Follow [AGENTS.md](../AGENTS.md) for PR shape and required tests.
