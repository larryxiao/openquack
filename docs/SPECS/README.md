# Specs

Every meaningful change in OpenQuack cites a SPEC. This directory is the source of truth for *what* we build and *why*.

Conventions:

- File names: `SPEC-<NNN>-<kebab-name>.md`.
- IDs are global, monotonic, and stable. Renumbering is forbidden once a spec is referenced by a PR.
- New spec? File the `Spec proposal` issue first; merging the spec is a separate PR from any implementation.
- **Every spec must include an `## Acceptance criteria` section** that states the clear goal and how to validate it — a user-visible behaviour ("pastes within 200 ms of hotkey release"), a measurable metric ("WER ≤ 6.5 % on `bench/corpus/noisy`"), or explicit manual steps a reviewer can follow. If neither the goal nor the validation method can be written down, the spec is still a proposal, not a contract.

## Index

Every spec listed here has been ratified (the spec PR merged). The **Status**
column tracks *implementation* state, which is what the roadmap drives against:

- **shipped** — implemented and merged to `main`
- **partial** — partly implemented; remaining work noted in the spec
- **draft** — accepted spec, not yet built
- **parked** — superseded or on hold

| ID | Title | Status | Milestone |
|---|---|---|---|
| [SPEC-001](SPEC-001-voice-capture.md) | Voice capture | shipped | M2 |
| [SPEC-002](SPEC-002-transcription.md) | Transcription | shipped | M1 |
| [SPEC-003](SPEC-003-hotkey.md) | Global hotkey | shipped | M2 |
| [SPEC-003a](SPEC-003a-fn-key.md) | `fn` / Globe key as a bindable hotkey | shipped | M2 |
| [SPEC-004](SPEC-004-overlay.md) | Recording overlay | shipped | M2 |
| [SPEC-005](SPEC-005-paste.md) | Paste at cursor | shipped | M2 |
| [SPEC-006](SPEC-006-agent-dispatch.md) | Agent dispatch (closed-loop sessions) | draft | M2 |
| [SPEC-007](SPEC-007-llm-polish.md) | LLM transcript polish | draft | M2.5 |
| [SPEC-007a](SPEC-007a-gemma-bench.md) | Gemma 4 polish bench addendum | draft | M2.5 |
| [SPEC-007b](SPEC-007b-rewrite-ux.md) | Intelligent rewrite UX | draft | M2.5 |
| [SPEC-008](SPEC-008-in-context-rewrite.md) | In-context transcript rewrite | draft | M3 |
| [SPEC-010](SPEC-010-app-shell.md) | App shell | shipped | M2 |
| [SPEC-011](SPEC-011-update-flow.md) | Update flow: notification + one-click upgrade | shipped | M2 |
| [SPEC-012](SPEC-012-streaming-transcription.md) | Streaming transcription (perf-only chunking) | shipped | M3 |
| [SPEC-013](SPEC-013-usage-stats.md) | Usage stats pane | shipped | M3 |
| [SPEC-014](SPEC-014-local-history.md) | Local audio + transcript history | shipped | M3 |
| [SPEC-015](SPEC-015-release-channels.md) | Release channels (alpha / beta / stable) | partial | M3 |
| [SPEC-016](SPEC-016-distilled-polish-model.md) | Distilled polish model (1B from Gemma 4) | parked | M2.5 |
| [SPEC-018](SPEC-018-feedback-menu.md) | Send-feedback menu item | shipped | M3 |
| [SPEC-019](SPEC-019-i18n.md) | App localisation (i18n) | draft | M3 |
| [SPEC-020](SPEC-020-copy-transcript-button.md) | One-click "Copy" button for the last transcript | shipped | M3 |
| [SPEC-021](SPEC-021-mandarin-autodetect-bench-fix.md) | Mandarin auto-detect failure: bench coverage + fix | draft | M1/M2 |
| [SPEC-022](SPEC-022-custom-dict-autolearn.md) | Custom dictionary auto-learn from user corrections | draft | M3 |
| [SPEC-023](SPEC-023-launch-at-login.md) | Launch at login | shipped | M2 |
| [SPEC-024](SPEC-024-per-app-tone.md) | Per-app tone profiles | draft | M3 |
| [SPEC-025](SPEC-025-code-signing-notarisation.md) | Code signing + notarisation | partial | M2 |
| [SPEC-026](SPEC-026-sparkle-auto-update.md) | Sparkle auto-update | partial | M2 |
| [SPEC-027](SPEC-027-demo-gif-landing.md) | README demo gif + landing-page polish | draft | M2 |
| [SPEC-028](SPEC-028-dictation-distribution.md) | Dictation distribution + personal performance stats | shipped | M3 |
| [SPEC-029](SPEC-029-ane-cache-only-model.md) | ANE-cache-only model footprint (investigation) | draft | M3 |
| [SPEC-030](SPEC-030-ane-cache-volunteer-bench.md) | ANE cache footprint: volunteer measurement campaign | draft | M3 |
| [SPEC-031](SPEC-031-agent-kickoff.md) | Agent kickoff (one-shot voice-to-action) | shipped | M2 |
| [SPEC-031a](SPEC-031a-voice-reply.md) | Voice reply to live agent sessions | draft | M2 |
| [SPEC-032](SPEC-032-engine-prompt-token-cache.md) | Engine prompt-token cache (offline path parity) | draft | M1 |

> Next free spec IDs: **SPEC-033, SPEC-034** (reserved for the two open docs PRs
> #41 Pages analytics → 033 and #42 install-count → 034, pending renumber). IDs
> are global and monotonic — never reuse 028/029/031/032.

## Spec lifecycle

```
proposal issue ──► draft PR adds spec ──► ratified (PR merged)
                                              │
                          ┌───────────────────┴──────────────────┐
                          │                                       │
                  superseded by SPEC-NNN              archived (no longer relevant)
```

A spec at `ratified` may still be amended; small edits are fine within an
implementation PR if they don't change semantics. Material changes are their
own PR.
