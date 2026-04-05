"""OpenQuack — main application orchestrator.

Pipeline:
  Default:  Hotkey → Record → Transcribe (Whisper MLX) → Paste
  --polish: Hotkey → Record → Transcribe → Polish (Ollama) → Paste

Everything runs locally. No audio or text ever leaves the machine.
"""

import argparse
import sys
import threading
import time as _time

from .config import Config
from .recorder import Recorder
from .transcriber import Transcriber
from .context import gather_context
from .output import paste_at_cursor, play_sound
from .overlay import Overlay
from .hotkey import start_listener


class QuackApp:
    def __init__(self, config: Config):
        self.config = config
        self.recorder = Recorder(config.sample_rate)
        self.overlay = Overlay()
        self._thinker = None  # lazy — only created when polish=True
        self._transcriber: Transcriber | None = None
        self._is_recording = False
        self._lock = threading.Lock()

    # -- hotkey callbacks (called from listener thread) ---------------------

    def toggle(self):
        with self._lock:
            if self._is_recording:
                self._stop_and_process()
            else:
                self._start_recording()

    def cancel(self):
        with self._lock:
            if not self._is_recording:
                return
            self._is_recording = False
        self.recorder.stop()
        self.overlay.send("CANCELLED")
        if self.config.play_sounds:
            play_sound("cancel")
        _log("Recording cancelled")

    # -- internal -----------------------------------------------------------

    def _start_recording(self):
        self._is_recording = True
        self.overlay.send("RECORDING")
        if self.config.play_sounds:
            play_sound("start")
        self.recorder.start()
        _log("Recording started — press hotkey again to stop, Esc to cancel")

    def _stop_and_process(self):
        self._is_recording = False
        audio = self.recorder.stop()
        if self.config.play_sounds:
            play_sound("stop")

        duration = len(audio) / self.config.sample_rate
        if duration < self.config.min_duration:
            self.overlay.send("CANCELLED")
            _log(f"Too short ({duration:.1f}s) — cancelled")
            return

        _log(f"Captured {duration:.1f}s of audio")
        self.overlay.send("TRANSCRIBING")
        threading.Thread(target=self._process_pipeline, args=(audio,), daemon=True).start()

    def _process_pipeline(self, audio):
        t_start = _time.perf_counter()
        metrics: dict[str, float] = {}
        try:
            # Step 1 — Local STT
            t0 = _time.perf_counter()
            transcriber = self._get_transcriber()
            raw = transcriber.transcribe(audio)
            metrics["stt"] = _time.perf_counter() - t0

            if not raw.strip():
                self.overlay.send("ERROR:No speech detected")
                _log("No speech detected in audio")
                return
            _log(f"Transcript: {raw}")

            output = raw

            # Step 2 — Polish with local LLM (opt-in)
            if self.config.polish:
                ctx = gather_context()
                _log(f"Context: {ctx.get('app', '?')} — {ctx.get('window_title', '?')}")
                self.overlay.send("POLISHING")
                t0 = _time.perf_counter()
                try:
                    thinker = self._get_thinker()
                    output = thinker.polish(raw, ctx)
                    _log(f"Polished: {output}")
                except Exception as exc:
                    _log(f"LLM unavailable ({exc}), using raw transcript")
                metrics["llm"] = _time.perf_counter() - t0

            # Step 3 — Paste at cursor
            if self.config.auto_paste:
                paste_at_cursor(output)
            if self.config.play_sounds:
                play_sound("done")
            self.overlay.send("DONE")

            metrics["total"] = _time.perf_counter() - t_start
            _log_metrics(metrics, len(audio) / self.config.sample_rate)

        except Exception as exc:
            msg = str(exc)[:60]
            self.overlay.send(f"ERROR:{msg}")
            _log(f"Error: {exc}")

    def _get_transcriber(self) -> Transcriber:
        if self._transcriber is None:
            self._transcriber = Transcriber(
                model_size=self.config.whisper_model,
                device=self.config.whisper_device,
                compute_type=self.config.whisper_compute,
                language=self.config.whisper_language,
                custom_words=self.config.custom_words,
            )
            _log(f"Whisper '{self.config.whisper_model}' via {self._transcriber.backend}")
        return self._transcriber

    def _get_thinker(self):
        if self._thinker is None:
            from .thinker import Thinker
            self._thinker = Thinker(self.config.ollama_url, self.config.ollama_model)
        return self._thinker

    # -- lifecycle ----------------------------------------------------------

    def run(self):
        """Start the app. Blocks on the overlay event loop."""
        _print_banner(self.config)

        if self.config.polish:
            from .thinker import Thinker
            thinker = Thinker(self.config.ollama_url, self.config.ollama_model)
            if thinker.is_available():
                _log(f"Ollama + {thinker.model}: ready")
                thinker.warm()
                self._thinker = thinker
            else:
                _log(f"Ollama/{thinker.model} not reachable — polish will fall back to raw")
                _log(f"  Start Ollama and run: ollama pull {thinker.model}")

        start_listener(self.config.hotkey, self.toggle, self.cancel)
        _log("Listening for hotkey... (Ctrl+C to quit)\n")

        if self.config.show_overlay:
            self.overlay.run()  # blocks
        else:
            try:
                threading.Event().wait()
            except KeyboardInterrupt:
                pass


