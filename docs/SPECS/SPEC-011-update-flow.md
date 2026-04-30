# SPEC-011 — Update flow: notification + one-click upgrade

## Goal

Let users on an outdated build know **inside the app**, with copy and a
button that match how they actually installed OpenQuack — and a hook
for proper auto-update once we have notarisation. Today's banner
("Click to download from GitHub Releases") is identical for brew users
and DMG users, which leads brew users to drag-install a DMG over their
brew-managed `.app` and silently drift `brew upgrade` out of sync.

## Phase A — install-aware banner (v2.0.0-alpha.3, this SPEC's MVP)

Status: implemented in this PR.

- `InstallMethodDetector` resolves `Bundle.main.bundleURL` and decides:
  - `.homebrew(prefix:)` if the path is under `<prefix>/Caskroom/openquack/`
    (resolved through symlinks), or if `<prefix>/Caskroom/openquack/.metadata`
    exists alongside a manual-looking `.app` (belt-and-braces).
  - `.manual` otherwise.
- `AppState.installMethod` is set once at launch and never changes.
- The popover's update banner adapts:
  - **Brew users:** copy `brew upgrade --cask openquack` to clipboard,
    open `Terminal.app`. User presses ⌘V + ⏎.
  - **Manual users:** open the DMG asset URL in the default browser
    (current behaviour).
- Menu-bar status item appends `⬆` to `🦆` when an update is detected
  and the app is idle / ready, so the duck reads as `🦆⬆` until the
  user opens the popover and acts.
- `Image(systemName: "arrow.down.circle")` in the banner uses
  `.symbolEffect(.bounce)` on macOS 14+ for a one-shot bounce when the
  banner first renders. Static fallback on Ventura.

## Phase B — designed icon set + animation

Deferred — needs visual iteration with the maintainer.

- Replace the emoji-text status item with an `NSImage`-based icon set:
  - Stroke-style duck rendered to match SF Symbols' visual language
    (`@Sendable` SF-Symbol-like proportions, monochrome template image
    that adapts to menu-bar dark/light + accent).
  - State variants: `idle`, `recording`, `transcribing`, `update`.
  - `update` overlays a small badge (`⬆` glyph or download arrow) in
    the duck's tail/wing area.
- One-shot intro animation when the update state first appears: a wing
  flap or a small bob via `CAAnimation` on the status item button's
  image layer.
- Stretch: a quack overlay (audio + glyph wiggle) the first time the
  user sees an update, gated behind `playSounds`.

Open questions for next session:
- Per-state custom icons or one icon + animation overlays?
- Light + dark menu-bar variants, or a single template image?
- How loud is "intriguing" — bounce on first detection only, or pulse
  every N hours until acknowledged?

## Phase C — proper auto-update via Sparkle

Deferred to **M3** (signed builds).

- Adopt [`Sparkle`](https://sparkle-project.org) once we have an Apple
  Developer ID and notarised builds. Sparkle handles download +
  in-place replace + relaunch, which we currently can't safely offer
  without a stable code signature across releases.
- For brew installs, surface a small "managed by Homebrew — auto-update
  is off" note instead of the Sparkle prompt; brew is the source of
  truth there.
- Cadence: same 24h polling, but Sparkle owns the UI for the install
  step.

## Verification

- **Phase A:** install via `brew install --cask openquack` against a
  pre-release tag, run `brew tap` + cask edit to point at a newer
  version → relaunch app, popover banner reads "Upgrade", clicking it
  drops the brew command on the clipboard and opens Terminal.
- Drag-install the DMG to `~/Desktop/OpenQuack.app`, run, repeat the
  cask trick → banner reads "Download", clicking opens the DMG asset
  URL in the browser.
- Menu-bar duck reads `🦆⬆` while idle, reverts to `🦆` after popover
  open + relaunch (next launch: `availableUpdate` is nil if cask sha
  matched, so duck is plain again).
