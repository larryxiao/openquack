# SPEC-030 — ANE cache footprint: volunteer measurement campaign

**Status:** draft (call for contributors)
**Owner:** `OpenQuackKit/Transcription/` + community
**Last updated:** 2026-05-16
**Depends on:** [SPEC-029](SPEC-029-ane-cache-only-model.md)

## Goal

Collect storage and performance numbers across the Mac fleet we don't
own, so that [SPEC-029](SPEC-029-ane-cache-only-model.md) lands on
evidence rather than one machine's snapshot. Specifically, we need to
know — across M1/M2/M3/M4, 8 / 16 / 24+ GB, multiple macOS builds —
the answers to:

1. How big is the compiled ANE cache (`com.apple.e5rt.e5bundlecache`)
   *vs* the on-disk source weights, per Whisper variant?
2. After a macOS update, does the cache survive, get invalidated
   silently, or get rebuilt on first transcribe? What's the first-
   transcribe latency in each case?
3. Are there machines / OS builds where the cache path doesn't appear
   at all (e.g. CPU-only fallback, ANE refused)?

## Non-goals

- Designing the production "compact after warmup" feature itself —
  that's SPEC-029.
- Replacing the existing `openquack-bench` corpus run (`bench/CONTRIBUTING.md`).
  This campaign is *additional*: it's footprint + cold-warm timings, not
  WER/RTF.

## What we ask volunteers to do

Run **one script**, paste the output into a GitHub Discussion (or PR
the JSON file). That's the whole ask. The script:

1. Locates the installed OpenQuack app and its WhisperKit model cache.
2. Sums on-disk source weights per model variant.
3. Sums the e5rt cache contents and surfaces the OS-build segment.
4. Prompts the user to do **one cold transcribe** and **one warm
   transcribe** of a short sample clip (bundled), then reports the
   wall-clock for each.
5. Captures host info (chip family, RAM, macOS build) — same fields
   `OpenQuackBench` already collects, so reports collate easily.
6. Writes `bench/out/<host-tag>/cache-report.json` and prints a
   one-screen summary the user can paste.

Output schema (one JSON file per host):

```json
{
  "host": { "chip": "Apple M4", "ram_gb": 16, "macos_build": "24G84" },
  "openquack_version": "0.7.2",
  "models_on_disk": [
    { "variant": "openai_whisper-medium", "bytes": 1530000000 }
  ],
  "e5rt_cache": {
    "path_os_build": "24G84",
    "total_bytes": 107200000,
    "bundles": 3
  },
  "timings": {
    "cold_transcribe_ms": 14300,
    "warm_transcribe_ms": 820,
    "sample_clip": "samples/short_en_10s.wav"
  },
  "captured_at": "2026-05-16T19:42:00Z"
}
```

No audio is uploaded. No transcripts are uploaded. The sample clip is
shipped with the script — public-domain reading, ~10 s.

## What we want from the data

After ~30 reports across hardware tiers, we can answer:

- **Does the e5rt cache scale linearly with source weights?** If so,
  the per-machine disk savings of SPEC-029 are predictable; if not, the
  cache size depends on chip generation and ANE quantization choices,
  and we need to set expectations per-tier.
- **What's the post-update recompile cost?** Volunteers who run the
  script before *and* after a macOS update give us the cleanest signal.
  We'll mark those reports as a paired before/after pair.
- **Are there machines where ANE isn't used?** A zero-byte e5rt cache
  with a successful transcribe = CPU/GPU path. Those machines won't
  benefit from SPEC-029 at all; they should be excluded from any
  "compact source" default.

## Script contract

Path: `scripts/bench_ane_cache.sh` (this spec ships it alongside).

Requirements:

- Bash 3.2 — must run on stock macOS without Homebrew dependencies.
- Read-only by default. The only writes are under `bench/out/`.
- Calls `openquack-cli` if installed for the timed transcribes;
  otherwise prints copy-pasteable instructions for running them through
  the menu-bar app and pasting the timing back.
- Prints a final "what to share" block with the exact text to paste
  into the Discussion thread.

