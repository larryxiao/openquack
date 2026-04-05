"""Global hotkey listener using pynput.

Registers a system-wide keyboard shortcut that works in any application.
Requires macOS Accessibility permissions for the terminal/app running this.
"""

from pynput import keyboard


def start_listener(hotkey_str: str, on_toggle, on_cancel):
    """Start a global hotkey listener in a daemon thread.

    Args:
        hotkey_str: pynput hotkey combo, e.g. "<ctrl>+<shift>+<space>"
        on_toggle: called when the main hotkey is pressed (start/stop toggle)
        on_cancel: called when Escape is pressed during recording
    """
    hotkey = keyboard.HotKey(keyboard.HotKey.parse(hotkey_str), on_toggle)

    def on_press(key):
        # Forward to hotkey detector
        hotkey.press(listener.canonical(key))
        # Escape to cancel
        if key == keyboard.Key.esc:
            on_cancel()

    def on_release(key):
        hotkey.release(listener.canonical(key))

    listener = keyboard.Listener(on_press=on_press, on_release=on_release)
    listener.daemon = True
    listener.start()
    return listener
