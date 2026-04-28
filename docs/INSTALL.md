# Install

## Homebrew (recommended)

OpenQuack ships as a Homebrew cask. Until it's accepted into the official
[`homebrew-cask`](https://github.com/Homebrew/homebrew-cask) — that requires
an Apple Developer ID + notarised builds, which is on the roadmap — install
it via this repo as a tap:

```sh
brew tap OpenQuack/openquack https://github.com/OpenQuack/openquack
brew install --cask openquack
```

That points at `Casks/openquack.rb` in this repo, which fetches the latest
DMG attached to a [GitHub release](https://github.com/OpenQuack/openquack/releases).

To upgrade later:

```sh
brew upgrade --cask openquack
```

To uninstall:

```sh
brew uninstall --cask openquack
```

Once OpenQuack lands in `homebrew-cask`, the tap step goes away and
`brew install --cask openquack` will work directly.

## DMG (manual)

Download `OpenQuack-<version>.dmg` from the
[Releases page](https://github.com/OpenQuack/openquack/releases), open it,
drag OpenQuack into Applications.

Pre-notarisation DMGs come with an "unidentified developer" prompt on first
open. Bypass once with:

```
right-click OpenQuack.app → Open → Open
```

Subsequent launches don't need that.

## From source (for developers)

See [`DEVELOPMENT.md`](DEVELOPMENT.md) — covers the full build, signing options, the CLI, and the benchmark framework.

## Uninstall

`brew uninstall --cask openquack` removes the app. Add `--zap` to also delete
state OpenQuack writes outside `/Applications`:

- `~/Library/Application Support/OpenQuack/` — speech model cache, last-recording.wav, app state.
- `~/Library/Preferences/org.openquack.OpenQuack.plist` — Settings.
- `~/Library/Saved Application State/org.openquack.OpenQuack.savedState`
- `~/.cache/openquack-bench/` — only if you ran the benchmark CLI.

If you installed manually, dragging OpenQuack.app to the Trash is enough;
the paths above are safe to leave or remove by hand.

## What gets downloaded on first run

- The `medium` speech model (~700 MB) — cached under
  `~/Library/Application Support/OpenQuack/WhisperKit/`. Subsequent
  launches don't re-download.
- A daily check against GitHub Releases for new versions; turn it off by
  blocking network access if you'd rather not.

Nothing else is downloaded by default.

## Permissions you'll be asked for

1. **Microphone** — required. We can't transcribe what we can't hear.
2. **Accessibility** — optional. Required only for *auto-paste*; the
   transcript still goes to your clipboard if denied.

Both are reversible from System Settings → Privacy & Security at any time.
