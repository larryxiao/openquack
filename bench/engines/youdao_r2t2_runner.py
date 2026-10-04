#!/usr/bin/env python3
"""Long-running NetEase Youdao Confucius4-R2T2 / Qwen3-ASR runner for OpenQuack.

Document Standard: ASD-STE100 (Simplified Technical English).
Specification: SPEC-046.

Reads line-oriented commands from standard input and writes one response line
per command to standard output:

    LOAD <model_id>
        -> "LOADED <load_seconds>" or "ERROR <message>"

    TRANSCRIBE\t<audio_path>\t<language>\t<context>
    (or space-separated: TRANSCRIBE <audio_path> [<language>])
        -> JSON: {"text": str, "wall_seconds": float, "audio_seconds": float,
                  "language": str|null}
           or "ERROR <message>"

    EXIT
        -> exits with code 0
"""
from __future__ import annotations

import json
import os
import sys
import time
import traceback
import wave
from pathlib import Path
from typing import Any, Optional, Tuple

MODEL_ALIASES = {
    "confucius4-r2t2": "netease-youdao/Confucius4-R2T2",
    "r2t2": "netease-youdao/Confucius4-R2T2",
    "youdao": "netease-youdao/Confucius4-R2T2",
    "default": "netease-youdao/Confucius4-R2T2",
    "qwen3-asr-1.7b": "Qwen/Qwen3-ASR-1.7B",
    "qwen3-asr": "Qwen/Qwen3-ASR-1.7B",
    "qwen3-asr-0.6b": "Qwen/Qwen3-ASR-0.6B",
}

LANGUAGE_CODE_TO_NAME = {
    "zh": "Chinese",
    "en": "English",
    "ja": "Japanese",
    "ko": "Korean",
    "fr": "French",
    "de": "German",
    "es": "Spanish",
    "it": "Italian",
    "pt": "Portuguese",
    "ru": "Russian",
    "ar": "Arabic",
}

LANGUAGE_NAME_TO_CODE = {v.lower(): k for k, v in LANGUAGE_CODE_TO_NAME.items()}

_ASR_TEXT_TAG = "<asr_text>"
_LANG_PREFIX = "language "

_HALF_TO_FULL = {
    ",": "，",
    ".": "。",
    "!": "！",
    "?": "？",
    ";": "；",
    ":": "：",
    "(": "（",
    ")": "）",
}
_FULL_TO_HALF = {v: k for k, v in _HALF_TO_FULL.items()}
_ALL_PUNCT = set(_HALF_TO_FULL) | set(_FULL_TO_HALF)

_backend_kind: Optional[str] = None
_model_obj: Any = None
_loaded_model_id: Optional[str] = None


def resolve_model_id(raw: str) -> str:
    """Resolve a short alias to a canonical HuggingFace model identifier."""
    trimmed = raw.strip()
    if not trimmed:
        return MODEL_ALIASES["default"]
    return MODEL_ALIASES.get(trimmed.lower(), trimmed)


def _is_cjk(ch: str) -> bool:
    return "\u4e00" <= ch <= "\u9fff" or "\u3400" <= ch <= "\u4dbf"


def _is_ascii_alpha(ch: str) -> bool:
    return ("a" <= ch <= "z") or ("A" <= ch <= "Z") or ("0" <= ch <= "9") or ch in "\"'"


def normalize_punct_by_context(text: str) -> str:
    """Normalize punctuation width based on the preceding character context.

    Ported from NetEase Youdao Confucius4-R2T2 (`r2t2/r2t2_asr.py`).
    """
    chars = list(text)
    prev_ctx: Optional[str] = None

    for i, ch in enumerate(chars):
        if ch in _ALL_PUNCT:
            if prev_ctx == "zh" and ch in _HALF_TO_FULL:
                chars[i] = _HALF_TO_FULL[ch]
            elif prev_ctx == "en" and ch in _FULL_TO_HALF:
                chars[i] = _FULL_TO_HALF[ch]
        elif _is_cjk(ch):
            prev_ctx = "zh"
        elif _is_ascii_alpha(ch):
            prev_ctx = "en"

    cjk_punct = set(_HALF_TO_FULL.values()) | {"、", "《", "》", "「", "」", "『", "』"}
    out: list[str] = []
    for i, ch in enumerate(chars):
        if ch in (" ", "\t") and out:
            prev_ch = out[-1]
            next_ch: Optional[str] = None
            for j in range(i + 1, len(chars)):
                if chars[j] not in (" ", "\t"):
                    next_ch = chars[j]
                    break
            if (
                next_ch is not None
                and (_is_cjk(prev_ch) or prev_ch in cjk_punct)
                and (_is_cjk(next_ch) or next_ch in cjk_punct)
            ):
                continue
        out.append(ch)
    return "".join(out)


