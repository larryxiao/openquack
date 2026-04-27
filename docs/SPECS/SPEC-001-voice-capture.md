# SPEC-001 — Voice capture

**Status:** ratified — shipped 2026-04-26 (`Sources/OpenQuackKit/Audio/AudioRecorder.swift`)
**Owner:** `OpenQuackKit/Audio/`
**Last updated:** 2026-04-26

## Goal

Capture microphone audio during a recording session into a buffer suitable for transcription: 16 kHz mono `Float32`. Cleanly start, stop, and cancel.

## Non-goals

- System audio capture (ScreenCaptureKit) — separate spec, M4.
- VAD-based auto-stop — separate spec, M3.
- Streaming chunks to the transcriber while recording — separate spec, M3.

## Public surface

```swift
public actor AudioRecorder {
    public init(sampleRate: Double = 16_000)
    public func start() throws
    public func stop() async -> [Float]      // 16 kHz mono float32, peak-normalised? TBD
    public func cancel() async
    public var isRecording: Bool { get async }
    /// 0.0 ... 1.0 short-term audio level for the overlay's level meter.
    public var currentLevel: Float { get async }
}
```

## Behaviour

- Backed by `AVAudioEngine` with a single input tap on the input node's bus 0.
- Convert at the tap to mono `Float32` 16 kHz via `AVAudioConverter`.
- Append samples to an in-memory buffer. No disk IO during recording.
- On stop, return the accumulated `[Float]`. Empty array if recording was cancelled.
- On cancel, discard the buffer.

## Permissions

- Requests `NSMicrophoneUsageDescription` once on first `start()`.
- If denied, `start()` throws `AudioError.permissionDenied`. App should show a settings deep link (handled by the app shell, not this module).

## Quality gates

- ≤ 50 ms latency from `start()` returning to first sample captured (no perceptible "missed first word").
- No drift over 5-minute recordings; sample rate stable.
- Memory bounded: ~1.4 MB / minute (16k * 4 bytes * 60). Acceptable.

## Open questions

- Peak-normalise samples on stop, or leave raw? WhisperKit handles either; raw is more honest for the bench. Leaning raw.
- Should the level meter be a Combine publisher instead of an actor accessor for SwiftUI ergonomics? Likely yes; revisit when the overlay (SPEC-004) is implemented.

## References

- AVAudioEngine docs: https://developer.apple.com/documentation/avfaudio/avaudioengine
- voxt's recorder for prior art: their repo has the AVAudioEngine + format conversion pattern we want.
