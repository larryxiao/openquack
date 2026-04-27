# Install

## Recommended — Homebrew (once v0 is released)

```sh
brew install --cask openquack
```

The cask formula at `Casks/openquack.rb` points to the GitHub release artefact.
Until the first release is tagged, `:no_check` is the placeholder sha256 — the
formula is shipped now so the install path is documented and reviewable; the
actual hash drops in once `scripts/make_dmg.sh` produces a release-ready DMG.

## DMG (manual)

Download `OpenQuack-<version>.dmg` from the
[Releases page](https://github.com/OpenQuack/openquack/releases), open it,
drag OpenQuack into Applications.

The DMG is **ad-hoc codesigned, not notarised** until we have an Apple
Developer account. First launch:

```
right-click OpenQuack.app → Open → Open
```

Subsequent launches don't need that.

## From source (for developers / agents)

Requires **Xcode 16+** (full Xcode, not just CommandLineTools — KeyboardShortcuts
and similar deps use `#Preview` macros that need the Xcode plugin).

```sh
git clone https://github.com/OpenQuack/openquack.git
cd openquack
git checkout v2

# Build + bundle into build/OpenQuack.app
bash scripts/wrap_app.sh

# Run
open build/OpenQuack.app
```

`wrap_app.sh` auto-uses the Xcode toolchain when CommandLineTools is the
default `xcode-select`. Output lands at `build/OpenQuack.app` and is ad-hoc
codesigned so Gatekeeper doesn't block local launches.

## Build a DMG yourself

```sh
bash scripts/make_dmg.sh
# → build/OpenQuack-<version>.dmg
```

The script prints the sha256 — paste it into `Casks/openquack.rb` if you're
preparing a release.

## Uninstall

If installed via Homebrew:

```sh
brew uninstall --cask openquack
```

The cask's `zap` block also removes:
- `~/Library/Application Support/OpenQuack/` (last-recording.wav and any
  state we add later)
- `~/Library/Preferences/org.openquack.OpenQuack.plist` (Settings)
- `~/Library/Saved Application State/org.openquack.OpenQuack.savedState`
- `~/.cache/openquack-bench/` (Lightning bench model cache, if you ran the
  bench)

If you installed manually, dragging OpenQuack.app to the Trash is enough;
the above paths are safe to leave or remove by hand.

## What gets downloaded on first run

- WhisperKit's `medium` Core ML package (~700 MB) — cached under
  `~/Library/Application Support/com.argmaxinc.WhisperKit/` (managed by
  WhisperKit, not us). Subsequent launches don't re-download.

Nothing else is downloaded by default; the agent backends (when they ship)
are explicit opt-ins.

## Permissions you'll be asked for

1. **Microphone** — required. We can't transcribe what we can't hear.
2. **Accessibility** — optional. Required only for *auto-paste*; the
   transcript still goes to your clipboard if denied.

Both are reversible from System Settings → Privacy & Security at any time.
