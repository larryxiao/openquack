# SPEC-025 — Code signing + notarisation

**Status:** draft (Adoption focus)
**Owner:** `scripts/` + `.github/workflows/`
**Last updated:** 2026-05-14

---

## Problem statement

OpenQuack ships today as an ad-hoc-signed `.app` in an unsigned `.dmg`
(`scripts/make_dmg.sh` runs `hdiutil` and exits — no `codesign`, no
`notarytool`, no `stapler`). On first launch a fresh user hits the macOS
Gatekeeper dialog *"OpenQuack can't be opened because Apple cannot check it
for malicious software"* and has to right-click → Open → confirm. That's the
single biggest install-funnel drop for indie Mac apps; many users churn
rather than navigate the Open-Anyway dance. The cask path (`brew install
--cask openquack`) hides the worst of it but still inherits the unnotarised
bundle. Notarisation eliminates the dialog on every supported macOS (13+);
stapling lets the system verify the ticket offline.

## Goal

- The shipped `.dmg` is signed by **Developer ID Application**, hardened
  runtime is on, the bundle is notarised by Apple's `notarytool`, and the
  notarisation ticket is stapled to **both** the `.app` and the `.dmg`.
- First launch on a never-trusted Mac (or a fresh user account) shows **zero
  Gatekeeper dialogs**.
- A `git tag vX.Y.Z` push runs the entire build → sign → notarise → staple →
  publish flow in CI; the maintainer's local box only needs to bump version
  + cask SHA.

## Non-goals

- **Mac App Store distribution.** Different identity (Mac App Distribution),
  sandbox profile, asset pipeline. Deferred indefinitely.
- **Replacing the brew cask.** `Casks/openquack.rb` stays; the DMG behind it
  is just signed + notarised now. The cask SHA update remains the same step
  it is today.
