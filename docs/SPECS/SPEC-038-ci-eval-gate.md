# SPEC-038 — CI eval-gate on the real corpora

**Status:** proposal

## Goal

Let CI fail a PR that regresses transcription quality or latency. Today
`ci.yml` runs `openquack-bench` at **tiny** on **short** only, because the
corpus audio is gitignored — so neither a human nor an agent can catch a WER or
RTF regression before merge. The live SPEC-035 work (slow / inaccurate
streaming reports) is exactly the class of regression that slips through. This
spec proposes a CI eval-gate: a fetchable curated corpus, a medium-model run
across multilingual + noisy + voices, PR thresholds with a stated no-regression
margin, and the delta reported in the PR per `AGENTS.md`.

Design-first: this PR adds the spec only; the workflow is a follow-up.

## Background

`.gitignore` excludes all corpus audio (`bench/corpus/**/*.wav` …), and
`AGENTS.md` makes committing audio samples a **hard rule** — forbidden without
explicit human approval. So the smoke in `ci.yml` is all CI can do as written.

The audio is *reproducible*, not lost: `bench/corpus/fetch.sh` regenerates the
synthetic buckets via macOS `say`, `fetch_librispeech.sh` pulls real human
speech from openslr.org, and `mix_noise.py` derives the noisy buckets. The
references (`*.txt`) are tracked. The gap is a *fixed* corpus CI can fetch and a
job that gates on it.

## Mechanism

### Corpus delivery — recommendation

Three options, with the tie broken by the hard rule:

- **git-LFS** — still commits audio to git. Collides with the `AGENTS.md`
  hard rule. **Rejected.**
- **Committed golden subset** — *literally* the forbidden thing (audio in the
  tree). Allowed **only** with explicit maintainer sign-off; named here for
  completeness, not recommended.
- **Hosted + cached fetch** — *recommended.* A fixed corpus tarball hosted out
  of tree (GitHub Release asset / object store), fetched in CI and restored from
  the Actions cache keyed by a **manifest hash**. Respects the hard rule (no
  audio in git), and gives the byte-stable inputs a WER gate needs.

A WER gate requires fixed inputs: `say`-regenerated audio drifts across runner
macOS image updates, producing phantom regressions. So the gate fetches a
*pinned* hosted corpus rather than regenerating it. The fetch verifies the
manifest hash before running.

### The eval job

A workflow (label- or nightly-triggered for the slow medium path, not every doc
PR) fetches the pinned corpus and runs at **medium** on the quality-relevant
buckets:

- `openquack-bench --models medium` on `multilingual`, `noisy`, `voices`
- `openquack-stream-bench --models medium` on the long / code-switch clips

Medium model weights are fetched + cached (committing weights is the same hard
rule), not vendored.

### Gating

- **WER — hard gate.** Per-bucket WER must not regress beyond a stated margin
  vs the committed baseline (e.g. ≤ +0.5 pp). WER is hardware-independent, so the
  shared `macos-15` runner is a valid judge.
- **RTF — soft gate, same-runner.** RTF is hardware-dependent; the runner is not
  comparable to the host-tagged `M4-16GB` numbers in `BENCHMARKS.md`. Gate RTF
  only against a *same-runner* baseline with a stated margin, host-tagged
  separately, or it flaps.
- **Report the delta in the PR** per `AGENTS.md` — WER/RTF per bucket vs baseline,
  posted as a comment, regardless of pass/fail.

## Privacy impact

Preserves the `docs/VISION.md` contract. The corpus is synthetic (`say` TTS),
public-domain (LibriSpeech, CC BY 4.0), and noise-augmented derivatives — no
user audio, no transcripts, no telemetry. Everything runs in CI on public data;
nothing touches the dictation hot path or a user's machine.

## Acceptance criteria

- [ ] CI fetches a pinned hosted corpus, verifies its manifest hash, and
      restores it from the Actions cache on a warm run — **no audio committed to
      git**. (CI log + `git ls-files | grep -c '\.wav$'` stays 0)
- [ ] The eval job runs `openquack-bench --models medium` on `multilingual`,
      `noisy`, and `voices`, and `openquack-stream-bench --models medium` on the
      long/code-switch clips. (CI log)
- [ ] A PR that pushes any bucket's WER beyond the stated margin **fails** the
      gate; a within-margin change passes. (manual: seed a deliberate
      regression)
- [ ] Every eval run posts a per-bucket WER/RTF delta vs baseline as a PR
      comment, pass or fail. (CI artifact + comment)
- [ ] RTF is gated only against a same-runner baseline, host-tagged separately
      from the `M4-16GB` BENCHMARKS numbers; a cold-runner RTF swing alone does
      not fail the gate. (CI config review)
- [ ] The slow medium path is label- or nightly-triggered, not run on every doc
      PR. (workflow trigger config)

## Out of scope

- **An end-to-end / app-behaviour test.** There is no test that drives the
  shipped app (hotkey → record → paste). This spec gates *engine* quality only;
  the e2e gap is a sibling follow-up, not solved here.
- **Committing the corpus or model weights to git** — forbidden by `AGENTS.md`;
  the committed-subset option needs explicit maintainer sign-off if ever taken.
- **The agent harness that consumes this gate** — that is **SPEC-037**.
- **Polish/bias bench gating** (`openquack-polish-bench` / `-bias-bench`) — add
  once the transcription gate is stable; out of scope here.