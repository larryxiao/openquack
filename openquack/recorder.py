"""Audio recording from microphone using sounddevice."""

import threading
import numpy as np
import sounddevice as sd


class Recorder:
    def __init__(self, sample_rate: int = 16000):
        self.sample_rate = sample_rate
        self._frames: list[np.ndarray] = []
        self._lock = threading.Lock()
        self._stream: sd.InputStream | None = None
        self.is_recording = False

    def start(self):
        """Start capturing audio from the default microphone."""
        self._frames = []
        self.is_recording = True
        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=1,
            dtype="float32",
            blocksize=1024,
            callback=self._audio_callback,
        )
        self._stream.start()

    def stop(self) -> np.ndarray:
        """Stop recording and return audio as a flat float32 numpy array."""
        self.is_recording = False
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        with self._lock:
            if self._frames:
                audio = np.concatenate(self._frames).flatten()
            else:
                audio = np.array([], dtype="float32")
            self._frames = []
        return audio

    def _audio_callback(self, indata: np.ndarray, frames: int, time_info, status):
        if self.is_recording:
            with self._lock:
                self._frames.append(indata.copy())

    @property
    def duration(self) -> float:
        """Current recording duration in seconds."""
        with self._lock:
            total_frames = sum(f.shape[0] for f in self._frames)
        return total_frames / self.sample_rate
