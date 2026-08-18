# OpenQuack Tutorial

A 5-minute walkthrough from install to your first dictation. Everything runs locally on your Mac by default.

## 1. Install

```sh
brew tap larryxiao/openquack https://github.com/larryxiao/openquack
brew install --cask openquack
```

Or [download the DMG](https://github.com/larryxiao/openquack/releases) and drag into Applications. First launch: right-click → **Open** → **Open** (one-time Gatekeeper bypass since the build isn't notarised yet).

## 2. First launch

A welcome window walks you through the four things OpenQuack needs:

- **Microphone permission.** Click **Allow** when macOS prompts. OpenQuack uses the mic only while a hotkey is pressed; nothing is captured passively.
- **Accessibility permission.** Required for paste-at-cursor. macOS opens **System Settings → Privacy & Security → Accessibility**; toggle OpenQuack on.
- **Speech model download.** A ~700 MB Whisper model lands in `~/Library/Application Support/OpenQuack/WhisperKit/`. After this, dictation runs entirely offline.
- **Hotkey.** Default ⌃⇧Space (Control + Shift + Space). Change it any time in **Settings → Shortcut**.

Skip onboarding by closing the window — settings are accessible from the menu-bar duck at any time.

## 3. Your first dictation

Open any text field — Notes, Slack, Terminal, Mail, a browser address bar.

1. Press the hotkey (⌃⇧Space).
2. Speak.
3. Press the hotkey again.

The transcript pastes at the cursor a second or two after you stop. The menu-bar duck visibly morphs through phases — sitting (idle) → quacking (recording) → feather (transcribing) → swimming (ready).

If paste-at-cursor is off (or Accessibility is denied), the transcript lands on your clipboard and you press ⌘V yourself.

## 4. Tweak it

Open **Settings** from the menu-bar duck → **gear icon**.

- **General → Speech model.** `medium` is the default; `large-v3` is the most accurate (slower, more memory). `tiny` and `base` are fast but less reliable on accents and proper nouns.
- **General → Language.** Auto-detect by default, and it handles non-English and mixed speech well (as of alpha.17). Pin your primary language if you only ever dictate in one — it skips the detection step for a touch less latency.
- **General → Custom dictionary.** One word or phrase per line — proper nouns, jargon, project names. Whisper biases toward these.
- **Shortcut.** Press once to start dictating; press again to stop.
- **Stats.** Words dictated, audio processed, time saved versus typing — local-only, opt-in display.
- **History.** Recent transcripts kept on disk so you can re-paste yesterday's dictation. Audio storage is a separate opt-in (privacy posture — voice carries biometrics).

## 5. When it doesn't work

- **macOS keeps asking for mic / accessibility on every update.** Pre-notarised builds change signature on each release; macOS treats each build as a different app. Lands once a stable Developer ID signature is in place.
- **First dictation is slow.** Cold-loading the model into memory takes a few seconds. Subsequent dictations are instant — the model stays warm until the app quits.
- **Hotkey conflicts with another app.** Pick a different chord in **Settings → Shortcut**. ⌃⇧Space is uncommon enough to avoid most conflicts but isn't sacred.
- **Wrong language detected.** Set language explicitly in **Settings → General → Transcription language**.
- **Domain words come out wrong** ("cloud code" instead of "Claude Code"). Add them to the custom dictionary in **Settings → General**.

## What's next

Dictation is the foundation. Coming up: in-context transcription (the agent reads where you're about to paste), a thinking pass that turns raw spoken sentences into ones you'd press send on, and agent dispatch (speak → Claude Code does the thing). Roadmap and specs in [`docs/ROADMAP.md`](ROADMAP.md).

---

Stuck on something this guide doesn't cover? Open an issue: <https://github.com/larryxiao/openquack/issues>.
