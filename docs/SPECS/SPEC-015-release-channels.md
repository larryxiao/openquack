# SPEC-015 — Release channels (alpha / beta / stable)

**Status:** draft (M3)
**Owner:** `OpenQuackKit/Updates/`
**Last updated:** 2026-04-30

## Goal

An alpha tester sees *"You're on **alpha.5** (latest alpha). Stable is
2.0.0."* — never the disorienting *"upgrade to 2.0.0"* offered to
someone running 2.1.0-alpha.3. A stable user sees only stable releases,
never an alpha sneak-peek pushed by accident. The user can opt up or
down between channels with one Settings click.

This spec extends [SPEC-011](SPEC-011-update-flow.md) with explicit
channel awareness in the update pipeline, in the cask story, and in the
Sparkle integration that comes later.

## Non-goals

- Auto-channel-detection from telemetry — the running build's tag is
  the only signal, no analytics.
- Cross-channel bisect tooling, A/B feature gating. Channels are about
  *release vehicles*, not feature flags.
- Anything Sparkle-shaped before notarisation lands (SPEC-011 Phase C).
  We sketch the appcast layout here so the eventual Sparkle PR is small.

## Channels

| Channel | Tag pattern | Audience | Cadence |
|---|---|---|---|
| **alpha** | `vX.Y.Z-alpha.N` | maintainers + opt-in early users | per-feature, currently weekly |
| **beta** | `vX.Y.Z-beta.N` | broader testers, feature-frozen | per release-candidate, ~monthly |
| **stable** | `vX.Y.Z` (no suffix) | default for new installs once it exists | when beta soak passes |

Order from least to most conservative: **alpha < beta < stable**.

