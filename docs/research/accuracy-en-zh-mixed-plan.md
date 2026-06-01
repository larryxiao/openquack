# Accuracy plan — EN / ZH / mixed, holding latency + model size

**Goal:** improve transcription accuracy for English, Chinese, and mixed
(code-switched) speech while keeping latency low and model size small.
**Date:** 2026-05-30
**Status:** L1 (auto-detect fix) **IMPLEMENTED + BENCHED** — see Results. L2–L4
remain. Every number below is MEASURED on this host; no projected numbers.

**SPEC-021 scope of this change.** This is the engine fix only (the "F-class"
work in SPEC-021 §PR-2). It does **not** close SPEC-021's other deliverables:
the categorical failure-mode metrics (`.placeholder`/`.silentTranslation`/
`.garbled`), the zh_003–008 corpus expansion, or the "≥75% `.ok` rate" acceptance
criterion — those are bench-infra work tracked as L4 below. The decision logic
lives in `OpenQuackPlatform/LanguageDecodePolicy.swift` (pure, unit-tested in
`LanguageDecodePolicyTests`) so both transcription paths share one tested rule.

---

## Correction to repo record (for whoever opens the PR)

**SPEC-021 §"Root cause (hypothesis)" is now factually wrong and should be
updated.** It hypothesised "Whisper's language token selection during auto-detect
on short clips is unreliable." The truth, confirmed from WhisperKit 0.18.0
source: auto-detect was **disabled** in our config (`detectLanguage` defaulted
`false`), so the decoder never attempted detection — it prefilled English and
translated. The fix is enabling detection, not working around an unreliable
detector. SPEC-021's F1/F2/F3 fix candidates are mostly moot (see "dropped F1"
note). Recommend updating SPEC-021's root-cause section and BENCHMARKS.md's
"multilingual usage *requires* a language hint" line (auto now works).

---

## Verified ground truth (read directly from source)

Pipeline: `audio → WhisperKit(medium) → raw → TextPolisher.polish → paste`.
Two decode paths: offline `WhisperKitEngine.transcribe` (<30 s) and streaming
`StreamingTranscriber` (≥30 s).

