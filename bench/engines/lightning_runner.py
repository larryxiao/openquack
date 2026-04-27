#!/usr/bin/env python3
"""Long-running lightning-whisper-mlx process for the OpenQuack benchmark.

Reads commands line-by-line from stdin, writes one response line per command
to stdout:

    LOAD <model>
        -> "LOADED <load_seconds>" or "ERROR <message>"

    TRANSCRIBE <audio_path> [<language>]
        -> JSON: {"text": str, "wall_seconds": float, "audio_seconds": float,
                  "language": str|null}
           or "ERROR <message>"

    EXIT
        -> exits cleanly

Errors are reported on stdout (so the Swift caller doesn't have to demux
stderr); the original exception traceback goes to stderr for humans.
"""
from __future__ import annotations

import json
import os
import sys
import time
import traceback
import wave
from pathlib import Path
from typing import Optional

# Lightning stores distil models under CWD/mlx_models/ — chdir to a stable
# location so re-runs reuse the same cache regardless of where Swift launched us.
CACHE_DIR = Path.home() / ".cache" / "openquack-bench" / "lightning"
CACHE_DIR.mkdir(parents=True, exist_ok=True)
os.chdir(CACHE_DIR)

_model = None


def _audio_duration(path: str) -> float:
    p = Path(path)
    if p.suffix.lower() == ".wav":
        try:
            with wave.open(str(p), "rb") as w:
                return w.getnframes() / w.getframerate()
        except Exception:
            pass
    # Fallback for non-WAV (mp3 / m4a / flac).
    try:
        import soundfile as sf  # type: ignore
        info = sf.info(str(p))
        return info.frames / info.samplerate
    except Exception:
        return 0.0


def _emit(line: str) -> None:
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def _handle_load(model_id: str) -> None:
    global _model
    from lightning_whisper_mlx import LightningWhisperMLX  # noqa: WPS433
    t0 = time.perf_counter()
    _model = LightningWhisperMLX(model=model_id, batch_size=12)
    _emit(f"LOADED {time.perf_counter() - t0:.4f}")


def _handle_transcribe(audio_path: str, language: Optional[str]) -> None:
    if _model is None:
        _emit("ERROR no model loaded")
        return
    audio_secs = _audio_duration(audio_path)
    t0 = time.perf_counter()
    result = _model.transcribe(audio_path, language=language)
    wall = time.perf_counter() - t0
    text = (result.get("text") or "").strip()
    detected = result.get("language")
    _emit(json.dumps({
        "text": text,
        "wall_seconds": wall,
        "audio_seconds": audio_secs,
        "language": detected,
    }))


def main() -> None:
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            if line.startswith("LOAD "):
                _handle_load(line.split(" ", 1)[1])
            elif line.startswith("TRANSCRIBE "):
                parts = line.split(" ", 2)
                audio_path = parts[1]
                language = parts[2] if len(parts) > 2 else None
                _handle_transcribe(audio_path, language)
            elif line == "EXIT":
                return
            else:
                _emit(f"ERROR unknown command: {line!r}")
        except Exception as exc:
            traceback.print_exc(file=sys.stderr)
            _emit(f"ERROR {type(exc).__name__}: {exc}")


if __name__ == "__main__":
    main()
