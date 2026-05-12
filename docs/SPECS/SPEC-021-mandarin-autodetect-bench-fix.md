# SPEC-021 — Mandarin auto-detect failure: benchmark coverage + fix

**Status:** draft  
**Milestone:** M1 (bench) / M2 (fix)  
**Reported:** issue #17 — "Mandarin being translated as [SPEAKING CHINESE]"

---

## Problem statement

When a user speaks Mandarin without setting a language preference, WhisperKit can
produce one of three failure modes instead of a correct transcript:

1. **Placeholder hallucination** — output contains bracket-notation like
   `[SPEAKING CHINESE]` or `[FOREIGN LANGUAGE]`. The model recognised there was
   non-English speech but generated a training-data annotation rather than the
   transcript. This is the exact failure in issue #17.
2. **Silent translation** — Whisper's decoder decides to output English even with
   `task = .transcribe` (not `.translate`), typically when its language-detect
   confidence is low and the decoder falls back to an English beam. The user gets
   a rough English rendering of what they said, not their words in Chinese.
3. **Garbled hallucination** — extended repetition of partial Chinese characters
   or Latin symbols, producing WER far above 100%.

The existing benchmark already demonstrates that auto-detect on short multilingual
clips is catastrophic (>200% WER, per `docs/BENCHMARKS.md`). But WER alone cannot
distinguish the three failure modes above — mode 1 may score similarly to mode 3
even though the user experience is completely different. We need categorical metrics
and a fix.

---

## Root cause (hypothesis)

- `task = .transcribe` is already set; this is not a translate-task bug.
- Whisper's language token selection during auto-detect on short clips is
  unreliable. The model defaults toward high-frequency languages (English) when
  confidence is low.
- `[SPEAKING CHINESE]`-style outputs are training-data annotations that were not
  filtered from Whisper's pretraining corpus. The model learned to emit them when
  it detects non-English audio without a language token.
- `DecodingOptions.supressTokens` is currently `[]` in our engine. WhisperKit
  exposes this field; injecting the token IDs for `[SPEAKING`, `[FOREIGN`, etc.
  would suppress that failure mode. This is a primary candidate fix.

Verification before any fix lands: look up token IDs for the bracket strings and
confirm they are in the Whisper vocabulary. If they are not word-piece tokens (i.e.
they decompose into many IDs), suppression via this field is impractical and the
fix moves to the output-text post-processing layer instead.

---

## Scope — PR 1: benchmark (M1 close-out)

### 1.1 New categorical metrics

Add to `ClipMetrics` and `Report`:

| Metric | Type | Definition |
|---|---|---|
| `failureMode` | enum | `.ok`, `.placeholder`, `.silentTranslation`, `.garbled` |
| `outputScriptMatch` | Bool | true if dominant Unicode block of output matches reference |
| `hallucRateRaw` | Double | fraction of output chars matching `\[.*?\]` patterns |

**Failure mode classification rules** (applied per clip, in order):

1. Output matches `\[(SPEAKING|FOREIGN|INAUDIBLE|MUSIC|NOISE|APPLAUSE)[^\]]*\]` →
   `.placeholder`
2. Reference is CJK (>30% codepoints in CJK Unified / Hangul / Hiragana+Katakana
   blocks) but output is >70% Latin → `.silentTranslation`
3. WER > 2.0 (200%) → `.garbled`
4. Otherwise → `.ok`

### 1.2 Corpus expansion — Chinese clips

Extend `bench/corpus/fetch.sh` to generate 6 additional Mandarin clips using
macOS `say -v Tingting`:

| ID | Content | Why |
|---|---|---|
| `zh_003` | 我需要在明天下午三点开会。 | short, time/number context |
| `zh_004` | 请帮我发一封邮件给张总。 | instruction sentence |
| `zh_005` | 这个季度的销售额增长了百分之十五。 | longer, numeral density |
| `zh_006` | 苹果公司发布了新款 iPhone。 | proper noun (Apple, iPhone) |
| `zh_007` | 今天北京天气晴，最高气温三十度。 | city name + numeral |
| `zh_008` | 人工智能正在改变我们的工作方式。 | abstract / AI topic |

