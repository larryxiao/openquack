# Specs

Every meaningful change in OpenQuack cites a SPEC. This directory is the source of truth for *what* we build and *why*.

Conventions:

- File names: `SPEC-<NNN>-<kebab-name>.md`.
- IDs are global, monotonic, and stable. Renumbering is forbidden once a spec is referenced by a PR.
- New spec? File the `Spec proposal` issue first; merging the spec is a separate PR from any implementation.

## Index

| ID | Title | Status | Milestone |
|---|---|---|---|
| [SPEC-001](SPEC-001-voice-capture.md) | Voice capture | draft | M2 |
| [SPEC-002](SPEC-002-transcription.md) | Transcription | ratified | M1 |
| [SPEC-003](SPEC-003-hotkey.md) | Global hotkey | draft | M2 |
| [SPEC-004](SPEC-004-overlay.md) | Recording overlay | draft | M2 |
| [SPEC-005](SPEC-005-paste.md) | Paste at cursor | draft | M2 |
| [SPEC-006](SPEC-006-agent-dispatch.md) | Agent dispatch | draft | M2 |
| [SPEC-010](SPEC-010-app-shell.md) | App shell | draft | M2 |

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
