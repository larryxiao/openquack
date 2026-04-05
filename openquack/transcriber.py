"""Local speech-to-text — runs entirely on device, nothing leaves the machine.

Uses mlx-whisper (GPU-accelerated on Apple Silicon) with large-v3-turbo by default.
Falls back to faster-whisper on non-Apple-Silicon hardware.
"""

import platform
import numpy as np

# MLX model repo mapping (HuggingFace mlx-community)
_MLX_MODELS = {
    "tiny": "mlx-community/whisper-tiny",
    "base": "mlx-community/whisper-base",
    "small": "mlx-community/whisper-small",
    "medium": "mlx-community/whisper-medium",
    "large-v3": "mlx-community/whisper-large-v3",
    "large-v3-turbo": "mlx-community/whisper-large-v3-turbo",
}


def _can_use_mlx() -> bool:
    if platform.machine() != "arm64" or platform.system() != "Darwin":
        return False
    try:
        import mlx_whisper  # noqa: F401
        return True
    except ImportError:
        return False


class Transcriber:
    def __init__(
        self,
        model_size: str = "large-v3-turbo",
        device: str = "auto",
        compute_type: str = "int8",
        language: str | None = None,
        custom_words: list[str] | None = None,
    ):
        self.language = language
        self.custom_words = custom_words or []
        self._model_size = model_size
        self._device = device
        self._compute_type = compute_type
        self._use_mlx = _can_use_mlx()
        self._fw_model = None  # lazy-loaded faster-whisper model

    @property
    def backend(self) -> str:
        return "mlx-whisper" if self._use_mlx else "faster-whisper"

    def transcribe(self, audio: np.ndarray) -> str:
        """Transcribe audio array to text. Audio must be float32 at 16kHz."""
        if self._use_mlx:
            return self._transcribe_mlx(audio)
        return self._transcribe_faster_whisper(audio)

    # -- MLX backend (Apple Silicon, GPU-accelerated) -----------------------

    def _transcribe_mlx(self, audio: np.ndarray) -> str:
        import mlx_whisper

        repo = _MLX_MODELS.get(self._model_size, self._model_size)
        initial_prompt = ", ".join(self.custom_words) if self.custom_words else None

        result = mlx_whisper.transcribe(
            audio,
            path_or_hf_repo=repo,
            language=self.language,
            initial_prompt=initial_prompt,
            word_timestamps=False,
            condition_on_previous_text=True,
        )
        return result.get("text", "").strip()

    # -- faster-whisper fallback (CPU) --------------------------------------

    def _transcribe_faster_whisper(self, audio: np.ndarray) -> str:
        if self._fw_model is None:
            from faster_whisper import WhisperModel

            device = self._device if self._device != "auto" else "cpu"
            self._fw_model = WhisperModel(
                self._model_size,
                device=device,
                compute_type=self._compute_type,
            )

        initial_prompt = ", ".join(self.custom_words) if self.custom_words else None

        segments, _info = self._fw_model.transcribe(
            audio,
            beam_size=5,
            language=self.language,
            initial_prompt=initial_prompt,
            vad_filter=True,
            vad_parameters=dict(min_silence_duration_ms=500),
        )
        return " ".join(seg.text for seg in segments).strip()
