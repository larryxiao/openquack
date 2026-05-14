# SPEC-026 — Sparkle auto-update

**Status:** draft
**Effort:** M

Supersedes the Phase C "deferred to M3" note in
[SPEC-011](SPEC-011-update-flow.md). SPEC-011 Phase A (install-aware banner)
already shipped; this SPEC turns the banner's "Download" button into a real
in-app update for DMG users while keeping the Homebrew path untouched.

---

## Problem statement

Existing users have to re-download the DMG (or run `brew upgrade --cask
openquack`) every release. Downloading a fresh DMG is a 30-second task
most users won't do; non-cask alpha users miss every fix between the
one they installed and the next time they happen to revisit the site.
The popover already shows a "v… is here" banner via `UpdateChecker` +
`UpgradeAction`, but for DMG users tapping it still means "open browser
→ mount DMG → drag." This SPEC closes that gap: Sparkle for DMG users,
brew untouched.

---

## Goal

1. **In-app update for DMG users.** Tap the banner → Sparkle downloads,
   verifies, relaunches into the new build.
2. **Brew path preserved.** Sparkle defers to cask when
   `installMethod == .homebrew`; the AppleScript-driven `brew upgrade
   --cask openquack` flow is unchanged.
3. **Pre-release channels.** Alpha / beta users opt into a prerelease
   appcast and stop missing fixes.
4. **Banner remains the primary CTA.** Sparkle's standard window is
   the install UI; the banner is the call to action. No competing
   "Update available" surfaces.

---

## Non-goals

- **Delta updates.** Full DMG every release is fine at our size;
  `BinaryDelta` adds release-pipeline weight.
- **Silent background install.** A menu-bar app that relaunches itself
  unprompted is a trust violation; always confirm.
- **Rollback UI.** Not Sparkle's strong suit; users can reinstall an
  older release manually.
- **Self-hosted update server.** GitHub Pages is enough.

---

## Technical approach

### Dependency + wiring

Add **Sparkle 2.x** to `Package.swift`, pinned to a tagged version
(not a branch): `.package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")`.
Link into `OpenQuackApp` only — `OpenQuackKit` stays UI-free.

Use the modern API: `SPUStandardUpdaterController` / `SPUUpdater`
(the older `SUUpdater` is deprecated). Instantiate
`SPUStandardUpdaterController(startingUpdater: true, …)` once at app
launch; `OpenQuackApp` holds it for the app's lifetime so scheduled
checks run.

### Info.plist additions

`OpenQuackApp` has no `Info.plist` on disk — SwiftPM generates one.
PR-A sorts the plist mechanics; required keys:

| Key | Value | Why |
|---|---|---|
| `SUFeedURL` | `https://larryxiao.github.io/openquack/appcast.xml` | Stable channel; runtime override switches to alpha when toggled. |
| `SUEnableAutomaticChecks` | `YES` | First-launch default. Runtime toggle binds to `SPUUpdater.automaticallyChecksForUpdates` (Sparkle persists it). |
| `SUScheduledCheckInterval` | `86400` | Daily; matches the existing `UpdateChecker` cadence. |
| `SUPublicEDKey` | base64 EdDSA pubkey | Sparkle 2.x verifies every update against this. DSA was dropped in Sparkle 2.x. |
| `SUAutomaticallyUpdate` | `NO` | See non-goals: always confirm. |

### Signing ritual

Run Sparkle's bundled `generate_keys` once. Public half → `Info.plist`
as `SUPublicEDKey`; private half lives in the maintainer's Keychain
(where `generate_keys` puts it) and as a GH Actions secret. **Never
commit either form.** Each release runs `sign_update <dmg>`; the EdDSA
signature goes into `<enclosure sparkle:edSignature="…">`. PR-C
codifies this.

### Appcast feed shape

One `<item>` per release. Spec at
<https://sparkle-project.org/documentation/>. Minimal example:

```xml
<item>
  <title>v2.0.0-alpha.11</title>
  <sparkle:version>2.0.0.11</sparkle:version>
  <sparkle:shortVersionString>2.0.0-alpha.11</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
  <enclosure url="…/OpenQuack-2.0.0-alpha.11.dmg"
    length="9123456" type="application/octet-stream"
    sparkle:edSignature="…base64…" />
</item>
```

`sparkle:version` is the integer-dotted build number Sparkle uses for
ordering; `sparkle:shortVersionString` carries the human tag; `length`
is the DMG byte count.

### Multi-channel layout

Three appcasts under `docs/`: `appcast.xml` (stable, default),
`appcast-beta.xml` (reserved for the future stable/beta split, not
user-pickable yet), `appcast-alpha.xml` (prerelease toggle ON).

Channel selection is a pure function, testable like SPEC-023's
`reconcile`:

```swift
enum UpdateChannel { case stable, beta, alpha }
func chooseAppcastURL(channel: UpdateChannel) -> URL
```

Maps `.stable → appcast.xml`, `.beta → appcast-beta.xml`, `.alpha →
appcast-alpha.xml`. The UI exposes only a binary toggle (`.stable` ↔
`.alpha`); the `.beta` case exists so the release script (PR-C) can
emit `appcast-beta.xml` against the same table later.

At launch, after `SPUStandardUpdaterController` starts, set
`updater.feedURL = chooseAppcastURL(channel: …)`. Flipping the toggle
re-sets `feedURL` and triggers an immediate `checkForUpdates(_:)`.

---

## Brew-cask coexistence

Hard rule: **two installers must never fight over the same `.app`
bundle.** Branch on the existing `state.installMethod`
(`InstallMethodDetector`, SPEC-011 Phase A).

