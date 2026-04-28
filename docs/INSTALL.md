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

## From source (for developers)

See [`DEVELOPMENT.md`](DEVELOPMENT.md) — covers the full build, signing options, the CLI, and the benchmark framework.

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
