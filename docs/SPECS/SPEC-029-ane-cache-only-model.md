# SPEC-029 — ANE-cache-only model footprint

**Status:** draft (investigation)
**Owner:** `OpenQuackKit/Transcription/`
**Last updated:** 2026-05-16

## Goal

Investigate whether OpenQuack can drop the ~1.5 GB on-disk Whisper-medium
source weights once CoreML has compiled them for the Neural Engine, and
re-fetch only when the compiled cache is invalidated (e.g. after a macOS
update). Target disk footprint goes from **~1.5 GB → ~100 MB** in the
steady state.

## Non-goals

- Changing model selection, quality bar, or runtime engine (see
  [SPEC-002](SPEC-002-transcription.md)).
- Shipping a redistributable pre-compiled artifact. Apple does not
  guarantee the e5rt bundle format across OS/firmware revisions; we are
  *not* trying to ship one.
- Streaming model download at first-use (already covered by the
  onboarding flow via `WhisperKitEngine.ensureDownloaded`).

## What we observe today

A live `openquack` process running `openai_whisper-medium` on M-series:

| Location | Path | Size |
|---|---|---|
| Source weights (FP16 mlmodelc) | `~/Library/Application Support/OpenQuack/WhisperKit/models/argmaxinc/whisperkit-coreml/openai_whisper-medium/` | **1.46 GB** (586 MB AudioEncoder + 872 MB TextDecoder + ~370 KB MelSpectrogram) |
| Tokenizer / config | `~/Library/Application Support/OpenQuack/WhisperKit/models/openai/whisper-medium/` | ~2.7 MB |
| Compiled ANE cache (e5rt) | `~/Library/Caches/org.openquack.OpenQuack/com.apple.e5rt.e5bundlecache/<OS-build>/<hash>/.../bnns_program.bnnsir` | **~100 MB** total cache dir |
| Process RSS at idle | — | ~8 MB (the app is a thin client; weights live in the ANE) |

The compiled cache directory contains a path segment that is the **OS
build number** (e.g. `24G84`) and a per-model **content hash**. CoreML
keys cache lookups by hashing the source `.mlmodelc`. This is the load
flow we can observe in the runtime:

```
WhisperKit → MLModel(contentsOf: <source-url>)
           → CoreML hashes the source bundle
           → e5rt cache lookup at <OS-build>/<hash>/...
                 hit  → execute compiled bytecode on ANE
                 miss → recompile from source, write cache, then execute
```

## Hypothesis

After the first successful load, we can:

1. Pin / copy the source `.mlmodelc` hash (or the cache-key path) so we
   can detect later whether the cache is still warm.
2. Delete the FP16 source weights.
3. On every subsequent launch, *check* that the compiled cache for the
   current OS build still resolves. If yes, load without source. If no
   (OS updated, cache evicted, hash changed), redownload the source,
   recompile, then drop it again.

## Why this is probably **not** a clean win

These are the load-bearing risks identified before we started. The
investigation has to resolve each one or the spec gets parked.

1. **CoreML loader still needs the source URL.**
   `MLModel(contentsOf:)` in WhisperKit's pipeline is given a path to
   the `.mlmodelc` bundle. Even on a cache hit, CoreML opens that
   directory to read `coremldata.bin` / `metadata.json` / the
   `model.mil` graph. The compiled bytecode at `bnns_program.bnnsir` is
   the ANE-specific *compiled program*, not a standalone model. Loading
   a model whose source directory is missing is expected to fail
   regardless of cache state.
   - **To verify:** delete the source, launch, see what fails and at
     which call. Possible — though unconfirmed — that only `weights/weight.bin`
     is unreachable after compile, and the metadata files alone (~few MB)
     are enough. That would change the trade-off.

2. **Not all of Whisper runs on the ANE.**
   `MelSpectrogram.mlmodelc` (audio frontend) runs on CPU/GPU — the
   `.bnnsir` cache only covers ANE-bound graphs (likely encoder, possibly
   decoder). The MelSpectrogram component is tiny (~370 KB) so we keep it
   regardless, but this confirms the cache is not a complete substitute.

3. **Cache invalidation is frequent and silent.**
   The OS-build segment in the cache path means **every** macOS update
   blows away the cache. On invalidation we need source files present to
   recompile. If source is absent, the user sees a ~1.4 GB redownload at
   first transcription post-update — worse UX than the constant-state
   1.4 GB on disk.
   - **To verify:** how often do we expect cache invalidation in
     practice? Track this once SPEC-013 (usage stats) lands.

4. **e5rt cache is not under our control.**
   The directory is under our app's Caches sandbox, but the format,
   layout, and invalidation policy are CoreML internals. Any approach
   that *parses* the cache or *moves files into* it is fragile across
   macOS versions. We can only *observe* whether a load went fast (cache
   hit) or slow (recompile happened). That's a one-bit channel.