The full text of the report ends in a one-screen markdown table the
user can paste verbatim — no JSON wrangling required for the casual
contributor.

## Where reports land

- **Casual path** (preferred): paste the script's "summary block" into
  the [#cache-footprint Discussion thread](https://github.com/larryxiao/openquack/discussions)
  (to be created when SPEC-030 ships).
- **Power-user path**: PR `bench/out/<host-tag>/cache-report.json`.
  Mirrors the existing bench-result PR convention.

We do *not* ask volunteers to run a paired before/after macOS-update
test unless they happen to be updating anyway. Opportunistic data only —
nobody should update their OS for our benefit.

## Hardware coverage matrix

We want at least the cells marked **wanted** filled by the campaign.
Cells marked *have* are already covered by maintainer hardware or
existing bench reports — extra data still welcome but lower priority.

| Chip family | 8 GB | 16 GB | 24 GB | 32 GB | 36–48 GB | 64 GB+ |
|---|---|---|---|---|---|---|
| **M1** (base) | wanted | wanted | — | — | — | — |
| **M1 Pro** | — | wanted | wanted | wanted | — | — |
| **M1 Max** | — | — | wanted | wanted | wanted | wanted |
| **M1 Ultra** | — | — | — | — | wanted | wanted |
| **M2** (base) | wanted | wanted | wanted | — | — | — |
| **M2 Pro** | — | wanted | wanted | wanted | — | — |
| **M2 Max** | — | — | wanted | wanted | wanted | wanted |
| **M2 Ultra** | — | — | — | — | wanted | wanted |
| **M3** (base) | wanted | wanted | wanted | — | — | — |
| **M3 Pro** | — | wanted | wanted | wanted | — | — |
| **M3 Max** | — | — | wanted | wanted | wanted | wanted |
| **M4** (base) | wanted | *have* (M4 / 16 GB) | wanted | — | — | — |
| **M4 Pro** | — | wanted | wanted | wanted | wanted | — |
| **M4 Max** | — | — | wanted | wanted | wanted | wanted |
| **Intel** (any) | wanted | wanted | wanted | wanted | wanted | wanted |

Intel Macs are included specifically because they have **no ANE** —
those reports validate the "ANE refused / not used" branch of
[SPEC-029](SPEC-029-ane-cache-only-model.md) and prevent us shipping
a default that would regress them.

Form factor (MacBook Air / Pro / iMac / mini / Studio) does *not* go
in the matrix — the chip + RAM + OS build are the load-bearing fields.
But the script captures form factor anyway since `system_profiler`
reports it for free; useful for cross-referencing thermal-throttling
anomalies if any show up.

## Quality gates

This spec is "done" (i.e. SPEC-029 can move past Step 1 with confidence)
when:

- ≥ 5 reports per memory tier (8 / 16 / 24+ GB).
- ≥ 3 reports per chip generation (M1 / M2 / M3 / M4).
- ≥ 1 paired before/after macOS-update report.
- ≥ 1 report from a machine on a current-1 macOS major version (to
  catch invalidation patterns).
- ≥ 1 Intel-Mac report (confirms no-ANE behavior).

## Open questions

- Should `scripts/bench_ane_cache.sh` be promoted to a subcommand of
  `openquack-bench` (e.g. `openquack-bench cache-footprint`)? Pro:
  one entry point for contributors. Con: the script needs to run on
  machines that haven't built the bench binary.
- Do we want the script to also dump the e5rt cache *path tree* (no
  contents) for diagnostic purposes? Useful for SPEC-029's
  invalidation work; modestly more privacy-sensitive (it leaks the
  app bundle identifier and OS build, both of which we already
  collect).

## References

- [SPEC-029](SPEC-029-ane-cache-only-model.md) — the feature this
  campaign feeds.
- [SPEC-002](SPEC-002-transcription.md) — engine surface; defines the
  models in scope.
- `bench/CONTRIBUTING.md` — established convention for volunteer
  bench contributions; this spec follows the same shape.
- `scripts/bench_ane_cache.sh` — the runnable artifact (shipped with
  this spec).