| `installMethod` | Sparkle | Banner button |
|---|---|---|
| `.manual` | Registered, `automaticallyChecksForUpdates = true`, scheduled daily | `updater.checkForUpdates(nil)` — Sparkle's window downloads, verifies, relaunches |
| `.homebrew` | Registered, `automaticallyChecksForUpdates = false`, no dialogs | Unchanged — `UpgradeAction.run` AppleScripts `brew upgrade --cask openquack` |

`UpgradeAction.run` already switches on `InstallMethod`. Extend the
`.manual` branch from "open DMG URL" to "trigger Sparkle"; the
`.homebrew` branch is untouched. Sparkle stays registered for brew
users so the channel toggle keeps working if they switch install
methods, but it polls nothing and shows nothing on its own.

`UpdateChecker` (GitHub Releases polling) keeps running for both
install methods — it populates the in-popover banner, which is the
primary CTA. On `.manual`, Sparkle's scheduled check may also fire its
own dialog independently; both paths lead to the same signed install,
so we don't suppress one in favour of the other.

---

## Hosting the appcast

- `appcast.xml`, `appcast-beta.xml`, `appcast-alpha.xml` live under
  `docs/` and are served via GitHub Pages (configured in repo settings
  to serve `/docs`; there is no `_config.yml`).
- The alpha appcast carries every release; stable only carries
  non-prerelease tags.
- PR-C adds a release script: take the signed DMG, read its byte
  length, run `sign_update`, prepend the `<item>`, commit.
- **Cache:** Pages serves with `Cache-Control: max-age=600` —
  propagation takes ~10 minutes; PR-C must verify the deployed
  `appcast.xml` is reachable before announcing the cutover.

---

## Settings UI

In `Sources/OpenQuackApp/SettingsView.swift`'s `GeneralPane`, add an
"Updates" section after "Startup" (SPEC-023):

1. Toggle "Check for updates automatically" — runtime source of truth
   is `SPUUpdater.automaticallyChecksForUpdates` (Sparkle persists it
   itself). The toggle reads/writes through Sparkle; an `@AppStorage`
   mirror keeps the SwiftUI binding clean but isn't authoritative.
2. Toggle "Include pre-release builds (alpha/beta)" —
   `@AppStorage("receivePrereleases")`. Flipping it recomputes
   `chooseAppcastURL`, re-points `updater.feedURL`, and triggers an
   immediate check.
3. "Last checked: \<relative time\>" + "Check now" button calling
   `updater.checkForUpdates(nil)`.

**Prerelease first-launch default:** ON if `OpenQuackKit.version`
contains `-alpha` or `-beta` (respect installed channel); OFF
otherwise. One-shot — only applied if the key has never been written.

Sparkle ships its own download/install/relaunch window — use it
vanilla, no custom install UI.

---

## Test plan

- **Unit:** drive `chooseAppcastURL(channel:)` through all three cases;
  assert each returns the right URL. Pure function, no Sparkle mocking
  (mirrors SPEC-023's `reconcile` unit test).
- **Manual (DMG, happy path):** point `SUFeedURL` at a localhost
  `appcast.xml` with a newer `sparkle:version`. Confirm Sparkle's
  dialog appears, download proceeds, signature verifies, app
  relaunches into the new build.
- **Manual (brew):** with `state.installMethod == .homebrew`, confirm
  (a) no Sparkle scheduled check fires, (b) the popover banner still
  surfaces via `UpdateChecker`, (c) tapping "Upgrade" still runs
  `brew upgrade --cask openquack` in Terminal exactly as today.
- **Manual (channel toggle):** flip "Include pre-release builds";
  confirm `updater.feedURL` re-points and the next update offered is
  from `appcast-alpha.xml`.
- `swift build && swift test` green under the Xcode toolchain
  (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).

---

## Out of scope

- Everything in non-goals (delta updates, silent install, rollback,
  self-hosted server).
- Migrating the popover banner off `UpdateChecker` to a Sparkle-driven
  indicator — the banner stays as-is; Sparkle augments the install path.
- Migrating brew users to Sparkle — brew is the source of truth there.

---

## PR shape

| PR | Title | SPEC cite | Effort |
|---|---|---|---|
| this | `docs(SPEC-026): Sparkle auto-update` | SPEC-026 | XS |
| PR-A | `feat(updates): Sparkle dependency, SPUStandardUpdaterController, Info.plist keys, appcast template` | SPEC-026 | M |
| PR-B | `feat(settings): "Updates" pane — auto-check + prerelease toggle + Check now` | SPEC-026 | S |
| PR-C | `chore(release): sign DMG with sign_update, prepend appcast item, push docs/appcast.xml` | SPEC-026 | S |

PR-A is feature-flag-safe: with no `<item>` newer than the running
build, nothing changes user-visibly. PR-B adds the toggles. PR-C makes
the pipeline real; until then, appcast items can be hand-crafted for
end-to-end tests.

---

## Open questions

- **Beta installs default to which channel?** The first-launch default
  rule maps both `-alpha` and `-beta` binaries to the alpha channel
  because that's the only prerelease feed we'll publish initially.
  Once `appcast-beta.xml` is real, beta-installed users should default
  to `.beta`, not `.alpha`. Revisit at that cutover.
- **`SUAutomaticallyUpdate` for accessory apps.** Sparkle docs
  recommend `YES` for utilities so updates apply on relaunch without
  prompting. The SPEC's stance is `NO` (trust); flagged for revisit
  if users complain about the prompt.
- **`appcast-nightly.xml`.** Overkill at current cadence; would also
  need a nightly build job. Not planned.
