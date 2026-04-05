"""Clipboard management and paste-at-cursor via macOS system APIs."""

import subprocess
import time


def paste_at_cursor(text: str):
    """Copy text to clipboard and simulate Cmd+V to paste at the current cursor."""
    _copy_to_clipboard(text)
    time.sleep(0.05)  # Brief delay for clipboard to settle
    _simulate_paste()


def _copy_to_clipboard(text: str):
    process = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
    process.communicate(text.encode("utf-8"))


def _simulate_paste():
    subprocess.run(
        [
            "osascript", "-e",
            'tell application "System Events" to keystroke "v" using command down',
        ],
        capture_output=True, timeout=3,
    )


def play_sound(name: str):
    """Play a macOS system sound (non-blocking)."""
    sounds = {
        "start": "/System/Library/Sounds/Pop.aiff",
        "stop": "/System/Library/Sounds/Blow.aiff",
        "done": "/System/Library/Sounds/Glass.aiff",
        "error": "/System/Library/Sounds/Basso.aiff",
        "cancel": "/System/Library/Sounds/Funk.aiff",
    }
    path = sounds.get(name)
    if path:
        subprocess.Popen(["afplay", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
