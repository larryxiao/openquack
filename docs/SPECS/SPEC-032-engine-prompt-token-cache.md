# SPEC-032 — Engine prompt-token cache (offline path parity)

**Status:** draft
**Owner:** `OpenQuackKit/Transcription/WhisperKitEngine.swift`
**Milestone:** M1 (perf fix)
**Effort:** S
**Last updated:** 2026-05-28

---

## Problem statement

OpenQuack has two transcription paths:

| Path | When used | How `customWords` is encoded |
|---|---|---|
| `StreamingTranscriber` | audio ≥ 30 s | `encodePrompt()` called once at `begin()`; result stored in `self.promptTokens` and reused for every VAD-chunk decode |
| `WhisperKitEngine.transcribe()` | audio < 30 s | `tokenizer.encode()` called on **every invocation** |

The offline path re-does the tokenizer call on every short dictation. The tokenizer call itself is cheap (~1–5 ms), but the inconsistency is a latent correctness trap and adds needless work at the boundary that matters most for latency — short clips where post-stop wall time is most visible to the user.

---

## Goal

Cache the encoded prompt tokens inside `WhisperKitEngine`. Re-encode only when the `customWords` string changes. The offline path then behaves identically to `StreamingTranscriber` with respect to prompt-token handling.

---

## Non-goals

- Changing Whisper decoder behaviour or the effect of `promptTokens` on accuracy.
- Modifying `StreamingTranscriber` (it already caches correctly).
- Changing when or whether custom words are applied — the feature semantics are unchanged.
- Any UI changes.

---

## Design

Add two fields to `WhisperKitEngine`:

```swift
private var cachedCustomWordsKey: String = ""
private var cachedPromptTokens: [Int]? = nil
```

In `transcribe(audioFile:language:customWords:)`, replace the inline encode block with a cache-check:

```swift
let wordsKey = customWords?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
if wordsKey != cachedCustomWordsKey {
    cachedCustomWordsKey = wordsKey
    if !wordsKey.isEmpty, let tok = pipe.tokenizer {
        let joined = wordsKey
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        cachedPromptTokens = joined.isEmpty ? nil : tok.encode(text: " " + joined)
    } else {
        cachedPromptTokens = nil
    }
}
options.promptTokens = cachedPromptTokens
```

`WhisperKitEngine` is created once per app lifetime and accessed only from async transcription tasks (serialised through the actor model in `OpenQuackApp`). The cache is therefore safe without additional locking.

---

## Acceptance criteria

1. **Cache hits.** A new unit test `WhisperKitEngineCacheTests` (or extension of
   the existing `WhisperKitEngineCacheTests` file) confirms that, for N
   consecutive `transcribe()` calls with identical `customWords`, the
   tokenizer's `encode()` is invoked exactly **once**.  The test must also
   confirm a cache miss (re-encode) occurs when `customWords` changes between
   calls.

2. **Empty / nil passthrough.** When `customWords` is `nil` or `""`, `promptTokens`
   remains `nil` on every call — same behaviour as before.

3. **Bench unchanged.** Running `swift run OpenQuackStreamBench` against the
   existing noisy + clean corpora produces RTF and WER values within noise of
   the pre-patch baseline (no accuracy regression from the cache change).

4. **All existing tests green.** `swift test` passes with 0 failures.
