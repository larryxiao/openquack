# Polish corpus

Test cases for the SPEC-007 LLM-polish bench (and SPEC-008 in-context
rewrite). One case per JSONL line in [`cases.jsonl`](cases.jsonl).

## Schema

```json
{
  "id": "en_trans_001",
  "category": "transcription_errors | rephrase_organize | in_context",
  "language": "en | zh | ja | es | fr | de",
  "raw": "raw transcript as Whisper would produce it",
  "app_context": null,
  "references": ["acceptable rewrite 1", "acceptable rewrite 2"],
  "must_contain": ["substring that MUST appear in the polished output"],
  "must_not_contain": ["substring that must NOT appear"],
  "notes": "freeform — where the case came from, what's being tested"
}
```

`app_context` is one of `null | chat | email | code | docs | terminal |
browser | other` — see SPEC-008.

## Categories

1. **`transcription_errors`** — homophone / proper-noun mishearings the
   polish step should fix. Drawn from real WhisperKit-medium output on
   `bench/out/M4-16GB/report.csv` plus user-reported cases.
2. **`rephrase_organize`** — fillers, false starts, multi-clause runs
   needing structure. Includes idempotency cases (already-clean input
   must come back ≈ unchanged).
3. **`in_context`** — same `raw`, multiple `app_context` slots, one
   case per (raw, context) pair. The judge scores whether the output
   fits the named context.

## Adding cases

- One JSON object per line. No multi-line entries — `cases.jsonl` is
  parsed line-by-line.
- IDs are stable. Use `<lang>_<bucket>_<NNN>` for solo cases and
  `ctx_<NNN>_<context>` for in-context groups.
- Validate with: `jq -c . cases.jsonl > /dev/null` (exits 0 on success).

## Current size

Seed: ~30 cases. Target before running the bench: ~80 (per SPEC-007
§Quality gates). Grow by adding cases the candidate models fail on
during the first run.