1. **Auto-detect is catastrophic and is a user-selectable option.**
   `SettingsView`: `@AppStorage("language") = "en"` default, with an auto-detect
   choice the UI itself warns against ("Auto-detect can be unreliable on short
   utterances"). The fix should make auto *work*, not just warn.

2. **Engine decode options are bare.** `WhisperKitEngine.transcribe` (L296-318):
   `task=.transcribe`, `language` pass-through, `withoutTimestamps=true`,
   `promptTokens` from customWords. **No** `supressTokens`, **no** `detectLanguage`
   handling, **no** threshold/temperature tuning. SPEC-021 fixes unimplemented.

3. **Chinese long-form corrupted at chunk seams.** `StreamingTranscriber`
   `stitchChunks` (L252-272) joins chunks with `" "` and dedupes by
   `split(isWhitespace)`. Chinese has no inter-character spaces → every seam
   injects a spurious ASCII space; boundary-word dedupe never fires for CJK.

4. **`ChineseScript` (Hant↔Hans, ICU) IS wired** — `OpenQuackApp.swift:823,1083`
   `ChineseScriptConverter.convert(result.text, to: chineseScript)`. (Earlier
   note that it was dead code was wrong; corrected here.) Default `.auto` = no-op.

5. **ROOT CAUSE CONFIRMED (WhisperKit 0.18.0 source).** The auto-detect failure
   is not "detection is unreliable" — **detection never runs.**
   - `TranscribeTask.swift:312`: detection fires only
     `if textDecoder.isModelMultilingual, options.language == nil, options.detectLanguage`.
   - `Configurations.swift:226`:
     `self.detectLanguage = detectLanguage ?? !usePrefillPrompt`, and
     `usePrefillPrompt` defaults to `true` ⇒ **`detectLanguage` defaults to
     `false`.**
   - Our engine builds `DecodingOptions()` with all defaults, so on the auto
     path (`language == nil`) the guard is false: no detection, the decoder
     prefills the default English token and silently translates. Exactly the
     measured result (every clip labelled `en`).
   - **Fix = one line:** `options.detectLanguage = (options.language == nil)`.
     The in-decoder detect at `TranscribeTask.swift:313` reuses the already-
     computed `encoderOutput` (no duplicate encode), so it is cheaper than a
     separate `pipe.detectLanguage(audioPath:)` pre-pass (which reloads audio +
     re-encodes). When a language is pinned, the guard stays false and the path
     is byte-for-byte unchanged → zero overhead.

6. **Bench gaps.** `BenchRunner` calls 2-arg `transcribe` (no customWords) →
   SPEC-032 `--custom-words` flag absent. No failure-mode metrics (SPEC-021
   PR-A not landed). Corpus: only `zh_001/zh_002` + ja/ko/es/fr/de×2; no
   zh_003-008, no EN/ZH code-switch corpus.

---

## MEASURED baseline — `bench/corpus/multilingual`, medium, auto-detect

Run 2026-05-30 on this host (M4, 16 GB reported tag), debug build, no `--language`
(auto-detect). Reproduces BENCHMARKS.md (253.2% / 156.0%) exactly.

| Clip | ref lang | detected | WER | CER | Preview (note: ENGLISH = silent translation) |
|---|---|---|---:|---:|---|
| de_001 | de | en | 100.0% | 74.3% | "Today the weather is really nice." |
| de_002 | de | en | 122.2% | 66.0% | "I would like a coffee and a piece of cake…" |
| es_001 | es | en | 100.0% | 78.7% | "Today is a beautiful day to walk…" |
| es_002 | es | en | 111.1% | 82.2% | "I would like to have a coffee with milk…" |
| fr_001 | fr | en | 122.2% | 73.8% | "The cat is on the carpet…" |
| fr_002 | fr | en | 0.0% | 0.0% | "Je voudrais un café…" (correct, by luck) |
| ja_001 | ja | en | 600.0% | 233.3% | "Today is a very good weather." |
| ja_002 | ja | en | 700.0% | 173.7% | "The cat always pees in the window." |
| ko_001 | ko | en | 133.3% | 173.3% | "(speaking in foreign language)" |
| ko_002 | ko | en | 150.0% | 223.1% | "The weather is really nice today." |
| zh_001 | zh | en | 350.0% | 380.0% | "Spring is here, the flowers are blooming." |
| zh_002 | zh | en | 550.0% | 313.3% | "The weather is so nice today, let's go…" |
| **Aggregate** | | | **253.2%** | **156.0%** | RTF 0.35×, RSS 225 MB, cold 24.4 s |

**Read:** every clip silently translated to English (detected `en`), plus one
`(speaking in foreign language)` annotation (ko_001) — exactly SPEC-021's modes
1+2. This is the target to beat with detect-then-decode.

---

## MEASURED results — L1 fix applied (`options.detectLanguage = (language == nil)`)

One line per path. Offline: `WhisperKitEngine.transcribe` sets
`options.detectLanguage = (language == nil)`. Streaming: `StreamingTranscriber`
detects on the first auto chunk and locks the result for the rest of the
session. Same host / model / corpus / debug build as the baseline above.

**Multilingual, auto-detect (the headline win):**

| Metric | Before | After | Δ |
|---|---:|---:|---|
| Aggregate WER | 253.2% | **16.7%** | −236 pp |
| Aggregate CER | 156.0% | **3.7%** | −152 pp |
| RTF | 0.35× | 0.40× | +0.05× (auto path only) |

Per-clip after: de/es/fr/ja_001/ko/zh_001 all **0.0% WER**, correct language
token detected (`de`,`es`,`fr`,`ja`,`ko`,`zh` — was `en` for all). Two clips
(ja_002, zh_002) now decode in-language with CER 31.6% / 13.3% — ordinary ASR
slips, not translation. (zh_002 emitted Traditional hanzi; the `.auto`
ChineseScript default leaves it — pinning Simplified in Settings converts it.)
**16.7% now equals the Lightning engine's multilingual score** → the fix closes
the entire gap BENCHMARKS.md blamed on "WhisperKit auto-detect being
unreliable." Detection was never unreliable; it was switched off.

**English regression guards (all MEASURED this session, after = branch):**

| Corpus / path | WER | CER | RTF | Note |
|---|---:|---:|---:|---|
| LibriSpeech (real speech), auto | 2.6% | 1.3% | 0.20× | = published BENCHMARKS.md baseline (2.6%/1.3%) → no regression |
| short TTS, auto (`language==nil`) | 1.3% | 0.7% | 0.34× | tts_005 6.7%, rest 0% — model noise, not the change |
| short TTS, pinned `--language en` | 1.3% | 0.7% | 0.31× | identical to the auto run above |

English is unchanged. **The pinned path is provably byte-for-byte identical:**
WhisperKit's `detectLanguage` already defaulted to `false`
(`detectLanguage ?? !usePrefillPrompt` = `nil ?? !true` = `false`); when a
language is pinned the policy sets the same `false`. So the default-config path
that most users run (`@AppStorage("language")` default `"en"`) cannot regress by
construction. LibriSpeech (the real-speech gold standard) confirms 2.6% → 2.6%.
Model size unchanged. The **auto** path pays one extra in-decoder detection pass
— it reuses the existing encoder output (no second encode), so the cost is ~tens
of ms (visible as short-TTS auto RTF 0.34× vs pinned 0.31×, within run-to-run
noise on 5 clips). Honest framing: the auto path is slightly slower than pinned,
the pinned path is unchanged, and accuracy is identical on English either way.

**Custom-words bias survives auto-detect (verified by source reading, not yet
benched).** With detection on, WhisperKit calls `prefillDecoderInputs` a second
time after picking the language (`TranscribeTask.swift:326`). That rebuild slices
`basePrompt = currentTokens[0...startOfTranscriptIndex]` and re-appends
`options.promptTokens` (`TextDecoder.swift:467-476`); because prompt tokens sit
*after* the start-of-transcript token, the first prefill's copy is discarded by
the slice and the custom words are re-applied exactly once — no doubling, no
loss. This can't be empirically confirmed until `openquack-bench` gains
`--custom-words` (SPEC-032 crit 4, L4 below), so it ships on source reading.

**Long-form Chinese, offline path, auto-detect (MEASURED).** Synthesised 30.8 s
Mandarin clip (`say -v Tingting`, 16 kHz mono), `openquack-bench`, medium, no
`--language`:

| Metric | Value | Note |
|---|---:|---|
| Detected language | `zh` | correct (was `en` before the fix) |
| CER | **12.9%** | the real metric for ZH |
| WER | 100% | meaningless — Chinese is one whitespace-token; ignore, use CER |
| RTF | 0.16× | well within budget |

Output: `人工智能正在改变我们的工作方式和生活方式今天的天气真好…`. Inspecting the
diff, the CER is dominated by **number normalisation**, not recognition errors:
ref `百分之十五` → `15%`, ref `三点` → `3点`. The actual speech is transcribed
correctly in Chinese. So long-form Chinese works on the offline path.

**Streaming path (≥30 s) — MEASURED.** This PR adds `openquack-stream-bench
--language auto` (maps to nil) so the streaming auto path is exercisable; the
same 30.8 s Mandarin clip, `--mode both --smoke`, 2 chunks. Whitespace-WER is
meaningless for CJK (reference is one token, so it reads 100% even when perfect),
so the dispositive signal is the **output text** (full strings in
`/tmp/oq-stream-auto-{before,after}/report.csv`):

Exact CSV output (verbatim, first clause):
| | streaming output |
|---|---|
| **Before** (pre-fix `StreamingTranscriber`) | `"The artificial intelligence is changing our working and living ways…"` — English translation (stm whitespace-WER 725%) |
| **After** (fix) | `人工智能正在改变我们的工作方式和生活方式。今天的天气真好,我们出去散步吧。…` — correct Chinese (58%) |

The second chunk correctly **reused** the `zh` locked from chunk 1 (it did not
re-detect to English or flip), confirming the detect-then-lock mechanism — though
chunk 2 came back Traditional (`蘋果公司發布…`) while chunk 1 was Simplified, an
existing ZH-script issue the `.auto` ChineseScript default leaves alone (orthogonal
to this fix; pinning Simplified in Settings normalises it). Post-stop wait ~4–6 s
on this 30.8 s clip in smoke mode (no real-time pacing, so not a latency figure).
The space at the chunk seam (`…材料。 蘋果公司…`) is the **separate L2 issue** —
`stitchChunks` space-joins CJK chunks; tracked below, not part of this fix.
Verification method: pre-fix `StreamingTranscriber` checked out from `main`,
rebuilt against the new bench harness, run with `--language auto`; then the fix
restored. Both runs used identical bench code, so the delta isolates the engine
change.

A CER column for stream-bench (to put a number on CJK streaming, not just text)
remains an L4 follow-up.

**Why this beats a `pipe.detectLanguage()` pre-pass:** the WhisperKit internal
detect at `TranscribeTask.swift:312` runs inside `decodeWithFallback` on the
encoder output it already computed (and carries the detected language out via
`TranscriptionResult.language`, `TranscribeTask.swift:391-396`); a separate
pre-pass would reload 30 s of audio and re-run the encoder. Same accuracy, half
the work.

**Dropped from SPEC-021 on purpose:** F1 (suppress the `[` token) — the
`[SPEAKING …]` placeholders are multi-token, and blanket `[`-suppression would
corrupt dictated code/brackets (`arr[i]`, `[TODO]`) for the dev audience. The
annotation failure mode (ko_001 previously emitted the parenthetical
`(speaking in foreign language)`) is **verified gone** in the after-run —
ko_001 now scores 0.0% WER with correct Hangul output — because detection picks
the language token before that fallback can fire. So a separate F3 text-strip is
not needed for these corpora. If real user logs later show residual placeholders,
add a *known-vocabulary* strip (preserving real brackets) then.

---

## Levers, ranked by (accuracy gain ÷ latency+size cost)

### L1 — Auto-detect robustness (biggest ZH/mixed win; auto-path-only cost)
First verify lever 5 above. Then, on the `language == nil` path only:
- Detect language properly (either `options.detectLanguage = true` if the
  decoder honours it, or an explicit `pipe.detectLanguage()` pre-pass), then
  force the detected token. Pinned languages stay free.
- Targeted strip of `[(SPEAKING|FOREIGN|INAUDIBLE|MUSIC|NOISE|APPLAUSE|…)]`
  annotations from output — a **known-vocabulary** strip so dictated code/
  brackets (`arr[i]`, `[TODO]`) survive. (NOT blanket `[`-token suppression —
  that would corrupt the dev audience's transcripts.)
- Apply to both paths. **Mixed EN/ZH:** detect+lock dominant language beats the
  decoder flip-flopping per 30 s window.

### L2 — Chinese chunk stitching (latency-free, long-form ZH)
`stitchChunks`: when both seam sides are CJK, join with NO space + char-level
dedupe; keep space-join for Latin.

### L3 — Deterministic CJK post-processing in `TextPolisher` (latency-free)
Full-width punctuation, strip spurious inter-CJK spaces, optional CJK↔Latin
pangu spacing for mixed.

### L4 — Bench infra (gate for measuring L1-L3 and the streaming auto path)
- `openquack-stream-bench`: add `--language auto` (→ nil) so the streaming auto
  path is benchable, and a **CER column** (today it reports only whitespace-WER,
  useless for CJK). Without these, the L1 streaming change can't be measured
  honestly — see the streaming caveat in Results.
- `openquack-bench`: failure-mode metrics (placeholder/silentTranslation/garbled
  per SPEC-021), `--custom-words` flag (SPEC-032 crit 4).
- Corpus: zh_003-008 (SPEC-021) + a small EN/ZH code-switch corpus for mixed.
  CER primary for ZH.

### Rejected (named, not silently dropped)
Larger model (size), beam search (latency), network ASR (offline/privacy).

---

## Execution order (each PR cites a SPEC; engine touches carry SPEC-032 table)
0. Baseline benched ✓ (above).
1. Verify lever-5 detect mechanism → implement L1 (biggest win).
2. L2 Chinese stitching. 3. L3 CJK post-processing. 4. L4 bench infra/corpus.
Re-bench after each; record REAL before/after WER/CER. No projected numbers.