def parse_language_output(raw: str, user_language: Optional[str] = None) -> Tuple[Optional[str], str]:
    """Extract language code and normalized text from raw Qwen3-ASR / R2T2 output."""
    s = raw.strip()
    if not s:
        return user_language, ""
    if _ASR_TEXT_TAG in s:
        meta_part, text_part = s.split(_ASR_TEXT_TAG, 1)
        detected_lang: Optional[str] = None
        for line in meta_part.splitlines():
            line = line.strip()
            if line.lower().startswith(_LANG_PREFIX):
                val = line[len(_LANG_PREFIX):].strip()
                if val and val.lower() != "none":
                    detected_lang = LANGUAGE_NAME_TO_CODE.get(val.lower(), val.lower())
                    break
        return detected_lang or user_language, normalize_punct_by_context(text_part.strip())
    return user_language, normalize_punct_by_context(s)


def _audio_duration(path: str) -> float:
    p = Path(path)
    if p.suffix.lower() == ".wav":
        try:
            with wave.open(str(p), "rb") as w:
                rate = w.getframerate()
                return (w.getnframes() / rate) if rate > 0 else 0.0
        except Exception:
            pass
    try:
        import soundfile as sf  # type: ignore

        info = sf.info(str(p))
        return (info.frames / info.samplerate) if info.samplerate > 0 else 0.0
    except Exception:
        return 0.0


def _emit(line: str) -> None:
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def _handle_load(raw_model_id: str) -> None:
    global _backend_kind, _model_obj, _loaded_model_id
    model_id = resolve_model_id(raw_model_id)
    t0 = time.perf_counter()

    if model_id.startswith("mock:"):
        _backend_kind = "mock"
        _model_obj = model_id[len("mock:"):]
        _loaded_model_id = model_id
        _emit(f"LOADED {time.perf_counter() - t0:.4f}")
        return

    # Priority 1: Official Youdao r2t2 package (if installed with vLLM).
    if os.environ.get("OPENQUACK_YOUDAO_BACKEND", "").lower() in ("", "r2t2"):
        try:
            from r2t2 import R2T2ASR  # type: ignore

            mode = os.environ.get("OPENQUACK_YOUDAO_MODE", "onetime")
            _model_obj = R2T2ASR(model=model_id, mode=mode)
            _backend_kind = f"r2t2:{mode}"
            _loaded_model_id = model_id
            _emit(f"LOADED {time.perf_counter() - t0:.4f}")
            return
        except Exception:
            if os.environ.get("OPENQUACK_YOUDAO_BACKEND", "").lower() == "r2t2":
                raise

    # Priority 2: qwen_asr package (Transformers / MPS / CPU / CUDA).
    try:
        from qwen_asr.inference.qwen3_asr import Qwen3ASRModel  # type: ignore

        device_map = os.environ.get("OPENQUACK_YOUDAO_DEVICE", "auto")
        _model_obj = Qwen3ASRModel.from_pretrained(model_id, device_map=device_map)
        _backend_kind = "qwen_asr"
        _loaded_model_id = model_id
        _emit(f"LOADED {time.perf_counter() - t0:.4f}")
        return
    except Exception:
        pass

    # Priority 3: HuggingFace transformers ASR pipeline fallback.
    try:
        import torch  # type: ignore
        from transformers import pipeline  # type: ignore

        device = "mps" if hasattr(torch.backends, "mps") and torch.backends.mps.is_available() else "cpu"
        if torch.cuda.is_available():
            device = "cuda:0"
        _model_obj = pipeline(
            "automatic-speech-recognition",
            model=model_id,
            device=device,
            trust_remote_code=True,
        )
        _backend_kind = "transformers"
        _loaded_model_id = model_id
        _emit(f"LOADED {time.perf_counter() - t0:.4f}")
        return
    except Exception as exc:
        raise RuntimeError(
            f"Could not load {model_id}. Install qwen-asr or r2t2 (`pip install qwen-asr soundfile`). "
            f"Underlying error: {exc}"
        ) from exc


