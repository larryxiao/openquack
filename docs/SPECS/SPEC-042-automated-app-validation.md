# SPEC-042 — Automated app-behaviour validation

## Goal

Ship releases confidently without a manual on-device pass. Validate the
record → transcribe → paste path, and especially the **freeze / partial-transcript
class** (audio tap stops mid-recording → frozen UI → truncated transcript), in CI
and locally — no human, no physical device-switching.

The freeze cost two rollbacks. Its fix (SPEC-036 graceful interruption + health)
is currently only verifiable by hand (switch a Bluetooth device mid-recording and
read Console). That gate is the bottleneck on every release; this spec removes it.

## Background

Unit tests cover pure logic (`RecordingHealth`, `DiagnosticsReport`, `rawRMS`,
word counting). The **live capture path** — `AudioRecorder`'s tap, the
`AVAudioEngineConfigurationChange` interruption handler, the app pump, and
`stopAndTranscribe` — has no automated coverage, because it's bound to a real
`AVAudioEngine` + microphone + hardware route changes.

## Mechanism — two increments

### Increment 1 (this PR): interruption-gate coverage

SPEC-036's interruption decision (config change → auto-stop **only** when
`engine.isRunning == false`; a benign reconfig that leaves capture running must
**not** cut a dictation short) was inlined in the observer closure and untested —
the most regression-prone line in the freeze fix. Extract it to
`AudioRecorder.handleConfigurationChange(engineRunning:)` (no behaviour change;
the observer now calls it) and unit-test both arms. Pairs with the existing
`RecordingHealth.assess` tests (captured-vs-wall shortfall) to cover the fix's two
load-bearing pieces.

### Increment 2 (follow-up): audio-injection app harness

A test seam, env-gated so a normal launch is byte-identical:

- **`OQ_TEST_AUDIO_FILE`** — instead of the mic tap, drive the *same* capture
  handlers (frame tally, level, frames, WAV write) from a WAV, at real-time or
  fast pace. Requires unifying the tap-block processing into one method both the
  real tap and the injector call (the tap's lock/sink design must be preserved —
  hence a careful follow-up, not bundled here).
- **Scripted control** via `DistributedNotificationCenter` (start / stop /
  simulate-interruption), registered only in test mode.
- **Observable outcomes**: transcript + `DiagnosticsReport.LastRecording` written
  as JSON to `OQ_TEST_RESULT_FILE`; auto-paste disabled in test mode (never type
  into a runner's focused app).
- **`scripts/app_test.sh`**: build, launch with the env vars, wait for model warm,
  drive record → stop on a known WAV, assert transcript non-empty + word-overlap
  vs the paired reference + no incomplete-capture; then drive a
  simulated-interruption run and assert graceful auto-stop + the incomplete-capture
  flag. Non-zero exit on failure. CI-runnable (model fetch cached; cross-refs
  SPEC-038's corpus/model delivery).

## Privacy impact

Preserves the `docs/VISION.md` contract. The test seam is env-gated and inert in
any normal launch; no audio, transcripts, or network are added. Increment 1 is a
pure refactor + tests.

## Acceptance criteria

- [ ] `AudioRecorder.handleConfigurationChange(engineRunning: false)` fires
      `interruptionHandler`; `(engineRunning: true)` does **not**; nil handler is a
      no-op. (unit test, this PR)
- [ ] The observer wiring is unchanged in behaviour (still bound to the engine,
      main-queue, fires only on a real stop). (code review)
- [ ] `swift build && swift test` green.
- [ ] (Increment 2) `scripts/app_test.sh` drives record→transcribe on a WAV with
      no hardware and exits non-zero on a freeze/partial regression. (follow-up)

## Out of scope

- Increment 2's injection seam + runner (documented above; separate PR — it
  touches the deadlock-sensitive real-time tap and warrants its own review).
- Engine *quality* gating (WER/RTF) — that's **SPEC-038**.