8 clips total (zh_001–zh_008) gives a statistically meaningful sample for a
single-language bucket.

### 1.3 Bench report additions

- Add a `Failure mode breakdown` column to the per-bucket aggregate table.
- Print failure mode per clip in `--verbose` mode.
- CSV gets `failure_mode,output_script_match,halluc_rate_raw` columns.

### 1.4 Baseline run and BENCHMARKS.md update

After landing the metrics + expanded corpus, rerun the bench with and without
`--language zh` on the new zh bucket and record the delta. This gives us:

- **No-hint baseline**: quantifies the three failure modes as rates.
- **Hinted baseline**: confirms what a correct transcript looks like.

---

## Scope — PR 2: fix exploration (M1/M2 boundary)

Fixes are explored in a worktree. Land only the one(s) that show measurable
improvement on the new categorical metrics without regressing English WER.

### Fix candidates (priority order, try model-layer first)

**F1 — Token ID suppression of bracket hallucinations (one-line in `WhisperKitEngine`)**

Resolve token IDs for `[SPEAKING`, `[FOREIGN`, `[INAUDIBLE`, `[MUSIC]` via
`pipe.tokenizer?.convertTokenToId(...)` at engine-init time. Add resolved IDs to
`options.supressTokens`. Verify token IDs exist; if not, fall through to F3.

Expected impact: eliminates failure mode 1 (placeholder) cleanly. No effect on
modes 2 or 3.

**F2 — Script-match retry with language hint**

After a transcription returns a `.silentTranslation` or `.garbled` result, retry
the same audio with `options.language = <auto-detected lang>`. Detect the audio
language via a first-pass no-decode language-only run. WhisperKit supports this
through `detectLanguage(audioArray:)`.

Expected impact: fixes mode 2 and 3 for short clips where the language-detection
first pass is more reliable than the full decode. Adds latency on failure paths
only (~50 ms). Does not help mode 1 if bracket tokens already consumed the decode
budget.

**F3 — Output-text post-processing: strip bracket hallucinations**

Regex-strip `\[(SPEAKING|FOREIGN|INAUDIBLE|MUSIC|NOISE|APPLAUSE)[^\]]*\]` from the
final text. Lives in `WhisperKitEngine.transcribe(...)`, after join/trim.

This is a safety net, not a primary fix — it doesn't address modes 2 or 3, and it
masks rather than fixes. Land only if F1 is impractical (tokens not in vocabulary).

**F4 — Prompt the user for language before first non-English clip**

This is already tracked as a roadmap item ("user language preference in Settings →
General"). It is the complete fix for all three modes. SPEC-021 should not attempt
to implement the full Settings UI — that belongs in M2/M2.5. If F1+F2 close the
issue adequately, F4 remains a UX improvement for later.

### Success criteria for fix PR

- `failureMode == .ok` rate on `bench/corpus/multilingual/` rises from current
  baseline to ≥75% across zh clips, without a language hint.
- English WER on `bench/corpus/short` and `voices` does not regress by more than
  0.5 pp.
- Bench delta table included in PR.

---

## Out of scope

- Japanese, Korean, Arabic, and other scripts: same failure modes exist; tracked as
  a follow-up once the zh fix is validated.
- Full multilingual Settings UI: tracked separately under M2/M2.5.
- Large corpus (>10 clips per language): cost vs. signal for a dev corpus; defer.
- Changing `task` from `.transcribe` to anything else.

---

## PR shape

| PR | Title | SPEC cite | CI gate |
|---|---|---|---|
| PR-A | `bench: categorical failure-mode metrics + zh corpus expansion` | SPEC-021 | swift build + swift test |
| PR-B | `fix(whisperkit): suppress bracket hallucinations + script-match retry` | SPEC-021 | swift build + swift test + bench delta |

PR-A must merge before PR-B (B depends on the new metrics to report its delta).
