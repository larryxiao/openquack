# SPEC-012 — Streaming transcription (perf-only chunking)

**Status:** draft (M3)
**Owner:** `OpenQuackKit/Streaming/`
**Last updated:** 2026-04-30

## Goal

A 90-second voice memo feels the same as a 10-second one — paste latency
stays roughly flat after the user releases the hotkey, regardless of
utterance length.

We get there by transcribing **chunks of the audio while recording is
still in flight**, so by the time the user stops speaking, only the
trailing tail (a few seconds at most) still needs to be processed. The
final transcript is assembled from the chunked results plus the tail.
This is a **perf-oriented** internal pipeline change. The user **never
sees partial transcripts** — the overlay still shows
`recording → transcribing → done`, the only difference is that
`transcribing` resolves in roughly constant time instead of growing
linearly with audio length.

## Why this matters

WhisperKit's runtime is bounded by `defaultWindowSamples = 480_000`
(30 s @ 16 kHz, see `Models.swift:1543`). For audio longer than one
window, the offline `transcribe(audioArray:)` path already chunks
internally (see "Primary-source notes"), but only **after** recording
ends — every second of audio adds proportional wall time to the
post-stop wait. On a baseline M4/16GB at WhisperKit-medium ~0.22× RTF,
a 2-minute dictation costs ~26 s of post-stop wait. That breaks the
"send without re-reading" quality bar from `VISION.md`: the user has
already moved on.

Streaming the chunk transcribes *during* recording reduces post-stop
wait to "tail-chunk transcribe + assembly" — bounded by the chunk
size, independent of total length.

## Non-goals

