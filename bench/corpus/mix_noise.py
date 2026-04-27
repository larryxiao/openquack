#!/usr/bin/env python3
"""Generate noise-augmented clips for the OpenQuack bench.

Walks a source bucket of clean speech (default: bench/corpus/voices), mixes
each clip with synthetic noise at configurable SNRs, and writes the mixed
clips + their reference text into bench/corpus/noisy/.

We use synthetic noise (white / pink) instead of curated environmental
recordings to avoid licensing complexity. White-only and pink-only buckets
are written separately so the bench can compare model robustness across
spectrums.

Usage:
    python3 bench/corpus/mix_noise.py
    python3 bench/corpus/mix_noise.py --source bench/corpus/librispeech --snr 0,5,15
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List

import numpy as np
import soundfile as sf

DEFAULT_SOURCE = "bench/corpus/voices"
DEFAULT_OUT = "bench/corpus/noisy"
DEFAULT_SNRS = [5, 10, 20]


def pink_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    """Generate ~1/f (pink) noise via the Voss-McCartney algorithm.

    Cheap and good enough for our purposes; not a perfect 1/f spectrum but
    very close in the relevant audio band.
    """
    octaves = max(1, int(np.ceil(np.log2(max(n, 1)))))
    rows = octaves + 1
    array = rng.standard_normal((rows, n))
    # Hold each row's value for 2**i samples — mimics octave-band randomness.
    for i in range(1, rows):
        step = 2**i
        for col in range(0, n, step):
            array[i, col:col + step] = array[i, col]
    pink = array.sum(axis=0)
    return pink / np.max(np.abs(pink) + 1e-12)


def mix_at_snr(clean: np.ndarray, noise: np.ndarray, snr_db: float) -> np.ndarray:
    """Scale noise so the resulting SNR (dB) matches the requested value, then add."""
    # Match length.
    if len(noise) < len(clean):
        reps = (len(clean) // len(noise)) + 1
        noise = np.tile(noise, reps)[:len(clean)]
    else:
        noise = noise[:len(clean)]

    # Compute current powers (avoid divide-by-zero on silent clips).
    clean_power = float(np.mean(clean**2)) + 1e-12
    noise_power = float(np.mean(noise**2)) + 1e-12

    target_noise_power = clean_power / (10 ** (snr_db / 10))
    scale = np.sqrt(target_noise_power / noise_power)
    mixed = clean + noise * scale

    # Light peak limiting so we don't clip on int16 export.
    peak = float(np.max(np.abs(mixed))) + 1e-12
    if peak > 0.99:
        mixed = mixed * (0.99 / peak)
    return mixed.astype(np.float32)


def find_clips(source: Path) -> List[Path]:
    """Return all WAV clips under `source` that have a sibling `.txt`."""
    out = []
    for wav in source.rglob("*.wav"):
        if wav.with_suffix(".txt").exists():
            out.append(wav)
    return sorted(out)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--source", default=DEFAULT_SOURCE,
                   help=f"Clean-speech source dir (default: {DEFAULT_SOURCE})")
    p.add_argument("--out", default=DEFAULT_OUT,
                   help=f"Output dir (default: {DEFAULT_OUT})")
    p.add_argument("--snr", default=",".join(str(s) for s in DEFAULT_SNRS),
                   help=f"Comma-separated SNR levels in dB (default: {DEFAULT_SNRS})")
    p.add_argument("--noises", default="white,pink",
                   help="Noise types to apply (default: white,pink)")
    p.add_argument("--seed", type=int, default=42, help="RNG seed for reproducibility")
    args = p.parse_args()

    source = Path(args.source)
    out_root = Path(args.out)
    snrs = [int(s.strip()) for s in args.snr.split(",") if s.strip()]
    noises = [n.strip() for n in args.noises.split(",") if n.strip()]
    rng = np.random.default_rng(args.seed)

    clips = find_clips(source)
    if not clips:
        print(f"error: no .wav/.txt pairs found under {source}", file=sys.stderr)
        return 1

    print(f"→ {len(clips)} source clips × {len(noises)} noise types × {len(snrs)} SNRs "
          f"= {len(clips) * len(noises) * len(snrs)} mixes")

    written = 0
    for clip_path in clips:
        clean, sr = sf.read(str(clip_path), dtype="float32", always_2d=False)
        if clean.ndim > 1:
            clean = clean.mean(axis=1)
        ref_text = clip_path.with_suffix(".txt").read_text(encoding="utf-8").strip()
        clip_id = clip_path.stem

        for noise_kind in noises:
            for snr_db in snrs:
                if noise_kind == "white":
                    noise = rng.standard_normal(len(clean)).astype(np.float32)
                elif noise_kind == "pink":
                    noise = pink_noise(len(clean), rng).astype(np.float32)
                else:
                    print(f"warning: unknown noise type '{noise_kind}' — skipping", file=sys.stderr)
                    continue

                mixed = mix_at_snr(clean, noise, snr_db)
                bucket = out_root / f"{noise_kind}_snr{snr_db}db"
                bucket.mkdir(parents=True, exist_ok=True)
                out_wav = bucket / f"{clip_id}_{noise_kind}{snr_db}db.wav"
                out_txt = bucket / f"{clip_id}_{noise_kind}{snr_db}db.txt"
                sf.write(str(out_wav), mixed, sr, subtype="PCM_16")
                out_txt.write_text(ref_text + "\n", encoding="utf-8")
                written += 1

    print(f"✓ Wrote {written} noise-augmented clips under {out_root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
