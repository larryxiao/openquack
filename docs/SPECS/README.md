# Specs

Every meaningful change in OpenQuack cites a SPEC. This directory is the source of truth for *what* we build and *why*.

Conventions:

- File names: `SPEC-<NNN>-<kebab-name>.md`.
- IDs are global, monotonic, and stable. Renumbering is forbidden once a spec is referenced by a PR.
- New spec? File the `Spec proposal` issue first; merging the spec is a separate PR from any implementation.
- **Every spec must include an `## Acceptance criteria` section** that states the clear goal and how to validate it — a user-visible behaviour ("pastes within 200 ms of hotkey release"), a measurable metric ("WER ≤ 6.5 % on `bench/corpus/noisy`"), or explicit manual steps a reviewer can follow. If neither the goal nor the validation method can be written down, the spec is still a proposal, not a contract.

## Index

| ID | Title | Status | Milestone |
|---|---|---|---|
| [SPEC-001](SPEC-001-voice-capture.md) | Voice capture | draft | M2 |
| [SPEC-002](SPEC-002-transcription.md) | Transcription | ratified | M1 |
| [SPEC-003](SPEC-003-hotkey.md) | Global hotkey | draft | M2 |
| [SPEC-003a](SPEC-003a-fn-key.md) | `fn` / Globe key as a bindable hotkey | draft | M2 |
| [SPEC-004](SPEC-004-overlay.md) | Recording overlay | draft | M2 |
| [SPEC-005](SPEC-005-paste.md) | Paste at cursor | draft | M2 |
| [SPEC-006](SPEC-006-agent-dispatch.md) | Agent dispatch | draft | M2 |
| [SPEC-007](SPEC-007-llm-polish.md) | LLM transcript polish | draft | M2.5 |
| [SPEC-007a](SPEC-007a-gemma-bench.md) | Gemma 4 polish bench addendum | draft | M2.5 |
| [SPEC-007b](SPEC-007b-rewrite-ux.md) | Intelligent rewrite UX | draft | M2.5 |
| [SPEC-008](SPEC-008-in-context-rewrite.md) | In-context transcript rewrite | draft | M3 |
| [SPEC-010](SPEC-010-app-shell.md) | App shell | draft | M2 |
| [SPEC-011](SPEC-011-update-flow.md) | Update flow | draft | M2 |
| [SPEC-012](SPEC-012-streaming-transcription.md) | Streaming transcription (perf) | draft | M3 |
| [SPEC-013](SPEC-013-usage-stats.md) | Usage stats pane | draft | M3 |
| [SPEC-014](SPEC-014-local-history.md) | Local audio + transcript history | draft | M3 |
| [SPEC-016](SPEC-016-distilled-polish-model.md) | Distilled polish model (1B from Gemma 4) | draft | M2.5 |
| [SPEC-029](SPEC-029-ane-cache-only-model.md) | ANE-cache-only model footprint (investigation) | draft | M3 |
| [SPEC-030](SPEC-030-ane-cache-volunteer-bench.md) | ANE cache footprint: volunteer measurement campaign | draft | M3 |

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