Today: only `alpha` exists (we're at `2.0.0-alpha.4`). `beta` and
`stable` are forward-looking and may not get their first tags until
`2.0.0` ships.

## Tag conventions

The single source of truth for a release's channel is its **tag name**,
not GitHub's `prerelease: true/false` flag (which has been mis-set on
real releases in the wild and can't be relied on).

Parse with:

```
^v(?<ver>\d+\.\d+\.\d+)(?:-(?<channel>alpha|beta)\.(?<n>\d+))?$
```

- Match → channel from `<channel>` capture (default `stable` when the
  pre-release suffix is absent).
- No match → log a warning, treat as `stable` for safety (the parser is
  forward-incompatible by design; if we add `rc` later, the spec
  amendment lands here first).

Tags failing the regex are not eligible to be served as updates.

## Update-check semantics

A user on channel **X** wants the **latest release where the release's
channel is at most as risky as X**. Concretely:

| Running channel | Eligible release channels | Picks |
|---|---|---|
| stable | stable | newest stable |
| beta | beta, stable | newest of either by version |
| alpha | alpha, beta, stable | newest of any |

Version comparison is **proper semver**, not the `String.compare(_:options:.numeric)`
that `UpdateChecker.isNewer` uses today. Specifically, per semver §11:

- A release version (`2.0.0`) is **greater** than any pre-release of the
  same base (`2.0.0-alpha.5`, `2.0.0-beta.1`).
- Pre-releases compare lexicographically by dot-separated identifiers,
  numeric where both are numeric (`alpha.10 > alpha.2`).

The current naive comparator silently breaks at the alpha→stable
boundary; SPEC-011's existing `// SPEC-??` TODO resolves here.

### `ReleaseInfo` shape (extension)

```swift
public extension UpdateChecker {
    enum Channel: String, Sendable, CaseIterable, Comparable {
        case alpha, beta, stable
        public static func < (a: Channel, b: Channel) -> Bool { … }
    }

    struct ReleaseInfo: Sendable, Equatable {
        // existing fields …
        public let channel: Channel
    }

    /// Latest release the running channel is willing to upgrade to.
    /// Pulls the *list* endpoint, not `/latest` — `releases/latest`
    /// excludes anything flagged prerelease and is unusable for our
    /// channel filtering.
    func latestForChannel(_ channel: Channel) async throws -> ReleaseInfo
}
```

The endpoint switch matters: `GET /repos/:owner/:repo/releases?per_page=20`
returns the most recent 20 tags including pre-releases; we filter
client-side. Rate-limit budget is unchanged (one request per 24h per
launch, well under the 60 req/h unauthenticated cap).

### `currentChannel` setting

- Defaults to the running build's channel, parsed from `Bundle.main`'s
  `CFBundleShortVersionString` (or the build-time-injected
  `OpenQuackKit.version`) at first launch.
- Stored under `UserDefaults` key `updateChannel` (string raw value).
- Read once at launch into `AppState.updateChannel`; the picker writes
  back through the same key.
- The `UpdateChecker` instance is initialised with the channel from
  settings; `latestForChannel(_:)` routes accordingly.

## Brew cask story

The canonical-name question: should `brew install --cask openquack`
mean stable or "whatever's latest"?

We adopt **Option B with a transitional period**:

1. **Today (no stable tag yet)** — `Casks/openquack.rb` continues to
   track `alpha`. We add `Casks/openquack-alpha.rb` as an alias of
   today's cask so users can already start migrating their tap to the
   channel-explicit name.
2. **First stable tag (`v2.0.0`)** — `openquack` cask flips to track
   stable. `openquack-alpha` keeps tracking alpha. Existing
   `openquack` users on alpha will be offered the stable on next
   `brew upgrade` — that's the *correct* behaviour because the
   canonical name carries the conservative-default expectation.
3. **Beta channel materialises** — add `Casks/openquack-beta.rb`.

Rationale for not doing **Option A** (single cask, livecheck-against-channel):
brew's `livecheck` is global per cask and can't be parameterised by
user preference. Rationale for not doing **Option C** (DMG-only for
pre-releases): the brew flow is *the* polished install path on macOS
and pre-release testers are exactly the audience who benefits most
from `brew upgrade --cask openquack-alpha` working cleanly.

The migration plan for existing alpha.4 users is a one-liner that
lands in the `2.0.0` release notes:

```
brew uninstall --cask openquack && brew install --cask openquack-alpha
```

(or equivalent `brew tap` re-fetch). Stale `openquack` users on alpha
who skip the migration get the stable upgrade prompt automatically —
fine, since they presumably want the safer channel anyway.

`Casks/openquack.rb` itself is not edited by this spec; that's the
follow-up "Brew cask reorganisation" PR in the implementation order.

## Sparkle integration (forward)

When notarisation lands and SPEC-011 Phase C ships, Sparkle takes over
the in-app upgrade UI. Sparkle natively supports channels via
`<sparkle:channel>`. Layout:

```
docs/appcasts/
  appcast-stable.xml   ← stable releases only
  appcast-beta.xml     ← stable + beta
  appcast-alpha.xml    ← stable + beta + alpha
```

Each appcast embeds the same `<sparkle:channel>` value in every
`<item>` so a misconfigured client gracefully falls back. The running
app picks its appcast URL by `currentChannel` at launch.

Hosting: GitHub Pages on the docs branch, or `https://openquack.app/`
once that exists. Either way the URL set is fixed at build time.

Out of scope here: the actual Sparkle PR. We pin the layout so the
eventual change is "wire `SUFeedURL` per channel" plus the appcast
generators in `scripts/`.

## Settings UX

A new sub-section in **Settings → About** (no full new pane required):

```
─── Updates ──────────────────────────────────────
You're on  alpha.5  ·  Apr 30 2026
Channel    [ Alpha  ▾ ]
           Latest changes, may break.

           [ Check now ]   Last checked: 2 min ago
─────────────────────────────────────────────────
```

- Picker options carry one-line descriptions:
  - **Stable** — "Production releases only."
  - **Beta** — "Feature-frozen, undergoing testing."
  - **Alpha** — "Latest changes, may break."
- The picker is sticky once the user changes it. Auto-detection only
  fires on first launch.
- Switching to a *less risky* channel: an inline note appears below
  the picker — "Your current build is alpha.5; you'll stay on it until
  stable 2.0.0 is older." See Open Questions for the "downgrade now"
  prompt.
- Switching to a *more risky* channel takes effect on next check; no
  prompt.

## Privacy

- No new network IO. The polling endpoint changes from
  `releases/latest` to `releases?per_page=20` — same host, same auth
  story, same rate-limit budget.
- The channel selection is local-only (`UserDefaults`). It is never
  sent in any request: the User-Agent header continues to identify
  only the running build's version.
- No analytics on which channel users picked, ever.

## Implementation order

1. **`Channel` enum + tag parser + extended `ReleaseInfo`** with unit
   tests covering the `2.0.0 > 2.0.0-alpha.5` semver case the current
   comparator gets wrong.
2. **Switch `UpdateChecker` to the list endpoint** and add
   `latestForChannel(_:)`. Migrate `checkForUpdate` to take a
   `Channel` parameter (default `.alpha` for now).
3. **Settings → About: channel picker** + persistence + wire to the
   running `UpdateChecker`.
4. **Brew cask reorganisation** — separate PR touching `Casks/`. Adds
   `openquack-alpha.rb`; does not yet swap `openquack` (waits on
   stable tag).
5. **Sparkle integration** — deferred, lands with SPEC-011 Phase C.

## Open questions

- **"Downgrade now" prompt.** When a user switches Alpha → Stable and
  a stable build older than their current alpha exists, do we offer a
  side-grade install prompt? Lean **no for v1** — surface the gap as
  a passive note, let the user uninstall/reinstall manually. Adding a
  proper "install older version" UI is out of scope until Sparkle.
- **0.x pre-releases.** If we ever pre-release a `0.x` line, do we
  reuse `alpha`/`beta` or introduce `dev`? Lean reuse — semver suffix
  semantics don't depend on the major version.
- **Default channel for fresh installs once stable exists.** Lean
  **stable** — opt-in to alpha is the safer posture even though the
  current pre-1.0 default is alpha. The `Bundle.main` channel
  detection still wins on first launch, so a user who downloads the
  alpha DMG defaults to alpha; a stable-cask user defaults to stable.
- **Auto vs. user override.** If a user explicitly picks `stable` and
  later sideloads an alpha DMG over the brew install, whose preference
  wins on next launch? Lean: **the running build's channel resets the
  picker** — installing an alpha is a strong signal the user wants
  that channel, regardless of stale settings. Reversible from
  Settings.

## References

- SPEC-011 — update flow; this spec extends its pipeline (channel
  filtering on top of the existing in-app banner) and resolves its
  `// SPEC-??` semver TODO.
- `Sources/OpenQuackKit/Updates/UpdateChecker.swift` — the `latest()`
  / `checkForUpdate(currentVersion:)` / `isNewer(_:_:)` surfaces this
  spec amends.
- `Sources/OpenQuackKit/Updates/InstallMethod.swift` — unchanged;
  channel selection is orthogonal to install method, both feed the
  banner.
- `Casks/openquack.rb` — the cask to fork into channel-named
  variants.
- Sparkle channel docs: https://sparkle-project.org/documentation/channels/
- semver §11 (precedence rules): https://semver.org/#spec-item-11
