# SPEC-036 — Recording & transcription diagnostics + recording-health

## Goal

Make the intermittent "transcription stops mid-recording, the waveform freezes,
and only a partial transcript comes back" class of bug **diagnosable** — and turn
its most likely trigger from a silent freeze into a clean, finished result.

Concretely:

1. **Structured logging** across the capture → stream → transcribe path so a
   single recording leaves a readable trail (lifecycle, per-chunk timing/RTF,
   language decisions, errors).
2. **Recording-health check**: compare wall-clock duration against the audio the
   tap actually delivered. A large shortfall means the engine stopped feeding the
   tap mid-recording — the freeze signature — and is flagged automatically.
3. **Graceful interruption handling**: observe `AVAudioEngineConfigurationChange`
   (device/route change, the usual trigger) and auto-stop-and-transcribe instead
   of freezing.
4. **Attachable bug reports**: a diagnostics `.txt` (app/OS/chip, last-recording
   wall-vs-captured, chunk count/failures, RTF, detected language, recent events)
   written and revealed in Finder from the existing "Report Bug" (SPEC-039) and
   "Send feedback" (SPEC-018) entry points.

## Background

The capture tap (`AudioRecorder`) is the single driver of three things in one
closure: the WAV write, the level meter (waveform), and the streaming frames fed
to `StreamingTranscriber`. If the tap stops firing, **all three stall together** —
which is exactly the reported triad. `AVAudioEngine` silently stops its tap when
the input route/format changes (Bluetooth connect/disconnect, device switch,
sample-rate change, sleep/wake), and there is currently no observer to notice,
recover, or even log it. The bug is environment-triggered, so it is hard to
reproduce and hard to attribute to a release.

There is no per-recording instrumentation today, so "slow" / "inaccurate" reports
(e.g. SPEC-035's per-chunk language re-detection) can't be confirmed from a user's session either.

## Mechanism

### Captured-vs-wall

`AudioRecorder` already exposes `elapsedSeconds` (wall clock since `start`). Add a
captured-frame counter incremented in the tap closure → `capturedSeconds`
(frames ÷ input sample rate). On stop, `RecordingHealth.assess(wall, captured)`
flags `.incompleteCapture` when the shortfall is ≥ 2 s **and** captured < 85 % of
wall (tolerances keep short clips and normal teardown rounding from
false-positiving).

### Interruption → graceful stop

`AudioRecorder` registers a `.AVAudioEngineConfigurationChange` observer bound to
its engine. The notification **also fires for benign changes that leave input
capture intact** (default output-device change, Bluetooth codec renegotiation,
sample-rate settle), so the handler only treats it as an interruption when
`engine.isRunning == false` — otherwise auto-stopping would truncate a long
dictation on a harmless route change. When the engine genuinely stopped it logs a
warning and invokes `interruptionHandler` (main queue); the app sets that handler
to auto-stop-and-transcribe while in `.recording`, surfacing "Recording
interrupted by an audio device change." This fails safe: a real stop that still
briefly reports running falls back to the prior freeze, which `capturedSeconds` +
the logged event still surface. The observer is removed before our own
`engine.stop()` so teardown doesn't re-enter it.

> Out of scope: restarting the engine and *continuing* capture across the change
> (the WAV is opened in the pre-change format; reinstalling the tap with a new
> format risks a write mismatch). Tracked as a follow-up.

### Logging

`Diagnostics` wraps `os.Logger` (subsystem `org.openquack.OpenQuack`, categories
`recording`/`streaming`/`transcription`/`app`) and mirrors every line into a
bounded in-memory ring (cap 300) so the bug-report flow can dump recent events as
plain text — users won't run `log show`.

### Diagnostics file

`DiagnosticsReport.render(...)` (pure) builds the report text. The app writes it to
`~/Library/Logs/OpenQuack/diagnostics-<timestamp>.txt` and reveals it in Finder
(`activateFileViewerSelecting`) so it can be dragged into a GitHub issue.

## Privacy impact

Preserves the `docs/VISION.md` contract. No audio, transcript text, or network IO
is added. The diagnostics file contains only durations, counts, RTF, a detected
language code, app/OS/chip strings, and event labels — **no transcript content** —
and is written locally; the user chooses whether to attach it.

## Acceptance criteria

- [ ] `RecordingHealth.assess` returns `.incompleteCapture` for wall 90 s /
      captured 20 s, and `.ok` for wall 10 s / captured 9.6 s and for wall 0.
      (unit test)
- [ ] `DiagnosticsReport.render` output contains an `INCOMPLETE` marker when health
      is incomplete, and includes RTF and chunk counts. (unit test)
- [ ] `Diagnostics` ring buffer never exceeds its capacity and returns events in
      order. (unit test)
- [ ] Switching the input device mid-recording (e.g. connect AirPods) logs an
      `AVAudioEngineConfigurationChange` event. **First confirm the premise**: does
      the log say the engine STOPPED or "still running"? If it stopped, the
      recording auto-stops and pastes the partial transcript with the "interrupted"
      status — no frozen waveform. If it stays running, capture continues
      uninterrupted (no truncation). (manual — this is the load-bearing test; it
      both verifies the freeze cause and exercises the interruption path.) (manual)
- [ ] After a recording, `log show --predicate 'subsystem == "org.openquack.OpenQuack"'`
      shows recording start/stop, per-chunk RTF, and the wall-vs-captured summary.
      (manual)
- [ ] "Report Bug" (crash alert) and "Send feedback…" both write and reveal a
      `diagnostics-*.txt` in `~/Library/Logs/OpenQuack/`. (manual)
- [ ] `swift build && swift test` green.

## Out of scope

- Restart-and-continue capture across a config change (follow-up).
- Any auto-uploader / telemetry / network reporting — the file is local + manual.
- Re-tuning SPEC-035's per-chunk detection cost; this spec only *measures* it.