def _log(msg: str):
    print(f"  {msg}", flush=True)


def _log_metrics(metrics: dict[str, float], audio_secs: float):
    parts = [f"audio={audio_secs:.1f}s"]
    for key in ("stt", "llm", "total"):
        if key in metrics:
            parts.append(f"{key}={metrics[key]:.2f}s")
    _log(f"Metrics: {' | '.join(parts)}")


def _print_banner(config: Config):
    hotkey_display = (
        config.hotkey
        .replace("<ctrl>", "Ctrl")
        .replace("<shift>", "Shift")
        .replace("<space>", "Space")
        .replace("+", " + ")
    )
    mode = f"whisper + {config.ollama_model}" if config.polish else "whisper only"
    print()
    print("  OpenQuack  ~  privacy-first voice to text")
    print("  ────────────────────────────────────────────")
    print(f"  Hotkey        {hotkey_display}")
    print(f"  STT model     whisper {config.whisper_model} (local, mlx)")
    print(f"  Mode          {mode}")
    print(f"  Auto-paste    {'on' if config.auto_paste else 'off'}")
    print()


def main():
    parser = argparse.ArgumentParser(
        description="OpenQuack — privacy-first voice to text",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Examples:\n"
               "  python -m openquack                  # whisper-only (default)\n"
               "  python -m openquack --polish          # enable LLM cleanup\n"
               "  python -m openquack --polish --llm gemma3:1b\n",
    )
    parser.add_argument("--polish", action="store_true",
                        help="Enable LLM polishing via Ollama (requires Ollama running)")
    parser.add_argument("--llm", help="Ollama model for polishing (e.g. gemma4:e2b, gemma3:1b)")
    parser.add_argument("--model", help="Whisper model (tiny/base/small/medium/large-v3-turbo)")
    parser.add_argument("--hotkey", help='Hotkey combo (default: "<ctrl>+<shift>+<space>")')
    parser.add_argument("--language", help="Force language (e.g. en, ja, zh). Default: auto-detect")
    parser.add_argument("--no-paste", action="store_true", help="Copy to clipboard only, don't paste")
    parser.add_argument("--no-overlay", action="store_true", help="No floating status window")
    parser.add_argument("--no-sound", action="store_true", help="Disable system sounds")
    args = parser.parse_args()

    config = Config.load()
    if args.polish:
        config.polish = True
    if args.llm:
        config.ollama_model = args.llm
        config.polish = True  # --llm implies --polish
    if args.model:
        config.whisper_model = args.model
    if args.hotkey:
        config.hotkey = args.hotkey
    if args.language:
        config.whisper_language = args.language
    if args.no_paste:
        config.auto_paste = False
    if args.no_overlay:
        config.show_overlay = False
    if args.no_sound:
        config.play_sounds = False

    app = QuackApp(config)
    try:
        app.run()
    except KeyboardInterrupt:
        print("\n  Quack! Goodbye.\n")
        sys.exit(0)
