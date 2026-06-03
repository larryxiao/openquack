# SPEC-035 — Auto-normalise Chinese script to the system language

**Status:** ratified — implemented 2026-06-02 (shipping in v2.0.0-alpha.18)
**Owner:** `Sources/OpenQuackKit/Polish/ChineseScript.swift`,
`OpenQuackPlatform/LanguageDecodePolicy.swift`,
`OpenQuackStreaming/StreamingTranscriber.swift`, + `OpenQuackApp`
**Last updated:** 2026-06-02

## Goal

Whisper's `zh` model emits a mix of Traditional and Simplified hanzi —
often skewing Traditional even for a mainland speaker, and the script can
flip between streaming chunks of one utterance. Today the only fix is a
manual Settings picker (`ChineseScript` = auto / simplified / traditional)
that defaults to `auto` (no-op), so most users see inconsistent script and
never discover the control.

This spec makes script normalisation **automatic and configuration-free**:
when the transcription language is Chinese, the output is normalised to the
script implied by the user's macOS language preferences (Traditional for a
Traditional-Chinese system, Simplified otherwise — including non-Chinese
systems). No picker; it just happens.

## Behaviour

1. **Language is auto-detected** (the default). Post-SPEC-021 the auto path
   reliably labels Chinese as `zh`. A user who pins a language in Settings
   still works — the rule keys off the *resolved* language, pinned or
   detected.
2. **Convert the characters, don't touch the transcription.** The conversion
   is an ICU character-level `Hant↔Hans` transform, applied to whatever Whisper
   already emitted — we never alter the decode path to force a language. The
   transform is a no-op on every non-Han character (Latin, digits, punctuation),
   so it is safe to run on *any* output **except** Japanese (`ja`) and Korean
   (`ko`): their kanji/hanja share code points with hanzi and would be corrupted.
   The normaliser therefore skips only `ja`/`ko`; `zh`, `en`, `nil`, and mixed
   output all pass through the transform, with non-Chinese characters untouched.

   This is what handles **mixed language**: an utterance transcribed as `en`
   that carries embedded Chinese (e.g. "I use 軟體 daily") still gets its hanzi
   normalised to the system script, while the English is left exactly as-is.

   **Verified (2026-05-31, `medium`, offline auto-detect, M4-16GB).** An
   English-dominant ~8 s clip with an embedded Mandarin phrase transcribed as
   `language=en` with the Chinese emitted *as hanzi* inline (not translated):
   `…It goes like this. 你好世界,今天天气很好。 Isn't that…`. Feeding that exact
   string through the converter for a Traditional system flips `天气→天氣`
   while the English stays byte-for-byte identical; a Simplified system leaves
   it. The old `== "zh"` gate skipped this `en`-labelled output entirely. (The
   decoder does **not** always translate embedded Chinese away — so the
   mixed-language win is real on the offline path. The streaming path needs the
   companion change in *Streaming* below to decode the switch as Chinese in the
   first place.)
3. **Target script = system language, default Simplified.** Resolved from
   `Locale.preferredLanguages`, scanning for the first Chinese entry:
   - explicit `Hant` script subtag, or region ∈ {TW, HK, MO} → **Traditional**
   - explicit `Hans` subtag, region ∈ {CN, SG}, or bare `zh` → **Simplified**
   - no Chinese entry in the system preferences → **Simplified**

   The region table is the source of truth: `Locale.Language(identifier:)`
   does not reliably populate `.script` on region-only forms like `zh-HK`
   without likely-subtag maximisation, so we never depend on it.

## Non-goals

- **Word-level conversion.** ICU is character-level: Traditional `軟體`
  becomes `软体`, not the idiomatic mainland `软件`. Word-level (OpenCC) is a
  future upgrade; out of scope here (no C++ dep).
- **A script picker / per-locale override.** Removed for simplicity. If
  Traditional-on-a-Simplified-system demand shows up, revisit.
- **Cantonese vs Mandarin.** Whisper labels both `zh`; no separate handling.
- **Japanese/Korean Han under a mislabelled decode.** The skip-list keys off the
  *detected* language, so genuine kanji/hanja that surface under a non-`ja`/`ko`
  label (e.g. a Japanese name in an utterance detected `en`) would be converted.
  Accepted: that requires both a detection miss and embedded CJK, and the
  alternative (never convert outside `zh`) loses the mixed-language win.
- **In-clip switching on the offline (<30 s) path.** The offline decode runs
  one language detection for the whole clip, so a short utterance that switches
  language mid-sentence is decoded under a single language. Whichever side the
  detector picks is transcribed faithfully (and embedded characters of the other
  language often survive — see the Behaviour §2 example); forcing a second
  decode is out of scope. The *streaming* path (≥30 s) does re-detect per chunk —
  see *Streaming* below.

## Streaming: per-chunk language detection

The streaming path (≥30 s) used to detect the language on the first chunk and
**lock** it for the whole recording (SPEC-021). That kept a monolingual
utterance from flipping language mid-stream, but it also meant an utterance that
genuinely switched language — start in English, finish in Chinese — was forced
to the first language: the Chinese tail came back as an English *translation*,
with no hanzi to normalise.

Per-chunk re-detection is the fix, but the naive version (re-detect every chunk)
re-opens the failure the lock was added for: WhisperKit returns the `"en"`
fallback — not `nil` — when detection is weak, so a short, low-content chunk can
silently flip a monolingual recording's tail to the wrong language.

