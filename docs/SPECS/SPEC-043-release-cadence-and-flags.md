# SPEC-043 — Release cadence, feature flags & runbook

## Goal

Make releases boring and safe: a predictable **cadence**, features shipped
**behind a flag first**, and a codified **runbook** so cutting a release is a
checklist, not a bespoke event. This is the process answer to the freeze/crash
rollbacks — risky work should reach users dark and gated, not live-on-merge.

## Background

Releases have been ad-hoc, and instability has shipped straight to users (two
rollbacks to alpha.16/18). Three practices fix that: decouple merge from release
(flags), make the cut repeatable (runbook), and ship to opt-in users first
(existing prerelease channel).

## Mechanism

### Feature flags — "behind a flag first"

`FeatureFlags` (OpenQuackPlatform): a `FeatureFlag` is `{ key, defaultEnabled }`,
resolved against `UserDefaults` (explicit override beats the release default).
New/risky features merge with their flag **defaulting `false`**, ship dark, and
flip on — per test build or for everyone in a later release — once validated.
The flag graduates (deleted, behaviour inlined) when proven. No remote config; it
matches the app's existing `@AppStorage` toggle convention.

The registry (`FeatureFlags.all`) is empty today — alpha.20 shipped flagless by
maintainer call. The **next** unvalidated feature (the kind of thing #88/#89
were) registers a flag here instead of going live.

### Cadence

- Cut an **alpha** when a batch of merges has accumulated, targeting a steady
  drumbeat (≈ weekly) rather than on-demand heroics. Prereleases reach opt-in
  users first via the existing alpha channel (`receivePrereleases` +
  `appcast-alpha.xml`); promote to "Latest" once it's held up.
- A flagged feature graduates on its **own** schedule, independent of the release
  it merged in.

### Runbook (the steps, as executed for alpha.20)

1. Bump `OpenQuackPlatform.version`.
2. `bash scripts/make_dmg.sh` → builds + signs the app, packs `OpenQuack-<v>.dmg`,
   prints the **sha256**.
3. Update `Casks/openquack.rb`: `version` + `sha256` (the printed value).
4. Update the README "What's new" banner (newest first; keep ~3).
5. Appcast: add a signed `<item>` to `docs/appcast-alpha.xml` — **blocked on the
   Sparkle EdDSA key** (SPEC-026); until then it stays empty and brew is the alpha
   path.
6. Commit (version + cask + README) → release PR → merge to `main`.
7. `gh release create v<v> --target <main-sha> --latest --notes-file … <dmg>`.
8. **Verify**: release asset name == cask URL; cask `sha256` == `shasum -a 256`
   of the uploaded DMG; GitHub "Latest" == the new tag.

> A `release-bot` (SPEC-037) can automate steps 1–8 once signing/notarisation
> lands (SPEC-025); until then it's the maintainer's gated, checklist-driven cut.

## Privacy impact

None. `FeatureFlags` is local UserDefaults; no network, no telemetry. The runbook
ships the same on-device app.

## Acceptance criteria

- [ ] `FeatureFlags.isEnabled` returns the flag default with no override, the
      override when set, and the default again after `reset`. (unit test)
- [ ] New unvalidated features land with a flag defaulting `false` and are absent
      from the shipped UI/behaviour until flipped. (convention — enforced in review)
- [ ] The runbook above reproduces a release (it cut alpha.20). (manual)
- [ ] `swift build && swift test` green.

## Out of scope

- Remote / server-driven flags, percentage rollouts — local boolean flags only.
- Automated release CI — documented as a `release-bot` follow-up (SPEC-037),
  gated on signing (SPEC-025).
