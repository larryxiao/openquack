# Roadmap

Atomic tasks — every item cites a SPEC and maps to a PR. Agent contributors should claim a task by opening a draft PR; see [AGENTS.md](../AGENTS.md).

> **Reconciled against shipped code on 2026-05-29** (current release `v2.0.0-alpha.16`). Statuses below reflect what is actually on `main`, not what a spec proposed. The companion [spec index](SPECS/README.md) tracks the same implementation state per spec.

## Status

- 🟡 **in progress** — draft PR or open issue, or partly implemented
- 🔵 **spec** — `docs/SPECS/<id>.md` exists; ready to claim
- ⚪ **idea** — not specced yet
- 🟢 **done** — merged to `main`

---

## Adoption focus (current priority)

The product has a working foundation. The current cycle is about removing first-launch friction, fixing visible quality issues, and improving the surfaces new users land on — **not building more features**. Pick from this band first. Ordered by impact.

| | Task | Spec | Notes |
|---|---|---|---|
| 🟡 | **Code signing + notarisation** — kill the first-launch Gatekeeper "right-click → Open" dance | SPEC-025 | **Biggest install-success unlock, still not delivered.** Signing *capability* exists in `scripts/wrap_app.sh` (Developer-ID branch + hardened runtime + TSA timestamp), but **no notarisation is wired** (`notarytool`/`stapler` absent everywhere) and no shipped DMG is Developer-ID-signed — README/INSTALL still tell users to right-click→Open. **Blocked on a paid Apple Developer ID** ($99/yr account decision). Once that's cleared: add `notarytool submit --wait` + `stapler staple` to `make_dmg.sh`/release CI, then strip the Gatekeeper caveats. |
| 🔵 | **README demo gif** — strong first-impression artifact | SPEC-027 | S; cheap solo win. The landing-page-polish half is *already done* (og/twitter cards, banner in `docs/index.md`). The genuinely-missing deliverable is a looping ≤2 MB demo GIF at the top of README + landing page — no `*.gif/*.mp4` exists in-repo yet. |
| 🟡 | **Mandarin auto-detect fix** — visible quality bug (#17, open since 2026-05-09) | SPEC-021 | M. **No fix on `main` yet.** PR #20 (draft, CI green) banks only the categorical failure-mode *metrics baseline* + zh corpus — the user-facing fix (PR-2, model-layer language handling) is the actual deliverable. Land #20 as the baseline, then ship the fix. Pairs with #62 below. |
| 🟡 | **Sparkle auto-update** — existing users stay current without reinstalling | SPEC-026 | Far past spec-only: dependency + Updates pane + framework bundling all shipped (#40/#50/#49). But auto-install is a **deliberate no-op** — `SUPublicEDKey` omitted, `appcast.xml` ships zero items. To finish: generate EdDSA keys, commit the public key, sign + publish appcast items (PR-C). **Gated behind SPEC-025** (notarised signed builds) for a trustworthy update path. |
| 🔵 | Voice reply to live sessions — modifier-key + notification voice-reply action | SPEC-031a | S; spec merged (#54), zero implementation on `main`. Injection mechanism (`--resume -p` vs daemon socket) resolved in impl PR. |
| ⚪ | **Re-transcribe a past dictation from History** — recovery without re-speaking | — (#62) | New 2026-05-29 feature request. Re-run stored audio through transcription/polish from the History view, with optional explicit language + model override. Directly mitigates #17's wrong-language case; reuses local history (SPEC-014). Needs a spec; good retention item. |
| ⚪ | Submission tracking for awesome-mac / awesome-llm / awesome-swift lists | — | quiet but durable inbound |
| ⚪ | Quarterly bench refresh — durable artifact + monthly relaunch hook | — | leverages existing 5×2×177 bench |

### Pending docs PRs (renumber required)

Two spec-doc PRs are clean and CI-green but cite **already-assigned** SPEC numbers and must be renumbered to the next free monotonic IDs before merge. They cross-reference each other, so renumber as a coordinated pair; **do not rename the branches** (renaming an open PR head ref can close it).

| PR | Becomes | What | Action |
|---|---|---|---|
| #41 | SPEC-033 | Privacy-respecting Pages visitor analytics (GoatCounter) | Renumber 031→033; fix body "Adds SPEC-028"→033; its `SPEC-032` cross-ref → `SPEC-034`. Then merge. |
| #42 | SPEC-034 | Active-install count via Sparkle appcast hits (Cloudflare Worker) | Renumber 032→034; fix body "Adds SPEC-029"→034; its two `SPEC-031` cross-refs → `SPEC-033`. Then merge. Impl gated on SPEC-026. |

## Feature backlog (deferred until adoption signal improves)

These have SPECs and are ready to claim, but we're **holding new feature scope** until install + retention pipelines are strong enough to justify the surface area. Pick from here only when Adoption focus is empty.

| | Task | Spec | Notes |
|---|---|---|---|
| 🟡 | Custom dictionary auto-learn (PR-A as #32; PR-B/C deferred) | SPEC-022 | M. PR #32 (post-paste AXObserver + correction store) is CI-green and merge-clean but **on hold** — it sits in this deferred band and Adoption focus isn't empty. No auto-learn code is on `main`. (Distinct from the shipped static-dictionary seed, PR #59, made invisible again in alpha.16.) |
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
| 🔵 | Engine prompt-token cache — offline-path parity for `customWords` | SPEC-032 | S; perf-fix groundwork for re-shipping the dictionary seed default |
| 🔵 | Per-app tone profiles | SPEC-024 | M; needs SPEC-007 first |
| 🔵 | App localisation (i18n) — runtime UI strings (READMEs already translated) | SPEC-019 | M |
| 🔵 | ANE-cache-only model footprint (investigation) | SPEC-029 | S |
| 🔵 | ANE cache footprint: volunteer measurement campaign | SPEC-030 | S |
| ⚪ | `OllamaAgent` (local HTTP) | SPEC-006 ext | S |
| ⚪ | `MLXLMAgent` (in-process via mlx-swift-lm) | SPEC-006 ext | M |
| ⚪ | Active-app context: feed foreground app + focused field text into Whisper prompt bias and polish/agent prompt | — | M |
| ⚪ | Investigate streaming for medium-length (15–30s) audio: bench WER vs. wall-time at lower `targetChunkSeconds` | SPEC-012 ext | S |
| ⚪ | Live partial transcripts in pill/popover while speaking | — | M |
| ⚪ | System-audio capture (meeting mode) | — | ScreenCaptureKit |
| ⚪ | Action confirmation UI for high-risk agent calls | — | privacy gate |
| ⚪ | Per-agent transcript history pane (opt-in, local-only) | — | — |
| ⚪ | Linux / Windows ports | — | post-2.0 |

## Done

| | Task | Spec | Notes |
|---|---|---|---|
| 🟢 | Agent kickoff: voice-launched `claude --bg` session via separate hotkey — daemon-managed, notification-driven | SPEC-031 | shipped in v2.0.0-alpha.14 (#53); post-ship fixes #57/#58 |
| 🟢 | Update flow: install-aware banner + silent one-click brew upgrade (no Terminal, quit-first relaunch) | SPEC-011 | shipped via c193f0e; SemVer-precedence fix #61 |
| 🟢 | Copy button on the last-transcript card | SPEC-020 | merged in #18 |
| 🟢 | Send-feedback menu item — one click from status item to GitHub issue chooser | SPEC-018 | merged in #5 |
| 🟢 | Dictation distribution + personal performance stats (Longest dictation, avg realtime ×, length histogram) | SPEC-028 | merged in #45 |
| 🟢 | `fn` / Globe key as a bindable hotkey (bare fn or fn+key) — closes #23 | SPEC-003a | infra #28 (PR-A) + UI wiring a8371b8 (PR-B) |
| 🟢 | Launch at login (SMAppService toggle in Settings → General) — closes #29 | SPEC-023 | merged in #33 (reconcile) + #39 (UI) — *issue #29 still open, needs closing* |
| 🟢 | Recording overlay follows the cursor across monitors — closes #25 | SPEC-004 | merged in #27 |
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
