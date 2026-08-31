# SPEC-002 — Transcription

**Status:** ratified (M1 complete; iterations expected)
**Owner:** `OpenQuackKit/Transcription/`
**Last updated:** 2026-04-26

## Goal

Transcribe a discrete audio buffer (file or PCM samples) into text behind a stable abstraction so engines can be swapped, compared, and benchmarked.

## Non-goals

- Streaming partial transcripts — separate spec, M3.
- Speaker diarisation — separate spec, M4.
- Audio capture — see SPEC-001.

## Public surface

```swift
public protocol TranscriptionEngine: AnyObject {
    static var engineName: String { get }
    static var suggestedModels: [String] { get }
    var modelID: String { get }
    func transcribe(audioFile url: URL, language: String?) async throws -> EngineTranscription
}

public struct EngineTranscription: Sendable {
    var text: String
    var detectedLanguage: String?
    var audioSeconds: TimeInterval
    var wallSeconds: TimeInterval
    var timeToFirstToken: TimeInterval?
}

public enum EngineKind: String, CaseIterable, Sendable { case whisperkit, lightning }
```

## Engines

| Engine | Status | Use case |
|---|---|---|
| WhisperKit (`argmaxinc/argmax-oss-swift`) | shipped | Primary runtime engine for the app |
| Lightning (`lightning-whisper-mlx` via subprocess) | shipped, bench-only | Comparison baseline; not for app runtime |
| WhisperCpp | future | Non-MLX reference for cross-platform later |
| MLXAudioEngine (`mlx-audio-swift`) | future | Voxtral / Qwen3-ASR / Parakeet variants |

## Model cache

Weights live in `~/Library/Application Support/OpenQuack/WhisperKit/models/argmaxinc/whisperkit-coreml/openai_whisper-<variant>/`, shared by the app, the CLI and the bench. Each variant is three `.mlmodelc` bundles, and a bundle's payload is its `weights/weight.bin` — everything else in it is small metadata.

"Is this variant downloaded?" (`WhisperKitEngine.hasModelWeights`) must therefore test those three weight **files**, never the bundle directories: HubApi creates the directories and the small files the moment a transfer starts and moves the weight file in only on completion, so a directory test reports every torn download — a cancel, a quit, a dropped connection — as finished. Downstream that means the app skips its own visible download, `WhisperKit`'s init silently re-fetches gigabytes with no progress surface, and Settings offers the half-model for deletion.

## Quality gates (M2 default model selection)

- WER ≤ **3 %** on `bench/corpus/librispeech` for the chosen default model.
- RTF ≤ **0.3×** on the median supported Mac for the default model.
- Cold-start (warm cache) ≤ **5 s** on M-series 16 GB.
- Peak RSS ≤ **400 MB** for the engine + model alone.

A model that fails any of these is not the default. `BENCHMARKS.md` is the source of truth.

## Acceptance criteria

- [ ] WER / RTF / cold-start / RSS meet the quality gates above for the default model; `BENCHMARKS.md` carries the numbers.
- [ ] A variant whose three `weights/weight.bin` files are all present reads as downloaded; one missing any of them — including the torn case where every bundle directory and its small files exist — reads as not downloaded (unit tests: `WhisperKitEngineCacheTests.testHasModelWeights_*`).
- [ ] Manual: interrupt a model download (quit mid-transfer), relaunch, and confirm Settings does not list the variant under "Downloaded models" and re-offers it for download with visible progress rather than fetching it silently.

## Open questions

- The right model name for `large-v3-turbo` in `argmaxinc/whisperkit-coreml` — current config glob doesn't match. Use `WhisperKit.fetchAvailableModels()` to enumerate.
- Per-call decode options exposed to user (temperature, fallback retries, language detection). Currently fixed; the Settings → Advanced tab will surface them in a later spec.
- Can we drop the ~1.5 GB on-disk source weights once CoreML has compiled them, keeping only the ~100 MB e5rt ANE cache? Tracked in [SPEC-029](SPEC-029-ane-cache-only-model.md); volunteer measurement campaign in [SPEC-030](SPEC-030-ane-cache-volunteer-bench.md).

## References

- `Sources/OpenQuackKit/Transcription/TranscriptionEngine.swift`
- `Sources/OpenQuackKit/Transcription/WhisperKitEngine.swift`
- `Sources/OpenQuackKit/Transcription/LightningEngine.swift`
- `docs/BENCHMARKS.md`