- **Live partial transcript display in the overlay or popover.** That's
  the separate roadmap item right below this one in M3 ("Live partial
  transcripts in the pill/popover while speaking — UX-facing"). The
  chunking infra in this spec MAY be reused by that future spec, but
  this spec commits to **zero UI changes**. The overlay stays exactly
  the four states from SPEC-004 (`recording → transcribing → dispatching
  → done`); the user has no way to tell streaming is happening.
- Speaker diarisation across chunks (separate spec, M4).
- Restructuring `AudioRecorder` (SPEC-001). We add a frames-callback
  hook; we do not change capture behaviour or output format.
- Streaming output from the agent (SPEC-006 already covers that).
- Per-chunk polish (see "Polish interaction" — polish stays whole-utterance batch).
- Falling back to streaming for *every* utterance. Short audio
  (<≈ 30 s) is faster end-to-end via the existing offline path; the
  streaming path is opt-in by duration.

## Primary-source notes (read before designing)

These are the WhisperKit surfaces this spec builds on. Conclusions in
this spec must trace back here, not to memory.

- `WhisperKit.transcribe(audioArray:decodeOptions:callback:segmentCallback:)`
  — `Sources/WhisperKit/Core/WhisperKit.swift:896`. The main entry
  point. Already chunks internally when `decodeOptions.chunkingStrategy
  == .vad` and `audioArray.count > windowSamples`.
- `ChunkingStrategy` — `Sources/WhisperKit/Core/Models.swift:362`.
  Today: `.none | .vad`. Drives the offline VAD chunker.
- `VADAudioChunker.chunkAll(audioArray:maxChunkLength:decodeOptions:)`
  — `Sources/WhisperKit/Core/Audio/AudioChunker.swift:66`. Splits a
  full buffer at the middle of the longest silence past the midpoint
  of each window. We can reuse the same idea online.
- `EnergyVAD` / `VoiceActivityDetector` —
  `Sources/WhisperKit/Core/Audio/EnergyVAD.swift`,
  `Sources/WhisperKit/Core/Audio/VoiceActivityDetector.swift`.
  `voiceActivity(in:)`, `findLongestSilence(in:)`,
  `voiceActivityIndexToAudioSampleIndex(_:)` — everything we need to
  pick a cut point at runtime.
- `AudioStreamTranscriber` —
  `Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift`. Does
  realtime streaming with confirmed/unconfirmed segments. **We do
  not use it directly.** It owns its own audio source
  (`audioProcessor.startRecordingLive`), surfaces partial UI state
  (`currentText`, `unconfirmedSegments`), and bypasses our
  `AudioRecorder` (SPEC-001). It's the right design for live UI; it
  is the wrong design for our perf-only goal.
- `WhisperKit` instances are reusable across `transcribe` calls — the
  loaded model is the expensive part, and `WhisperKitEngine` already
  holds a single `pipe`. Streaming reuses the same `pipe`.

Implication: the right shape is a new `StreamingTranscriber` actor in
`OpenQuackKit/Streaming/` that consumes float frames from a frames
callback on `AudioRecorder`, owns a sliding `[Float]` buffer plus an
`EnergyVAD`, dispatches sealed chunks to the existing `WhisperKit`
pipe, and assembles results in order.

## Public surface (sketch)

```swift
public actor StreamingTranscriber {
    /// Tunables. Defaults assume WhisperKit-medium on M-series 16 GB.
    public struct Config: Sendable {
        /// Minimum audio duration before streaming kicks in. Below this,
        /// the engine just transcribes the full buffer at stop and skips
        /// chunking entirely (offline path is faster end-to-end for short
        /// utterances).
        public var streamingThreshold: TimeInterval = 30
        /// Target chunk length. Cuts happen at the next silence past
        /// this mark, never before.
        public var targetChunkSeconds: TimeInterval = 20
        /// Maximum chunk length — if no silence found by this point,
        /// force-cut anyway (rare on natural speech, common on monologues).
        public var maxChunkSeconds: TimeInterval = 28
        /// VAD energy threshold for silence detection. EnergyVAD default.
        public var silenceEnergyThreshold: Float = 0.02
        /// Cap on in-flight chunk transcribes. Bounds memory/CPU.
        public var maxInFlightChunks: Int = 1
    }

    public init(engine: WhisperKitEngine, config: Config = .init())

    /// Begin a streaming session. Resets internal state. Caller wires
    /// `appendFrames` to AudioRecorder's frames callback (see SPEC-001
    /// extension below).
    public func begin(language: String?, customWords: String?) async

    /// Feed PCM frames captured at the recorder's native rate. The
    /// transcriber resamples internally to 16 kHz (mirrors what
    /// `WhisperKitEngine.transcribe(audioFile:)` does today via
    /// WhisperKit's own AudioProcessor).
    public func appendFrames(_ samples: [Float], sampleRate: Double)

    /// Block until pending chunks finish, transcribe the trailing tail,
    /// and return the assembled transcript. Equivalent in shape to
    /// `WhisperKitEngine.transcribe`'s return value.
    public func finish() async throws -> EngineTranscription

    /// Discard everything; cancel in-flight chunk transcribes. Safe at
    /// any time. After cancel, `begin` is required before reuse.
    public func cancel() async
}
```

And a minimal extension to SPEC-001 — additive, no behavioural change
to existing callers:

```swift
extension AudioRecorder {
    /// Emitted on the audio thread for every captured tap buffer (~10–20 ms
    /// at typical input rates). Set before `start()`. Called with raw
    /// float32 samples in the input device's native rate; consumers must
    /// resample if they need 16 kHz.
    public var framesHandler: (([Float], Double) -> Void)? { get set }
}
```

`framesHandler` is opt-in; existing dictation-only callers leave it
nil and pay nothing. The streaming app wires it to
`StreamingTranscriber.appendFrames`.

## Behaviour

### Chunk boundary strategy

**Default — silence-aware sliding window.** As frames arrive, the
buffer grows. Once `buffer.count ≥ targetChunkSeconds * 16_000`, run
`EnergyVAD.voiceActivity(in:)` over the most recent `targetChunkSeconds
... maxChunkSeconds` of buffered audio. If `findLongestSilence(in:)`
returns a hit, cut at that silence's midpoint (matching
`VADAudioChunker.splitOnMiddleOfLongestSilence`'s behaviour). If no
silence by `maxChunkSeconds`, force-cut at `maxChunkSeconds` — the
window-internal seek logic in WhisperKit handles non-silent boundaries,
just at slightly higher hallucination risk on the boundary word.

The cut produces a sealed `Chunk { startSecondsInUtterance, samples:
[Float] }` which is appended to the in-flight queue.

**Why VAD-midpoint and not fixed window**: same reason WhisperKit's
offline chunker does it — silence-cuts almost never split words, and
when paired with the VAD-aware decode they don't suppress boundary
content. Fixed-window cuts at e.g. 20.0 s have measurable WER cost on
boundary words.

### In-flight queue

A serial `Task` consumes the queue one chunk at a time. With
`maxInFlightChunks = 1`, the design assumes the model is faster than
realtime (RTF ≤ ~0.5×) for the chosen default model. With a baseline
M4/16GB at WhisperKit-medium ~0.22× RTF, a 20-second chunk takes
~4.4 s wall time — well under the next chunk's arrival, so the queue
typically stays empty between cuts.

The cap is conservative: bumping it to 2 gives some headroom against
RTF spikes (background load, thermal throttle) at the cost of double
peak RAM. Treated as a per-machine knob; default 1 stays safe.

### Stop semantics (the load-bearing case)

When `finish()` is called:

1. The current open buffer is the **tail** — everything after the last
   cut. Its length is at most `maxChunkSeconds`, in practice bounded
   by user behaviour (typically 5–15 s).
2. `await` any chunk currently transcribing.
3. Submit the tail as the final chunk and `await` it.
4. Concatenate all chunk transcripts in order, trimming any
   single-token overlaps where the segment seeker re-emitted boundary
   tokens (rare but observed; `TranscriptionUtilities` already exposes
   the dedup helper used by the offline chunker).
5. Compute final `EngineTranscription` (text, detectedLanguage from
   the first chunk, audioSeconds from total appended, wallSeconds from
   `begin()` to now, ttft as the timeToFirstToken of chunk 1).

Post-stop wait under the design = `tailTranscribeTime +
maybeOneInFlightChunkRemaining + assemblyTime`. With the tuning above,
**both terms are bounded by `maxChunkSeconds * RTF`**, independent of
total utterance length.

### Cancel mid-stream

`cancel()` must guarantee no leaks and no UI inconsistency:

1. Stop accepting new frames (`appendFrames` becomes a no-op until
   `begin`).
2. Cancel the in-flight chunk's `Task` — `WhisperKit.transcribe`
   honours Swift task cancellation cooperatively; if it doesn't drop
   on the next decoding step, treat the result as discarded on
   completion.
3. Release the buffer.
4. Caller (`AppDelegate.cancelRecording`) is responsible for showing
   the `cancelled` overlay state — no behaviour change vs. today.

The `AudioRecorder` buffer / WAV file are owned by `AudioRecorder` and
follow its existing cancel path (delete WAV on cancel, see SPEC-001).
`StreamingTranscriber` does not touch the WAV; the streaming pipeline
operates on the in-memory float copy fed via `framesHandler`.

### Error mid-stream

If a chunk transcribe throws:

1. **Continue, don't fail the session.** Log the chunk index, store an
   empty placeholder transcript for the failed chunk, keep accepting
   frames.
2. On `finish()`, if any chunk failed, still return the assembled
   transcript over the surviving chunks. Surface a flag in
   `EngineTranscription` (extend with `chunkFailures: Int`) so the
   caller can render an `error` overlay banner *after* paste — losing
   a 20-s window mid-utterance is bad, but losing the *whole* 2-minute
   transcript because of it is worse.
3. If **every** chunk fails (model crash, out-of-memory), fall through
   to the existing offline path: `WhisperKitEngine.transcribe(audioFile:)`
   on the WAV the recorder still has on disk. This is the "graceful
   degradation" branch — slower, but the user gets *something*. The
   overlay shows the normal `transcribing` state for the duration.

### Polish interaction (SPEC-007)

Polish runs **once, on the assembled transcript, after `finish()`
returns**. Never per-chunk. Three reasons:

1. Chunk boundaries cut sentences mid-clause; per-chunk polish would
   reorganise fragments and produce stitched-together garbage.
2. Polish prompts ask for filler removal, false-start cleanup,
   bullet-isation — all whole-utterance decisions. The LLM can only
   do them with full context.
3. Polish is the cheapest stage when the LLM is hot
   (cache `keep_alive: -1`, see SPEC-007); running it once on the
   final text is comparable in wall time to one chunk transcribe.

The pipeline becomes:

```
mic frames ─┬─► AudioRecorder.write(WAV)        (SPEC-001, unchanged)
            └─► StreamingTranscriber             (this spec)
                  ├── EnergyVAD silence cuts
                  ├── chunk[i] ─► WhisperKit.transcribe(audioArray:)
                  └── on finish() ─► assemble ─► raw transcript
                                                   │
                                                   ▼
                                              TextPolisher (SPEC-007, batch)
                                                   │
                                                   ▼
                                              PasteService (SPEC-005)
```

For utterances below `streamingThreshold`, `StreamingTranscriber` is
bypassed entirely — `AppDelegate` calls the existing
`WhisperKitEngine.transcribe(audioFile:)` on the finalised WAV, same
as today. The branch decision is at-stop based on
`AudioRecorder.elapsedSeconds`.

## Pipeline integration

In `AppDelegate.startRecording`:

```swift
let recorder = AudioRecorder()
recorder.framesHandler = { [streamer] samples, rate in
    Task { await streamer.appendFrames(samples, sampleRate: rate) }
}
try recorder.start()
await streamer.begin(language: settings.language, customWords: settings.customWords)
```

In `AppDelegate.stopAndTranscribe`:

```swift
let elapsed = recorder.elapsedSeconds
let url = recorder.stop()

let raw: EngineTranscription
if elapsed >= streamer.config.streamingThreshold {
    raw = try await streamer.finish()                    // streamed path
} else {
    await streamer.cancel()                              // discard accumulated frames
    raw = try await engine.transcribe(audioFile: url!,   // offline path
                                       language: settings.language,
                                       customWords: settings.customWords)
}

let polished = try await polisher.polish(raw.text, ...)
try await PasteService.paste(polished)
```

`AppDelegate` keeps a long-lived `StreamingTranscriber` between
sessions to avoid allocating the buffer on every hotkey press. The
cost is ~1.4 MB per minute of streaming-buffer headroom; bounded by
`cancel()` between sessions.

## Quality gates

Bench-able. Add to `openquack-bench`:

- **Post-stop wait, by utterance length.** New corpus
  `bench/corpus/long/` with utterances at 30 s, 60 s, 120 s, 300 s.
  Measure (`stop_hotkey → paste_ready`) wall time. Target on
  M4/16GB at WhisperKit-medium:
  - 30 s utterance: ≤ 1.5 s
  - 60 s utterance: ≤ 1.5 s
  - 120 s utterance: ≤ 2.0 s (tail variance + one queued chunk)
  - 300 s utterance: ≤ 2.5 s
  Without streaming, the same numbers grow ~6 s, ~13 s, ~26 s, ~65 s.
  The headline gate is **bounded by `maxChunkSeconds * RTF`**, not by
  utterance length. If the 300-s number ever exceeds the 60-s number
  by more than `2 * maxChunkSeconds * RTF`, streaming is broken.
- **WER delta vs. offline.** Streaming MUST NOT degrade transcription
  quality. WER on `bench/corpus/long/` for streaming vs. offline
  `transcribe(audioArray:)` should be within ±0.3 pp absolute.
  Anything beyond that points at chunk-boundary hallucinations and
  fails the gate.
- **Peak RSS during streaming.** Combined with WhisperKit-medium
  (~200 MB resident), streaming should stay ≤ 600 MB peak on a
  300-s utterance — that's the model + buffer + one in-flight
  chunk's worth of intermediate tensors.
- **Cancel cleanup.** Synthetic test: cancel after 45 s of a
  60-s utterance, verify (a) no orphan tasks, (b) buffer freed,
  (c) overlay returns to idle.

`BENCHMARKS.md` is the source of truth; the M3 default may shift the
chunk-size tuning if a smaller/faster default model lands.

## Open questions

- **Should we also wire WhisperKit's own `chunkingStrategy: .vad` for
  the offline fallback path?** Today `WhisperKitEngine.transcribe`
  passes `DecodingOptions()` with no chunking strategy, which forces
  the single-window path and silently truncates on audio > 30 s.
  Setting `.vad` is a one-line free win for the < `streamingThreshold`
  branch and the all-chunks-failed graceful-degradation branch. Lean
  yes; track separately if the change wants its own validation pass.
- **Frames-callback vs. WAV tail-read.** Wiring `framesHandler` is
  cleaner, but couples `StreamingTranscriber` to live audio capture.
  Tail-reading the WAV every N seconds is more decoupled (and lets
  the streaming infra also feed off recordings recovered from
  SPEC-014 history on next launch). Lean callback for v1; keep
  WAV-tail as a fallback option for the recovery flow.
- **Resampling location.** Today, resampling to 16 kHz happens inside
  WhisperKit's AudioProcessor when reading the WAV. With the frames
  callback, we have float samples at the device's native rate. Two
  options: (a) resample in `StreamingTranscriber` before queueing
  (uses Accelerate's `vDSP_desamp` or AVAudioConverter, well-trodden
  paths), (b) write each chunk to a temp WAV and call the existing
  `transcribe(audioPath:)` path. (a) is faster and avoids disk; (b)
  is closer to what we already trust. Lean (a), but stand up a small
  resample-correctness test against (b)'s output to catch drift.
- **`maxInFlightChunks > 1`.** Whether to ever exceed 1 is a per-host
  benchmark question. The peak-RSS gate above is the constraint —
  at 600 MB, `maxInFlightChunks = 2` may exceed it on the medium
  model.
- **Long-form decoder context.** WhisperKit carries some context
  across windows in offline `transcribe(audioArray:)` via
  `clipTimestamps` (see `WhisperKit.swift:923` resetting it for
  chunked options). For streaming, each chunk is transcribed
  independently — we lose cross-chunk context, which costs slightly
  on technical-term consistency at boundaries. SPEC-007's polish step
  recovers most of this; if benchmarks show a concrete WER hit, we
  can pass the previous chunk's last sentence as `promptTokens` to
  the next call.
- **Reuse with SPEC-014 (history).** SPEC-014 keeps recent recordings
  on disk for crash-recovery. Sealed chunks here are a natural
  persistence unit — write each chunk's PCM as it's cut and write the
  per-chunk transcript alongside. Crash mid-utterance then loses at
  most the open buffer (≤ `maxChunkSeconds` of audio). Out of scope
  for this spec; SPEC-014 may opt to consume the chunk stream rather
  than the WAV.
- **Streaming for the agent layer (SPEC-006).** With SPEC-012
  shipped, the assembled transcript becomes available roughly
  `maxChunkSeconds * RTF` after stop. Should `AgentRouter.submitTurn`
  start the agent session as soon as the *first* chunk transcribes,
  so by the time the user finishes speaking the agent has already
  parsed half the request? Compelling but big-scope; defer to a
  separate agent-streaming spec, do not block this one on it.

## References

- WhisperKit primary sources (read these first):
  - `Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift` —
    why we don't use it directly
  - `Sources/WhisperKit/Core/Audio/AudioChunker.swift` —
    `VADAudioChunker.splitOnMiddleOfLongestSilence` is the cut-point
    pattern we mirror at runtime
  - `Sources/WhisperKit/Core/Audio/EnergyVAD.swift`,
    `Sources/WhisperKit/Core/Audio/VoiceActivityDetector.swift` —
    `voiceActivity(in:)`, `findLongestSilence(in:)` are the only VAD
    primitives needed
  - `Sources/WhisperKit/Core/WhisperKit.swift:896` (`transcribe(audioArray:...)`),
    `:1543` (`Constants.defaultWindowSamples`)
  - `Sources/WhisperKit/Core/Models.swift:362` (`ChunkingStrategy`)
- OpenQuack code touched / extended:
  - `Sources/OpenQuackKit/Audio/AudioRecorder.swift` —
    additive `framesHandler` hook. **Note:** integration snippets in
    this spec use the *actual* `AudioRecorder` surface (`final class`,
    `start(outputURL:) throws -> URL`, `stop() -> URL?`, `elapsedSeconds`,
    `levelHandler` callback). SPEC-001's ratified Swift sketch is older
    than the impl and is not authoritative for those signatures —
    follow the source file.
  - `Sources/OpenQuackKit/Transcription/WhisperKitEngine.swift` —
    streaming reuses the same `pipe`; consider also enabling
    `chunkingStrategy: .vad` on its own offline path
  - new `Sources/OpenQuackKit/Streaming/StreamingTranscriber.swift`
- Adjacent specs:
  - SPEC-001 — voice capture (gets the `framesHandler` extension)
  - SPEC-002 — transcription (the engine streaming reuses)
  - SPEC-004 — overlay (no new states; same `transcribing` pill)
  - SPEC-007 — polish (runs once on assembled text)
  - SPEC-014 — local history (chunked persistence is a natural fit;
    sequencing not committed here)
- Roadmap: M3, effort L. Sibling item "Live partial transcripts" is
  explicitly out of scope here.
