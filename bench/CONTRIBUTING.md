# Contributing benchmark results

We're building a hardware × model accuracy/speed matrix so OpenQuack can ship
sane defaults per Mac class. Results from your Mac help directly.

## Run the bench

From the repo root, on the `v2` branch:

```sh
# 1. Generate the self-test corpus (uses macOS `say`).
bash bench/corpus/fetch.sh

# 2. Build + run. First run downloads WhisperKit models (~few hundred MB to a few GB).
swift run openquack-bench \
  --engines whisperkit \
  --models tiny,small,large-v3-turbo \
  --corpus bench/corpus \
  --verbose
```

Output lands in `bench/out/<host-tag>/`:
- `report.md` — human-readable per-engine × model summary + per-clip detail.
- `report.csv` — same data, flattened, for spreadsheet diff.
- `host.json` — chip / GPU cores / memory / macOS version.

## Add the lightning baseline

To compare WhisperKit against the v0.1 Python baseline:

```sh
# A python venv with lightning-whisper-mlx; .venv at repo root is auto-detected.
python3 -m venv .venv
source .venv/bin/activate
pip install -r bench/engines/requirements.txt

swift run openquack-bench \
  --engines whisperkit,lightning \
  --models distil-large-v3 \
  --corpus bench/corpus \
  --verbose
```

Note: not every model name is supported on every engine; see `--help` for the
suggested list per engine.

## Submit results

Open a PR adding `bench/out/<your-host-tag>/{report.md,report.csv,host.json}`.
We aggregate them into `docs/BENCHMARKS.md`. Keep your `host.json` honest —
peak RSS and RTF depend on what else is running, so close other heavy apps
before benching.

## What we're trying to learn

- **Smallest Mac that runs OpenQuack at <1× RTF** for typical voice input.
- **Recommended default model per memory tier** (8 / 16 / 24 / 36+ GB).
- **Where accuracy plateaus vs model size.**
- **WhisperKit vs lightning** on Apple Silicon today.
