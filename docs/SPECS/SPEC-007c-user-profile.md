# SPEC-007c — Personalised user profile

**Status:** draft (deferred — follow-up to SPEC-007, not scheduled for the current wave)
**Owner:** `OpenQuackKit/Polish/` + `OpenQuackKit/Transcription/` + a new profile component
**Last updated:** 2026-06-02
**Based on:** [SPEC-007](SPEC-007-llm-polish.md) (LLM polish engine), builds on [SPEC-007b](SPEC-007b-rewrite-ux.md) (polish UX)

## Goal

Build a compact, on-device **user profile** offline from the user's
transcript history, then reuse that one profile in **two** places to
improve dictation accuracy without hurting the "speak → paste"
latency budget:

1. **Whisper `customWords`** — bias decoding *before* information is lost.
2. **Polish LLM context** — recover residual errors and fit the user's
   register *after* transcription.

The profile is a personalisation layer, not a new model. It is produced
by the same lightweight text-only LLM SPEC-007 already ships
(`OllamaPolishEngine`'s model), run offline.

## Motivation

A recurring failure today: a user says "main 分支" (English term inside
Mandarin), Whisper — forced to a single language — collapses the English
word into a Mandarin homophone ("面粉支"), and the regex/LLM polish step
cannot recover it because the text it receives is already corrupted.

This is fundamentally an **ASR-layer** problem: the phonetic information
that distinguishes "main" from "面" lives in the audio, not in the text.
By the time the polish LLM sees "面粉支", the signal is mostly gone. Two
consequences shape this spec:

- The highest-leverage fix acts **at the decoder** (`customWords` →
  `promptTokens`), before the collapse — not at the polish step.
- A personalisation signal (domain, vocabulary, register) raises the
  odds of recovery at *both* layers, so it is worth deriving once and
  feeding to both.

## Architecture — one profile, two sinks

```
HistoryStore ──(offline, incremental)──► ProfileBuilder (4.6B text-only LLM)
                                              │
                                              ▼
                                         UserProfile  (on-device, user-editable)
                                          /          \
                  vocabulary subset      /            \   compact prior
                  (ranked, token-capped)/              \  (a few hundred tokens)
                                       ▼                ▼
                          Whisper customWords      Polish LLM context
                          (→ promptTokens,         (soft prior in the
                           ~224-token budget)       polish prompt)
                                       │                │
                          decode-time bias        generation-time recovery
                          (root fix)              + zh homophone disambiguation
                                                  + register fit (mitigation)
```

| Sink | Layer | Solves |
|---|---|---|
| Whisper `customWords` → `promptTokens` | pre-decode (root) | stops "main" from collapsing into "面" in the first place |
| Polish LLM context | generation (mitigation) | recovers reversible errors, disambiguates same-language homophones, fits the user's register |

Feeding both shares one derived artefact at near-zero marginal cost. The
decoder sink is the stronger of the two for the cross-lingual class of
errors; the polish sink covers what the decoder still gets wrong.

## Components

### 1. `ProfileBuilder` (offline)

- Runs the SPEC-007 text-only model **off the hot path** (not during a
  dictation). Trigger: every *N* new transcripts or on a timer.
- Reads [`HistoryStore`](../../Sources/OpenQuackKit/History/HistoryStore.swift)
  **incrementally** — it never re-scans the whole corpus. State tracks
  what has already been folded into the profile.
- Output: an updated `UserProfile`.

### 2. `UserProfile` (persisted)

- Compact, structured, on-device document:
  - **Domain** — short free-text characterisation (e.g. "software
    engineer; works in Swift and Git").
  - **Vocabulary** — ranked terms / proper nouns the user actually says
    (English words inside Mandarin, jargon, names), each with a frequency
    or recency weight for token-budget selection.
  - **Register** — tone / formality hints for the polish prompt.
- **User-visible and editable.** The user can inspect, prune, or correct
  it — this doubles as a transparency surface and a guardrail against the
  builder learning the wrong thing.

### 3. Injection adapters

- **Whisper adapter** — selects a ranked subset of `Vocabulary` that fits
  Whisper's prompt budget (~224 tokens), formatted the same way the
  existing path joins `customWords`
  ([`WhisperKitEngine.swift:259-268`](../../Sources/OpenQuackKit/Transcription/WhisperKitEngine.swift)).
- **Polish adapter** — compresses the profile into a few-hundred-token
  soft prior and injects it into the polish prompt
  ([`PolishPrompt`](../../Sources/OpenQuackKit/Polish/Engine/PolishPrompt.swift)),
  without displacing the existing formatting instructions.

## Hard constraints (guardrails)

1. **Faithfulness.** The profile is a *soft prior*. Polish must stay
   "clean up, do not rewrite" (SPEC-007's content-preservation principle).
   The polish prompt must forbid injecting terms or content the user did
   not say, even when the profile suggests them. Personalisation may not
   become hallucination.
2. **Latency.** Polish runs on the hot path. The profile context added to
   each polish call has a strict token ceiling and must be cacheable; the
   extra prefill must not regress the perceived "speak → paste" speed.
   Profile *building* is offline and exempt.
3. **Cold start.** No history ⇒ no profile ⇒ graceful degradation to
   current behaviour (empty `customWords`, no polish prior). The feature
   must never make a fresh install worse.
4. **Privacy.** The profile is sensitive data derived from everything the
   user has dictated. It stays strictly on-device — consistent with
   SPEC-007's "explicitly local" framing.

## Non-goals

- **No model fine-tuning or distillation.** On-device training of a 4.6B
  model is not viable, and the shipped GGUF is inference-only. The
  text-only model's text reasoning is the full language backbone; the
  lever here is *context*, not retraining.
- **No clipboard / keystroke monitoring.** OpenQuack cannot observe edits
  the user makes after paste in the focused app, and global input
  monitoring is rejected on privacy/permission grounds. The profile is
  derived only from transcript history the app already holds.
- **No cross-device sync.** The profile is local to one machine.

## Open questions

- **Profile-update cadence** — fixed *N* transcripts, a timer, or both?
- **Vocabulary ranking** — frequency, recency, or a decay that handles
  topic drift without losing durable terms.
- **`customWords` interaction** — how the derived vocabulary composes
  with the user's manually-entered `customWords`
  ([`OpenQuackApp.swift:44`](../../Sources/OpenQuackApp/OpenQuackApp.swift)):
  merge, or keep manual entries authoritative?
- **Code-switch language setting** — whether this work pairs with
  relaxing the forced `language` to auto-detect for code-switching users
  (`OpenQuackApp.swift:40-42`); likely a separate, smaller change.
- **Polish-prior format** — structured fields vs. a short natural-language
  summary; which the 4.6B model follows most faithfully under the
  latency budget.

## Relationship to SPEC-007

- **SPEC-007** ships the polish engine and pipeline this layer plugs into.
- **SPEC-007a** settles the default model; `ProfileBuilder` reuses it.
- **SPEC-007b** owns the polish UX; the profile's user-visible/editable
  surface extends that UX surface.
- **SPEC-007c** (this) adds the personalisation layer feeding both the
  Whisper decoder and the polish step. Deferred to a later wave.