5. **WhisperKit's own download/load path may not tolerate missing
   weights.** `WhisperKitConfig(load: true)` initialises the full
   pipeline. If `WhisperKit.download(...)` is the only sanctioned way to
   populate the cache directory, we can't skip it cleanly.

## Investigation plan

Step 0 — **measure first** (per `ARCHITECTURE.md` measure-first rule):

1. After a successful warm load, snapshot:
   - The full e5rt cache contents (path, sizes, hashes).
   - The set of files CoreML `mmap`'d from the source `.mlmodelc`
     during steady-state inference. Use `fs_usage -w -f filesys
     -p <pid>` plus `vmmap -interleaved` snapshots taken during a
     transcribe call.
2. Delete `weights/weight.bin` only (leave metadata) and re-launch. Does
   load succeed? If yes, we have ~99 % of the win at near-zero risk.
3. Delete the whole `.mlmodelc` bundle and re-launch. Confirm the failure
   mode and exact CoreML error.
4. Force a cache miss (bump the e5rt path's OS-build dir or delete the
   cache subtree) with source weights still present. Time the
   recompile. If it's <60 s on a cold M4 this is a viable
   "redownload-on-invalidation" plan; if minutes, it isn't.

Step 1 — **decide between three outcomes:**

- **A. "Weights-only delete" works.** Source metadata stays, big
  `weight.bin` files get removed once compiled. Disk: 1.5 GB → ~100 MB.
  Ship behind a setting; default off until we've sampled cache-miss
  frequency.
- **B. Hybrid: keep source, prune *other* model variants more
  aggressively.** Already partly handled by
  `WhisperKitEngine.cleanupOtherModels(keeping:)` — verify and expand.
- **C. Park the spec.** If CoreML genuinely needs the full source
  resident, the disk saving isn't worth the redownload-on-update tax.
  Document the finding in `docs/research/` and close.

## Implementation sketch (only if A or B survives Step 1)

```swift
// OpenQuackKit/Transcription/WhisperKitEngine.swift
public static func compactSourceAfterWarmup(model: String) {
    // After a successful pipe.transcribe() round-trip, delete the
    // .mlmodelc/weights/weight.bin files. Keep the metadata + .mil
    // alongside so CoreML can still resolve the bundle path.
    // Idempotent. No-op if files already absent.
}

public static func sourceWeightsPresent(model: String) -> Bool { ... }
```

The app re-fetches on launch if `sourceWeightsPresent == false` *and* a
probe-load fails (signal: cache miss / OS updated). Probe-load happens
during the existing warmup so the user doesn't see a separate phase.

Settings surface (optional): "Reclaim disk after first use" toggle in
Settings → Advanced → Storage. Off by default for the first ship; flip
default to on once telemetry shows OS-update cache invalidation is rare
enough.

## Telemetry needed (depends on SPEC-013)

- Count of cache misses per launch (proxy: warmup time exceeded a
  threshold) — informs whether OS-update churn is rare or constant.
- Disk reclaimed by users who opted in — informs whether the win is
  real after the dust settles.

## Quality gates

If we ship this:

- A cache miss on a 16 GB M-series Mac must not exceed **15 s** of
  added latency at the first transcription post-update.
- The "weights compacted" mode must produce **identical** transcripts
  to the source-present mode on the bench corpus (no quiet quality
  drop). Re-run `BENCHMARKS.md` defaults both ways before flipping any
  default.
- Recovery from a missing-source-AND-missing-cache state must not
  silently fail — surface a one-shot "redownloading model…" overlay.

## Open questions

- Does CoreML reopen `weight.bin` between transcribe calls, or only
  during the first `MLModel(contentsOf:)` init? If only at init, we may
  even be able to delete it *after* the first warmup of each launch.
- Does `WhisperKit.download` skip a redownload if metadata files exist
  but `weight.bin` is absent? If it does a smart diff, the re-fetch
  cost is ~1.4 GB worst case but possibly much less for partial loss.
- Is the `e5bundlecache` shared between OpenQuack and any other
  WhisperKit-using app on the same machine? The path is under our
  Caches sandbox, so almost certainly not — but worth confirming;
  affects how we frame disk-usage savings to users who run multiple
  Whisper apps.

## References

- [SPEC-002](SPEC-002-transcription.md) — Transcription engine surface.
- `Sources/OpenQuackKit/Transcription/WhisperKitEngine.swift` —
  current model cache layout, `cleanupOtherModels`, download base.
- `docs/WHISPER-ON-MAC-FAQ.md` §"Why does the first transcription take
  so much longer than subsequent ones?" — cold-start mechanics.
- Apple — *e5rt / Espresso* is the on-device CoreML runtime. The
  `bnns_program.bnnsir` artifact is the compiled ANE program for a
  given graph + chip + OS-build triple. No public stable format.