**Middle ground (keyed off chunk duration).** The cutter never emits an interior
chunk shorter than `targetChunkSeconds` (20 s), which is plenty for reliable
language ID — so **full chunks re-detect** (that's what lets the language switch
at a boundary), and only the trailing partial chunk, if it is below
`minDetectSeconds` (default 10 s), **inherits** the running language instead of
risking a misdetect. The first chunk has nothing to inherit, so a rare short
first chunk still detects. The whole decision is the pure, unit-tested
`LanguageDecodePolicy.decideStreamingChunk`; a pinned language skips detection
entirely as before.

**Bench (2026-06-02, `medium`, streaming auto, smoke, M4-16GB).** A/B via
`openquack-stream-bench --min-detect 10` (new) vs `9999` (reproduces the lock),
same clips, same process:

| Clip | Old (lock) | New (per-chunk) |
|---|---|---|
| `en_long` 49 s monolingual EN | WER 3.7% | WER 3.7%, **byte-identical output** |
| `zh_long` 37 s monolingual ZH | hanzi | hanzi, **byte-identical output** |
| `codeswitch` 53 s EN→ZH | Chinese tail **translated to English** (no hanzi) | Chinese tail decoded as **hanzi** (`…最近我还在尝试用它来朗读和整理我的读书笔记…`) |

No regression on either monolingual case; the code-switch tail goes from an
English mistranslation to correct Chinese, which the normaliser above then puts
in the system script. (Smoke mode has no real-time pacing, so its post-stop wait
is not a latency figure — SPEC-012 owns that.)

**Known limitation.** A switch confined to the final < `minDetectSeconds` (10 s)
of audio lands in the short trailing chunk, which inherits rather than detects,
so that brief tail is missed. Catching it would mean trusting detection on very
short chunks — the exact regression the lock guarded against — so the tradeoff is
deliberate. A switch that occupies a full chunk (the normal case for a real
language change) is caught.

## Interaction with the default language mode

For the feature to apply out of the box, the default transcription language
moves from pinned-`en` to **auto-detect** (`""`). This is really SPEC-021's
domain (the detection mechanism), folded in here for one coherent change.

The legacy Settings caption ("Auto-detect can be unreliable on short
utterances…") predates the SPEC-021 alpha.17 fix (caption 2026-04-27; fix
2026-05-31) and is stale. **Gate the default flip on a bench:** run
`openquack-bench --models tiny --corpus bench/corpus/short` with
`--language en` vs auto and compare EN WER. SPEC-021 validated the
non-English failure modes, not EN short-clip misdetection specifically, so
this is the gap worth measuring.

- EN WER unchanged → flip the default **and** update the stale caption.
- EN WER regresses → keep the pinned-`en` default; normalisation still
  applies whenever the user is on auto-detect or pins `zh`. Report the delta.

**Bench result (2026-05-31, `medium` on `bench/corpus/short`, M4-16GB):**
auto-detect is byte-for-byte identical to pinned-`en` — WER
`{0, 0, 0, 0, 0.067}` on both runs, and auto-detect labels every clip `en`.
No EN regression → default flipped to auto-detect (`""`) and the stale
caption replaced. (`medium` is the app's default model, so this is the
representative comparison; `tiny` was not cached.)

## Acceptance criteria

- **Pure resolver, unit-tested matrix.** `ChineseScript.resolve(preferredLanguages:)`
  maps the full matrix deterministically (machine-independent):
  `zh-Hant`, `zh-Hant-TW`, `zh-TW`, `zh-HK`, `zh-MO` → `.traditional`;
  `zh-Hans`, `zh-CN`, `zh-SG`, bare `zh`, `en-US`, `[]` → `.simplified`;
  `["en-US","zh-Hant-TW"]` → `.traditional` (first Chinese entry wins).
- **Gating, unit-tested.** `normalize(_:language:preferredLanguages:)`:
  `ja` / `ko` return the input byte-for-byte unchanged even when it contains
  Han characters (kanji/hanja protection); `zh`, `en`, `nil`, and mixed
  Latin+Chinese strings convert the Chinese characters to the resolved script
  while leaving non-Han characters untouched.
- **No config surface.** The `chineseScript` UserDefault and its Settings
  picker are removed; `swift build && swift test` green.
- **Streaming decision, unit-tested.** `LanguageDecodePolicy.decideStreamingChunk`:
  a full chunk (≥ `minDetectSeconds`) re-detects even when a language is already
  running; a short chunk inherits the running language; a short chunk with
  nothing to inherit detects; a pinned language always forces. The offline
  `decide(pinned:locked:)` path is unchanged (its tests stay green).
- **Streaming bench.** A/B `--min-detect 10` vs `9999` on a monolingual EN
  clip, a monolingual ZH clip, and an EN→ZH code-switch clip: no monolingual
  regression, code-switch tail decodes as hanzi (see *Streaming* above).
- **Manual:** on auto-detect, dictate a mixed Simplified/Traditional Chinese
  utterance; the pasted text is uniformly in the system-implied script.
- **Manual (mixed language):** dictate an English sentence with an embedded
  Chinese phrase; the English is unchanged and the Chinese is in the
  system-implied script (provided Whisper transcribed it as hanzi — see
  Non-goals).
- **(Default flip) Bench:** EN WER delta on `bench/corpus/short`, `en` vs
  auto, documented in the PR before the flip lands.

## References

- SPEC-021 — Mandarin auto-detect fix (the detection mechanism this builds on).
- `Sources/OpenQuackKit/Transcription/TranscriptionEngine.swift` —
  `EngineTranscription.detectedLanguage` (the resolved-language signal).
- ICU `StringTransform` `Hant-Hans` / `Hans-Hant`.
- AGENTS.md — atomic PR + bench-on-language-path rules apply.
