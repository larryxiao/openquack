"""Configuration for OpenQuack."""

from dataclasses import dataclass, field
from pathlib import Path
import json


CONFIG_DIR = Path.home() / ".config" / "openquack"
CONFIG_FILE = CONFIG_DIR / "config.json"


@dataclass
class Config:
    # Global hotkey (pynput format)
    hotkey: str = "<ctrl>+<shift>+<space>"

    # Audio capture
    sample_rate: int = 16000
    channels: int = 1
    min_duration: float = 0.5  # Minimum recording seconds

    # Whisper STT (mlx-whisper on Apple Silicon, faster-whisper fallback)
    whisper_model: str = "large-v3-turbo"  # tiny, base, small, medium, large-v3, large-v3-turbo
    whisper_device: str = "auto"
    whisper_compute: str = "int8"  # faster-whisper only: int8, float16, float32
    whisper_language: str | None = None  # Auto-detect if None
    custom_words: list[str] = field(default_factory=list)  # Bias STT toward these words

    # LLM polishing (off by default — Whisper-only is fast and needs no Ollama)
    polish: bool = False
    ollama_url: str = "http://localhost:11434"
    ollama_model: str = "gemma4:e2b"

    # Output
    auto_paste: bool = True  # Paste at cursor after processing
    play_sounds: bool = True

    # Overlay
    show_overlay: bool = True

    @classmethod
    def load(cls) -> "Config":
        if CONFIG_FILE.exists():
            try:
                raw = json.loads(CONFIG_FILE.read_text())
                return cls(**{k: v for k, v in raw.items() if k in cls.__dataclass_fields__})
            except Exception:
                pass
        return cls()

    def save(self):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_FILE.write_text(json.dumps(self.__dict__, indent=2, default=str))
