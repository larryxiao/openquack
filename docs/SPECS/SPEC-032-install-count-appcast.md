# SPEC-032 — Active-install count via Sparkle appcast hits

**Status:** draft (Adoption focus)
**Tracks:** Adoption focus band (`docs/ROADMAP.md`)
**Depends on:** [[SPEC-026]] (Sparkle auto-update) — implementation
**Related:** [[SPEC-031]] (Pages visitor analytics)

---

## Problem statement

OpenQuack today has **no measurement of active installs**. The available
proxies — GitHub release downloads (49 lifetime), unique clone IPs (329 in
14d, mixed with CI scrapers and brew taps), repo views (72/14d) — give an
order-of-magnitude estimate (100–300 users worldwide) but not a real
number. The privacy contract correctly rules out any in-app telemetry, so
the only ethical measurement path is **passive**: count something the app
*already does* over the network for a functional reason.

When SPEC-026 ships, every install will periodically request the Sparkle
`appcast.xml` feed to check for new versions. That request is functionally
necessary (otherwise auto-update doesn't work). If we host the appcast on
a surface that aggregates request counts — without logging IPs, UAs, or
identifiers — we get a real active-install count as a side effect.

GitHub Pages, where we'd otherwise host the appcast, exposes **no access
logs** to repo owners. That's the missing piece. This SPEC defines where
to host the appcast and how to count hits ethically.

## Goal

- A weekly + daily active-install count visible to the maintainer.
- The number reflects **active** installs (apps actually launching and
  checking for updates), not lifetime downloads.
- The mechanism is server-side aggregation only — no per-install
  identifier, no IP logging, no cookie equivalent.
- The choice is reversible: if the host turns out to be wrong, the
  appcast URL can be moved with a new release that includes the new
  feed URL.

## Non-goals

- **Per-user identification or session tracking.** Aggregate counts only.
- **Real-time dashboards.** Daily or weekly granularity is sufficient.
- **Migrating existing GitHub-hosted appcast URLs.** Since SPEC-026 hasn't
  shipped yet, there's no migration burden — the first appcast URL goes
  straight to the chosen host.
- **Crash reporting / usage analytics.** Out of scope. The hit-count is
  the *only* signal we extract from the appcast request.

---

## Technical approach

### Host recommendation: Cloudflare Workers

A Cloudflare Worker serves `appcast.xml` and writes an aggregated hit
count to Workers KV (or Workers Analytics Engine). Free tier covers
~100k requests/day which is two orders of magnitude beyond our needs for
years.

Why Cloudflare Workers:

- Free tier is comfortable: 100k requests/day, no credit card.
- Workers KV can store a daily counter keyed by `YYYY-MM-DD`.
- Workers Analytics Engine (if we want richer breakdowns) provides
  histograms keyed by app version + OS version + country — useful for
  measuring upgrade adoption — *without* writing IP or UA to disk.
- Custom domain support. The appcast URL ends up as
  `https://updates.openquack.app/appcast.xml` (or `openquack.workers.dev`
  if we delay the domain).
- Edge-cached static response — no cold-start latency for the actual XML.

### What gets logged

Minimum (PR-A):

- Daily counter: `INCR appcast_hits_<YYYY-MM-DD>` per request.
- That's it. No IP, no UA, no app version, no OS version.

Optional richer breakdown (PR-B, only if PR-A's number proves useful):

- Parse the Sparkle User-Agent (`OpenQuack/2.0.0-beta.1 Sparkle/2.x`) and
  the system version it includes. Increment per-(app-version,
  os-major-version) counters. **Still no IPs, no fingerprintable
  identifier.**
- Use Cloudflare's geolocation header (`cf-ipcountry`) to aggregate by
  country. Country is coarse enough to not be PII.

What we will *never* log:

- IP address
- Exact User-Agent string (only the parsed components)
- Any cookie, fingerprint, install UUID
- Request timestamp at sub-day granularity (it's daily-bucketed)

### App-side change (in Sparkle integration, SPEC-026)

Sparkle's default `User-Agent` already includes app + system version
sufficient for PR-B. **No app-side change is required for this SPEC** —
the Worker just inspects what Sparkle naturally sends.

### Appcast content

Independent concern. The Worker serves a static appcast.xml that the
build pipeline updates. Source of truth: a file in `docs/appcast.xml`
that the Worker reads from the GitHub Raw URL (or that's pushed to the
Worker via wrangler). Either way, no extra steps for the release flow
beyond what SPEC-026 already defines.

### Domain / DNS

- **Without `openquack.app`** (current state): `appcast.openquack.workers.dev`
  works. Looks slightly less polished but functions identically.
- **With `openquack.app`** (post P-063 in tracker): `updates.openquack.app`
  via Cloudflare DNS + Workers custom domain. Optional, not blocking.

### Privacy contract considerations

Same framing as [[SPEC-031]]. The macOS app's no-telemetry promise is
about the binary not sending user data anywhere. The appcast request is a
**functional update check**, not telemetry. The Worker aggregates request
counts in a way that's structurally incapable of identifying a user. The
distinction will be documented in `docs/VISION.md#privacy-contract`:

> *Update checks. When you have auto-update enabled (Settings → Updates),
> OpenQuack periodically asks our update server whether a new version
> exists. The request reaches our server; the server counts it as a
> generic "ping" — no IP, no user agent, no identifier is recorded.
> Disable auto-update if you want zero outbound network requests after
> first run.*

The opt-out path matters and must be a real toggle (already specified in
SPEC-026's Settings → Updates pane).

---

## Verification / rollout

- After PR-A merges and the Worker is deployed: install a beta build on a
  fresh Mac, let it run for the Sparkle check interval (default ~24h or
  manual "Check for Updates"), verify the daily counter incremented.
- Disable auto-update in Settings, run the app, verify no increment.
- After 7 days of real installs, eyeball the count vs the GitHub clone
  number to triangulate "what fraction of clones became persistent
  installs."

## PR shape

| PR | Title | SPEC cite | Effort |
|---|---|---|---|
| this | `docs(SPEC-032): install count via appcast hits` | SPEC-032 | XS |
| PR-A | `feat(infra): Cloudflare Worker serving appcast.xml with daily counter` | SPEC-032 | S — Wrangler config + Worker script + KV namespace + docs |
| PR-B | `feat(infra): version + OS breakdown in appcast counter` | SPEC-032 | S — optional, only if PR-A's number proves useful |
| PR-C | `docs(VISION): document the update-check ping in the privacy contract` | SPEC-032 | XS — explicit user-facing disclosure |

PR-A is gated on:

1. Larry has a Cloudflare account (free signup).
2. SPEC-026 implementation has landed (or at least has decided on the
   appcast URL shape). If SPEC-026 ships before this SPEC's PR-A, the
   initial appcast URL goes to a placeholder hostname and PR-A updates
   it — adds one release-cycle of friction. Better to land in this
   order: SPEC-026 ships → PR-A here → first signed/notarised release
   points at the Worker URL from day one.

PR-C should land same-week as PR-A so the privacy disclosure ships
together with the first ping-emitting build.

## Open questions

- **Cloudflare account ownership?** Personal account is fine for now;
  the Worker config is portable. Migration to a project-owned account
  later is a simple key transfer.
- **KV vs Analytics Engine?** KV is simpler and sufficient for the daily
  counter. Analytics Engine is needed for the version × OS breakdown
  (PR-B). Recommendation: KV in PR-A, AE in PR-B only if we want the
  breakdown.
- **What about Homebrew brew analytics?** Tap-based casks (current
  state) don't show up in mainline brew analytics. If we eventually
  submit to `homebrew/cask`, that becomes an independent data source
  not in conflict with this SPEC.
- **What about pre-Sparkle installs?** Users on v2.0.0-alpha.10 and
  earlier have no Sparkle. They'll auto-upgrade via the cask (`brew
  upgrade --cask openquack`) when SPEC-026 ships, at which point they
  join the count. There's no migration step.
