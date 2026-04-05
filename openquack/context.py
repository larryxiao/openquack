"""Gather local system context to help the LLM format output appropriately.

All context stays on device — nothing is sent to the cloud.
"""

import subprocess
import datetime


def gather_context() -> dict:
    """Return dict with active app, window title, and timestamp."""
    return {
        "app": _get_active_app(),
        "window_title": _get_window_title(),
        "time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    }


def _get_active_app() -> str:
    try:
        result = subprocess.run(
            [
                "osascript", "-e",
                'tell application "System Events" to get name of first '
                'application process whose frontmost is true',
            ],
            capture_output=True, text=True, timeout=2,
        )
        return result.stdout.strip() or "Unknown"
    except Exception:
        return "Unknown"


def _get_window_title() -> str:
    try:
        script = (
            'tell application "System Events"\n'
            '  set frontApp to first application process whose frontmost is true\n'
            '  tell frontApp\n'
            '    if (count of windows) > 0 then\n'
            '      return name of front window\n'
            '    end if\n'
            '  end tell\n'
            'end tell\n'
            'return ""'
        )
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=2,
        )
        return result.stdout.strip()
    except Exception:
        return ""
