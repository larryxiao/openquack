# AGENTS.md

How AI agents (and humans) should contribute to OpenQuack. Most rules apply equally to both — humans can ignore the bits about advisor calls.

## Posture

- **Specs are the contract.** Every PR cites a `SPEC-XXX`. If no spec covers your change, write the spec first (one PR adds the spec; a follow-up PR implements).
- **Atomic PRs.** One spec, one milestone task. If your work touches multiple concerns, split it.
- **Tests are non-optional.** Touch a metric → bench delta documented in the PR. Touch logic → unit test added. Touch UX → the PR describes how to repro manually.
- **Cite primary sources, not memory.** When you need WhisperKit specifics, read `.build/checkouts/argmax-oss-swift/Sources/WhisperKit/Core/...`. When you need bench math, read `Sources/OpenQuackKit/Metrics/`.
- **Do the work, don't narrate it.** PR descriptions describe *the change and why*, not *what you tried*.

## Before you start

1. Read [`docs/VISION.md`](docs/VISION.md), [`docs/ROADMAP.md`](docs/ROADMAP.md), this file. Skim [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).
2. Pick a 🔵 task in `ROADMAP.md`.
3. Read the cited SPEC under `docs/SPECS/`.

## Workflow

1. Open a **draft PR early** — even with just a one-line description and a stub change. Push small, test often.
2. Run before pushing (use Xcode's toolchain; the system `swift 6.1.x` lacks the `PreviewsMacros` plugin that `KeyboardShortcuts` depends on, so a bare `swift build` fails on a clean checkout):
   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
   ```
   CI uses the same toolchain, so the override matches reality.
3. If your change might affect transcription quality or latency, also:
   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run openquack-bench --models tiny --corpus bench/corpus/short
   ```
   and report the delta in the PR.
4. Mark the PR ready for review when CI is green and your tests cover the change.

## PR template (the required shape)

```
## SPEC: SPEC-XXX (Title)
## Milestone: M2

### Why
<one paragraph — what user-facing problem this solves>

### Change
<what you actually did, file-level if non-obvious>

### Tests
- [ ] unit test added: `OpenQuackKitTests.testFoo`
- [ ] `swift build && swift test` green
- [ ] (if relevant) bench delta: WER ↓ 0.4 pp at WhisperKit/small on M4-16GB

### Out of scope
<things explicitly deferred — link follow-up issues>
```

There's an enforced PR template at `.github/pull_request_template.md`. Filling it is not optional.

## When stuck

- **Errors recurring** — if you're a Claude agent, call `advisor`. Otherwise: open the PR with what you have and a `[BLOCKED]` comment describing the failure mode.
- **Spec ambiguous** — propose an amendment in the same PR if minor; open a separate spec PR if scope changes.
- **New requirement discovered** — *don't* expand scope. Open a follow-up issue and stay atomic.

## Hard rules — never without explicit human approval

- Force-push, branch deletes, history rewrites
- Skipping pre-commit hooks (`--no-verify`, `--no-gpg-sign`)
- Adding a network call in the dictation or agent-dispatch hot path that wasn't there before
- Committing model weights, audio samples, or transcripts to git (corpus stays gitignored)
- Adding a dependency without a spec-level note explaining why
- Anything that breaks the [privacy contract](docs/VISION.md#privacy-contract)

## Tooling assumed

- Swift 6.0+ / Xcode 16+
- macOS 13+ for bench, macOS 15+ for the eventual app
- Python 3.11+ in `.venv` for the lightning baseline (optional; only if touching that engine)
- `swift-format` (config TBD) — required once it lands

## CI

`.github/workflows/ci.yml` runs on push + PR:

1. `swift build`
2. `swift test`
3. `bench/corpus/fetch.sh` then `swift run openquack-bench --models tiny --corpus bench/corpus/short` as a smoke

A red CI is a hard block. Don't merge through.

## Glossary for agents new to the repo

- **OpenQuackKit** — the library. UI-free brain. Engines, metrics, audio, hotkey.
- **OpenQuackBench** — CLI that drives engine × model × corpus → reports.
- **OpenQuackCLI** — single-file transcribe for ad-hoc experiments.
- **OpenQuack.app** — the SwiftUI shell. Doesn't exist yet (M2).
- **Engine** — `WhisperKit`, `Lightning`, … swappable behind `TranscriptionEngine`.
- **Agent** — `Passthrough`, `ClaudeCode`, … swappable behind `Agent` (SPEC-006, draft).
- **Corpus** — `bench/corpus/{short,voices,multilingual,librispeech,noisy}/`. Audio gitignored, references tracked.
- **Host tag** — `M4-16GB`-style identifier for per-machine bench reports.
