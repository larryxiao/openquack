"""Floating status overlay — shows recording/processing/done state.

Uses tkinter for zero extra dependencies. Renders as a small dark pill
anchored to the top-center of the screen, just below the menu bar.
"""

import queue
import time
import tkinter as tk


# Catppuccin-inspired palette
_BG = "#1e1e2e"
_FG = "#cdd6f4"
_RED = "#f38ba8"
_ORANGE = "#fab387"
_GREEN = "#a6e3a1"
_GRAY = "#6c7086"
_BLUE = "#89b4fa"


class Overlay:
    """Thread-safe overlay controlled via a message queue."""

    def __init__(self):
        self.msg_queue: queue.Queue[str] = queue.Queue()
        self._root: tk.Tk | None = None
        self._recording_start: float = 0
        self._timer_id: str | None = None

    # -- public (called from any thread) ------------------------------------

    def send(self, msg: str):
        """Enqueue a state change. Thread-safe."""
        self.msg_queue.put(msg)

    def run(self):
        """Start the overlay event loop (blocks — call from main thread)."""
        self._root = tk.Tk()
        self._root.title("OpenQuack")
        self._root.overrideredirect(True)
        self._root.attributes("-topmost", True)
        self._root.attributes("-alpha", 0.92)
        self._root.configure(bg=_BG)

        # Size and position — top center, below menu bar
        w, h = 340, 48
        sx = self._root.winfo_screenwidth()
        self._root.geometry(f"{w}x{h}+{(sx - w) // 2}+48")

        # Content frame
        frame = tk.Frame(self._root, bg=_BG)
        frame.pack(fill="both", expand=True, padx=14, pady=8)

        self._dot = tk.Label(frame, text="\u25cf", fg=_GRAY, bg=_BG,
                             font=("Helvetica Neue", 18))
        self._dot.pack(side="left")

        self._label = tk.Label(frame, text="", fg=_FG, bg=_BG,
                               font=("Helvetica Neue", 13))
        self._label.pack(side="left", padx=(8, 0))

        self._sub = tk.Label(frame, text="", fg=_GRAY, bg=_BG,
                             font=("Helvetica Neue", 11))
        self._sub.pack(side="right")

        self._root.withdraw()
        self._poll()
        self._root.mainloop()

    # -- internal -----------------------------------------------------------

    def _poll(self):
        try:
            while True:
                msg = self.msg_queue.get_nowait()
                self._handle(msg)
        except queue.Empty:
            pass
        if self._root:
            self._root.after(50, self._poll)

    def _handle(self, msg: str):
        if msg == "RECORDING":
            self._recording_start = time.time()
            self._dot.config(fg=_RED)
            self._label.config(text="Recording...", fg=_FG)
            self._sub.config(text="0:00")
            self._root.deiconify()
            self._root.lift()
            self._tick_timer()

        elif msg == "TRANSCRIBING":
            self._cancel_timer()
            self._dot.config(fg=_ORANGE)
            self._label.config(text="Transcribing...", fg=_FG)
            self._sub.config(text="")

        elif msg == "POLISHING":
            self._dot.config(fg=_BLUE)
            self._label.config(text="Organizing thoughts...", fg=_FG)
            self._sub.config(text="")

        elif msg == "DONE":
            self._cancel_timer()
            self._dot.config(fg=_GREEN)
            self._label.config(text="Pasted!", fg=_GREEN)
            self._sub.config(text="")
            self._root.after(1800, self._hide)

        elif msg == "CANCELLED":
            self._cancel_timer()
            self._dot.config(fg=_GRAY)
            self._label.config(text="Cancelled", fg=_GRAY)
            self._sub.config(text="")
            self._root.after(1000, self._hide)

        elif msg.startswith("ERROR:"):
            self._cancel_timer()
            self._dot.config(fg=_RED)
            self._label.config(text=msg[6:], fg=_RED)
            self._sub.config(text="")
            self._root.after(3000, self._hide)

        elif msg == "HIDE":
            self._hide()

        elif msg == "QUIT":
            self._cancel_timer()
            if self._root:
                self._root.quit()

    def _tick_timer(self):
        if self._recording_start:
            elapsed = int(time.time() - self._recording_start)
            m, s = divmod(elapsed, 60)
            self._sub.config(text=f"{m}:{s:02d}")
            self._timer_id = self._root.after(1000, self._tick_timer)

    def _cancel_timer(self):
        self._recording_start = 0
        if self._timer_id and self._root:
            self._root.after_cancel(self._timer_id)
            self._timer_id = None

    def _hide(self):
        if self._root:
            self._root.withdraw()