- **Apple Silicon-only vs universal.** Out of scope here; we ship whatever
  `swift build -c release --product openquack` produces today (universal once
  the host toolchain is configured for it; that's a separate spec).
- **Migration tooling for users on pre-signed builds.** `brew upgrade --cask
  openquack` or a fresh download is enough; no in-app one-shot.

## Technical approach

### Prerequisites (one-time, ~1-2 hours)

1. Enrol in the Apple Developer Program ($99/yr — real cost, not free).
2. Generate a **Developer ID Application** cert via `developer.apple.com` →
   Certificates, IDs & Profiles. Install in the login keychain; export
   `.p12` for CI.
3. Generate a `notarytool` **App Store Connect API key** (Users and Access →
   Integrations → Keys, role "Developer"). Download the `.p8` once. We pick
   API keys over the legacy Apple-ID + app-specific password path — no 2FA
   juggling in CI; the key file is the only secret.

### Signing model

`scripts/wrap_app.sh` already does hardened runtime + Apple TSA timestamp +
entitlements when a `Developer ID Application:` identity is in the keychain
(lines 119-125). Gaps:

- The current command uses `codesign --force --deep --sign ...`. `--deep` is
  deprecated and signs in the wrong order (outside-in). Replace with an
  inside-out loop, per
  [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements):
  sign every nested bundle under `Contents/Resources/*.bundle` (dropped
  there by `wrap_app.sh:69-72`) first, then sign the outer `.app`:

  ```sh
  for b in "$BUNDLE"/Contents/Resources/*.bundle; do
      codesign --force --options runtime --timestamp \
          --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$b"
  done
  codesign --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$BUNDLE"
  ```

- The DMG itself isn't signed today. After `hdiutil create` in
  `make_dmg.sh`, add `codesign --sign "$IDENTITY" --timestamp "$DMG"`.

### Entitlements

The existing file at `scripts/openquack.entitlements` (referenced by
`wrap_app.sh:99`) is extended in-place — we don't introduce a parallel
"Distribution.entitlements". Final set:

| Key | Required? | Why |
|---|---|---|
| `com.apple.security.device.audio-input` | yes (already there) | Microphone capture via `AVAudioEngine`. |
| `com.apple.security.automation.apple-events` | yes (new) | `Sources/OpenQuackApp/UpgradeAction.swift` uses `NSAppleScript` to drive Terminal for `brew upgrade --cask openquack`. Under hardened runtime, sending Apple Events to another app needs this. |
| `com.apple.security.cs.allow-jit` | **no** | No MLX / `mlx-swift` / WhisperKit-JIT path in `Sources/` or `Package.swift` (verified). |
| `com.apple.security.cs.disable-library-validation` | **no** | No user-provided dylibs are loaded; all linkage is SwiftPM-resolved at build time. |

Paste-at-cursor (`Sources/OpenQuackKit/Output/PasteService.swift`) posts
`⌘V` via `CGEvent.post(tap: .cghidEventTap)`, which is gated by the
**Accessibility** TCC permission — not `automation.apple-events`. No
entitlement needed for that path.

### Notarisation

Add `scripts/notarise.sh` (or fold the same logic into
`scripts/make_dmg.sh`) that runs **after** the DMG is signed:

```sh
xcrun notarytool submit "$DMG" --key "$API_KEY_P8" \
    --key-id "$API_KEY_ID" --issuer "$API_ISSUER_ID" --wait
xcrun stapler staple "$DMG"
xcrun stapler staple "$BUNDLE"        # staple the .app inside, too
spctl -a -t open --context context:primary-signature -vv "$DMG"
```

`--wait` makes `notarytool` block until Apple returns accepted/rejected;
typical wall time is 1-5 minutes for our bundle size.

### CI / GitHub Actions

A new workflow `.github/workflows/release.yml` triggers on `push: tags:
['v*']`. It imports the signing cert into a temporary keychain, runs
`wrap_app.sh` + `make_dmg.sh` + `notarise.sh`, then `gh release create
vX.Y.Z OpenQuack-X.Y.Z.dmg`. Secrets introduced by this spec, **exact
names**:

| Secret | Contents |
|---|---|
| `MAC_DEVELOPER_ID_P12_BASE64` | `base64 -i DeveloperIDApplication.p12` |
| `MAC_DEVELOPER_ID_P12_PASSWORD` | export password for the `.p12` |
| `MAC_NOTARY_API_KEY_BASE64` | `base64 -i AuthKey_XXXXXXXXXX.p8` |
| `MAC_NOTARY_API_KEY_ID` | 10-character key ID from App Store Connect |
| `MAC_NOTARY_API_ISSUER_ID` | UUID issuer ID from App Store Connect |

Workflow steps: checkout → decode `.p12` into a temporary keychain (`security
import` + `set-key-partition-list`) → decode `.p8` → export
`OQ_SIGN_IDENTITY="Developer ID Application: ..."` so `wrap_app.sh` picks the
right identity → run `make_dmg.sh` (which now signs the DMG and invokes
`notarise.sh`) → `gh release upload` the stapled DMG → delete the temporary
keychain on `always()`.

### Cask interaction

`Casks/openquack.rb` lives in this repo (not a sibling tap). The SHA update
flow is unchanged — `make_dmg.sh` already prints the `sed` invocation at
exit. After this SPEC lands, the DMG behind that SHA is signed + notarised
+ stapled. PR-C may automate the SHA bump post-notarisation later.

## Verification / rollout plan

- **Smoke (fresh Mac / fresh user account):** download the DMG from the
  GitHub Release, mount, drag to `/Applications`, launch — confirm **no
  Gatekeeper dialog**, no right-click-required flow.
- `spctl --assess --verbose` on the mounted `.app` should print
  `accepted source=Notarized Developer ID`.
- **Offline staple check:** disconnect from network, then `stapler
  validate OpenQuack.app` — must return `worked`.
- The first signed + notarised release ships as **`v2.0.0-beta.1`** (not
  another alpha) — the install-quality jump warrants the channel bump
  and the change is visible in `livecheck` output.

## Out of scope

- Mac App Store distribution (different identity + sandbox).
- Setapp / paid third-party distribution.
- Mac Developer ID kernel-extension signing (N/A — no kext).
- `.pkg` installer alongside the DMG (deferred; DMG drag-install is
  conventional for menu-bar apps).
- Sparkle integration (SPEC-026 — lands after this).
- Migration tooling for users on the current ad-hoc builds — they re-run
  `brew upgrade --cask openquack` or download fresh.

## Open questions

- **Keep the `NSAppleScript` upgrade path?** Adding
  `automation.apple-events` lets `UpgradeAction.swift` drive Terminal
  cleanly but triggers a "OpenQuack would like to control Terminal" TCC
  prompt on first use. The fallback at `UpgradeAction.swift:46-49`
  (clipboard + `NSWorkspace.open(Terminal)`) works without the
  entitlement. Decision affects whether we ship the entitlement at all.
- **Document the entitlements file in-tree.** `scripts/openquack.entitlements`
  is committed today; keeping it committed is correct (transparency for a
  privacy-positioned app), but the file header should say so.
- **One Developer ID for all channels?** A single identity is simpler and
  Apple's recommendation; per-channel buys nothing here.
- **Auto-bump cask SHA in CI (PR-C)?** Auto-bump is convenient but pushes
  a commit from CI, which interacts with branch protection. Decide in
  PR-C; manual remains the fallback.

## PR shape

| PR  | Title                                                                | SPEC cite | Effort | CI gate |
|-----|----------------------------------------------------------------------|-----------|--------|---------|
| this| `docs(SPEC-025): code signing + notarisation`                        | SPEC-025  | XS     | — |
| PR-A| `feat(scripts): sign DMG + notarise + staple; entitlements update`   | SPEC-025  | S      | manual smoke on maintainer box |
| PR-B| `ci(release): tag-triggered workflow → signed/notarised DMG release` | SPEC-025  | S      | release.yml dry-run on a test tag |
| PR-C| `chore(cask): auto-bump SHA post-notarisation (optional)`            | SPEC-025  | XS     | swift build (no code change) |

PR-A edits `scripts/wrap_app.sh`, `scripts/make_dmg.sh`,
`scripts/openquack.entitlements`, and adds `scripts/notarise.sh` (or folds
the notarise + staple steps into `make_dmg.sh`). PR-B adds
`.github/workflows/release.yml` and documents the five secrets. PR-C is
optional and gated on PR-B landing; it's safe to defer.
