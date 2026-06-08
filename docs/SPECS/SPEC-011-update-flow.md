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

## Phase B.5 — silent brew upgrade (no Terminal window)

Status: implemented (see PR that cites this SPEC section).

### Goal

When the user clicks Upgrade and OpenQuack was installed via Homebrew,
run `brew upgrade --cask openquack` silently in the background — no
Terminal window, no clipboard dance. The duck disappears for ~30
seconds, then the new version relaunches itself.

### Design constraints

**Quit-first, relaunch-after.** The running binary must exit *before*
brew swaps the bundle, not after. Keeping the app alive during the
upgrade means brew can move resource files out from under the running
process; any bundle load that happens in that window (icon refresh,
sound, popover open) can crash, and if it does there is no parent
process left to do `open -a OpenQuack`. The sequence must be:

```
click Upgrade
  └─ write + launch detached /tmp/openquack-upgrade-*.sh
  └─ appState.updateStatus = .upgrading   (banner → "Installing…")
  └─ NSApp.terminate after 1.5 s          (old binary exits cleanly)

[old process gone]

detached script (reparented to launchd):
  └─ brew upgrade --cask openquack
  └─ open -a OpenQuack                    (new binary starts)
  └─ rm -- "$0"
```

The 1.5 s window is long enough for the "Installing update…" banner to
render and give the user a moment to see what's happening before the
duck disappears. It is short enough that the script is already running
before the parent exits.

**No conflict between old and new instance.** The old process exits at
t ≈ 1.5 s; `open -a OpenQuack` fires at t ≈ 30–60 s (brew network
latency). There is no overlap. macOS single-instance behaviour
(`applicationShouldHandleReopen`) is not exercised because the old
process is already gone.

**Detached script, not an in-process `Process`.** Running brew inside
the live app and quitting on `terminationHandler` completion is
attractive for live progress but inherits the bundle-swap risk above.
A detached shell script survives the parent's exit (reparented to
launchd), eliminates the race, and keeps `UpgradeAction` stateless.

**Explicit PATH.** GUI-launched processes inherit a sparse PATH
(`/usr/bin:/bin:/usr/sbin:/sbin`). `brew` itself is reachable by
absolute path (`<prefix>/bin/brew`), but brew shells out to `curl`,
`git`, and sometimes `gpg`. The script env sets:

```
PATH=<prefix>/bin:/usr/bin:/bin:/usr/sbin:/sbin
HOMEBREW_PREFIX=<prefix>
```

### State machine change

`UpdateCheckStatus` gains a new case `.upgrading` (no associated value).
It is active from the moment the script is launched until the process
exits (~1.5 s). `hasAvailableUpdate` returns `false` for `.upgrading`
so the `⬆` status-item badge clears immediately on click.

UI surfaces:
- **Popover banner**: replaces the "Upgrade" button row with a
  `ProgressView` + "Installing update… Duck will be back in ~30 seconds."
- **Settings → About chip**: shows `ProgressView` + "Installing…" text.

### Error handling

- Script write fails → restore `.available(release)`; user can retry.
- `/bin/bash` exec fails → same; also remove the partially-written script.
- brew exits non-zero → `open -a OpenQuack` runs anyway (semicolon, not
  `&&`), so the duck comes back. The new instance will re-poll for
  updates on launch; if the version is unchanged it shows `.upToDate`.

### Acceptance criteria

1. Brew-installed OpenQuack: click Upgrade in the popover. No Terminal
   window opens. The banner changes to "Installing update… Duck will be
   back in ~30 seconds." The duck disappears ≈ 1.5 s later.
2. After brew finishes (≈ 30–60 s on a typical connection), OpenQuack
   relaunches. `About` shows the new version string.
3. If the cask is already at the latest version, OpenQuack still
   relaunches cleanly (exit 0 from brew, `open -a` fires).
4. Manual (DMG) installs: Upgrade button still opens the DMG URL in the
   browser; no change to that path.
5. Simulate a script-write failure (e.g. chmod 000 /tmp momentarily):
   the Upgrade button reappears; no crash.

### Out of scope

- Progress percentage during the brew download (brew has no structured
  progress API; best-effort stdout parsing is deferred).
- Notification when the new version is ready (the duck reappearing is
  the signal; a `UNUserNotification` is a stretch for a future PR).
- DMG users: still manual; Sparkle handles this path in Phase C.

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