def _handle_transcribe(
    audio_path: str,
    language: Optional[str],
    context: Optional[str],
) -> None:
    if _backend_kind is None or _model_obj is None:
        _emit("ERROR no model loaded")
        return

    audio_secs = _audio_duration(audio_path)
    t0 = time.perf_counter()
    lang_code = language.strip().lower() if language and language.strip() and language.strip() != "-" else None
    lang_name = LANGUAGE_CODE_TO_NAME.get(lang_code, lang_code) if lang_code else None
    ctx_str = context.strip() if context and context.strip() and context.strip() != "-" else ""

    if _backend_kind == "mock":
        raw_out = f"language Chinese<asr_text>{_model_obj}"
        detected, text = parse_language_output(raw_out, user_language=lang_code)
    elif _backend_kind and _backend_kind.startswith("r2t2:"):
        mode = _backend_kind.split(":", 1)[1]
        if mode == "stream":
            res = _model_obj.streaming_transcribe(audio_path, context=ctx_str, language=lang_name)
        else:
            res = _model_obj.transcribe(audio_path, context=ctx_str, language=lang_name)
        text = normalize_punct_by_context((res.text or "").strip())
        raw_lang = (res.language or "").strip().lower()
        detected = LANGUAGE_NAME_TO_CODE.get(raw_lang, raw_lang or lang_code)
    elif _backend_kind == "qwen_asr":
        kwargs: dict[str, Any] = {"audio": [audio_path]}
        if lang_name:
            kwargs["language"] = [lang_name]
        if ctx_str:
            kwargs["context"] = [ctx_str]
        outputs = _model_obj.transcribe(**kwargs)
        first = outputs[0] if isinstance(outputs, list) and outputs else outputs
        if hasattr(first, "text"):
            raw_text = first.text or ""
            raw_lang = getattr(first, "language", None)
            detected, text = parse_language_output(raw_text, user_language=lang_code)
            if raw_lang:
                detected = LANGUAGE_NAME_TO_CODE.get(str(raw_lang).lower(), str(raw_lang).lower())
        else:
            detected, text = parse_language_output(str(first), user_language=lang_code)
    else:
        out = _model_obj(audio_path)
        raw_text = out.get("text", "") if isinstance(out, dict) else str(out)
        detected, text = parse_language_output(raw_text, user_language=lang_code)

    wall = time.perf_counter() - t0
    _emit(
        json.dumps(
            {
                "text": text,
                "wall_seconds": wall,
                "audio_seconds": audio_secs,
                "language": detected,
            },
            ensure_ascii=False,
        )
    )


def _parse_transcribe_line(line: str) -> Tuple[str, Optional[str], Optional[str]]:
    payload = line[len("TRANSCRIBE"):].lstrip(" \t")
    if "\t" in payload:
        parts = payload.split("\t")
        audio_path = parts[0]
        language = parts[1] if len(parts) > 1 and parts[1] != "-" else None
        context = parts[2] if len(parts) > 2 and parts[2] != "-" else None
        return audio_path, language, context
    parts = payload.split(" ", 2)
    audio_path = parts[0]
    language = parts[1] if len(parts) > 1 and parts[1] != "-" else None
    context = parts[2] if len(parts) > 2 and parts[2] != "-" else None
    return audio_path, language, context


def main() -> None:
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            if line.startswith("LOAD "):
                _handle_load(line.split(" ", 1)[1])
            elif line.startswith("TRANSCRIBE"):
                audio_path, language, context = _parse_transcribe_line(line)
                _handle_transcribe(audio_path, language, context)
            elif line == "EXIT":
                return
            else:
                _emit(f"ERROR unknown command: {line!r}")
        except Exception as exc:
            traceback.print_exc(file=sys.stderr)
            _emit(f"ERROR {type(exc).__name__}: {exc}")


if __name__ == "__main__":
    main()
