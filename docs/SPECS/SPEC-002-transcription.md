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

## Quality gates (M2 default model selection)

- WER ≤ **3 %** on `bench/corpus/librispeech` for the chosen default model.
- RTF ≤ **0.3×** on the median supported Mac for the default model.
- Cold-start (warm cache) ≤ **5 s** on M-series 16 GB.
- Peak RSS ≤ **400 MB** for the engine + model alone.

A model that fails any of these is not the default. `BENCHMARKS.md` is the source of truth.

## Open questions

- The right model name for `large-v3-turbo` in `argmaxinc/whisperkit-coreml` — current config glob doesn't match. Use `WhisperKit.fetchAvailableModels()` to enumerate.
- Per-call decode options exposed to user (temperature, fallback retries, language detection). Currently fixed; the Settings → Advanced tab will surface them in a later spec.

## References

- `Sources/OpenQuackKit/Transcription/TranscriptionEngine.swift`
- `Sources/OpenQuackKit/Transcription/WhisperKitEngine.swift`
- `Sources/OpenQuackKit/Transcription/LightningEngine.swift`
- `docs/BENCHMARKS.md`
