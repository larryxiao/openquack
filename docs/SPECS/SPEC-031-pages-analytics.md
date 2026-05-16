# SPEC-031 — Privacy-respecting visitor analytics for Pages landing

**Status:** draft (Adoption focus)
**Tracks:** Adoption focus band (`docs/ROADMAP.md`)
**Related:** [[SPEC-027]] (landing-page polish), [[SPEC-032]] (install count from appcast)

---

## Problem statement

The Pages landing at `https://larryxiao.github.io/openquack/` is now the
canonical surface for first-impression discovery — it's where every awesome-
list backlink, DM, and newsletter pitch eventually points. We have **zero
visibility** into who lands there, how many, from where, or which sections
they read. GitHub Insights gives a 14-day repo-view window with a top-10
referrer list, but Pages is treated as a separate surface and only the
`/larryxiao/openquack` repo views show up — not the Pages site itself.

Without analytics on Pages, we can't:

- Distinguish "people who looked at the GitHub repo" from "people who hit
  the actual landing page from a newsletter / Reddit / Twitter post."
- Measure whether the README FAQ section is actually being read.
- Tell which inbound channels (Reddit thread, Marco DM, Console.dev
  feature) are converting into clicks.
- Establish a baseline for the user-count metric beyond GitHub's
  unique-clone and DMG-download proxies.

## Goal

- A privacy-respecting analytics script embedded in `docs/index.md` (and
  any future Pages-served HTML) that captures:
  - Total + unique page views per URL
  - Top referrers (Reddit / Twitter / direct / etc.)
  - Top countries
  - Top entry pages
- Zero cookies, zero PII, honors Do-Not-Track. No analytics SDK is added
  to the macOS app itself — this is Pages-side only.
- Setup: ≤ 15 minutes total (account creation + paste-script + PR-merge).
- Free hosting (no credit card required for the indefinite future).

## Non-goals

- **App-side telemetry.** The macOS app's no-telemetry contract is
  unchanged. This SPEC is strictly about the marketing/docs surface.
- **Per-user identification.** Sessions / cohorts / funnels are out of
  scope. We want aggregate counts only.
- **Self-hosted analytics infrastructure.** Operational overhead
  outweighs the gain at our scale; use a hosted service.
- **Replacing GitHub Insights.** Insights still gives clone counts +
  release downloads + traffic-referrers for the repo itself; this SPEC
  complements it for the Pages surface.

---

## Technical approach

### Provider recommendation: GoatCounter

`GoatCounter` is the highest-fit option:

- Open source (MIT), free hosted tier up to 100,000 pageviews/month
  (we'll be three orders of magnitude under that for years).
- No cookies, no localStorage, no fingerprinting. Counts unique visits
  via a daily-salted hash of (IP + User-Agent) computed server-side; the
  raw IP is never written to disk.
- One-line embed: `<script data-goatcounter="https://<code>.goatcounter.com/count"
  async src="//gc.zgo.at/count.js"></script>`
- Honors Do-Not-Track by default.
- Public dashboard option (we can make the analytics public — fits
  OpenQuack's transparency ethos).
- Service is run by Martin Tournoij; sustainability path: paid tier for
  pro users.

### Alternatives considered

| Option | Why not picked |
|---|---|
| Plausible | Excellent product, but the hosted plan is $9/mo minimum. Self-host requires a VPS we don't have. |
| Umami | Self-host only. Operational overhead. |
| Cloudflare Web Analytics | Free, no cookies, but requires routing the Pages site through Cloudflare's edge (which means moving DNS to Cloudflare — a separate decision the team may not want to make for the docs site). |
| Fathom Lite | Self-host only. |
| Google Analytics | Cookies, PII, off-charter for OpenQuack's positioning. Reject. |

### Setup steps

The implementing PR should:

1. **Create the GoatCounter account.** This is Larry's manual action
   (signup at goatcounter.com with the desired site code, e.g.
   `openquack`). The PR doesn't unblock until Larry has the code.
2. **Add the script tag** to `docs/index.md` front matter via a Jekyll
   `_includes/analytics.html` partial, *or* directly in the front-matter
   `head` if Jekyll's seo-tag plugin supports it. The script must
   be conditional on a `analytics_enabled` flag in `_config.yml` so the
   site code doesn't end up in repo history.
3. **Document the dashboard URL** in `docs/index.md` footer
   ("transparency: visitor count is public at <dashboard URL>") and in
   `gtm/SESSION-HANDOVER-2026-05-13.md` (so we know where to look).
4. **Add a Privacy line** to the FAQ in both `README.md` and
   `docs/index.md`: *"Does the project site track visitors? Yes — we use
   GoatCounter, a privacy-respecting analytics service that doesn't use
   cookies or fingerprinting. Visit counts are public at [dashboard]."*

### Privacy contract considerations

The app's privacy promise — *"no audio, text, or telemetry leaves your
Mac"* — is about the application binary. The Pages site is HTML served
by GitHub; visiting any web page involves network requests and standard
HTTP-level telemetry (IP, UA) at the server. GoatCounter aggregates and
discards before persistence. We are transparent about the choice (FAQ
entry above) so an audit reveals the practice immediately.

Reject any implementation that:

- Embeds analytics in the macOS binary
- Uses cookies or localStorage
- Sends data to a non-privacy-respecting service (GA, Mixpanel, Amplitude,
  Heap, Segment, etc.)
- Hides the analytics presence from the FAQ

---

## Verification / rollout

- After PR merges and Larry's site code is in `_config.yml`:
  visit `larryxiao.github.io/openquack/` from a clean browser, then
  refresh the GoatCounter dashboard — count should increment.
- Verify the `Do-Not-Track` flag is honored: enable DNT in browser,
  visit, confirm no increment.
- Confirm zero cookies in browser dev-tools after visiting.

## PR shape

| PR | Title | SPEC cite | Effort |
|---|---|---|---|
| this | `docs(SPEC-031): privacy-respecting Pages analytics` | SPEC-031 | XS |
| PR-A | `feat(docs): GoatCounter snippet via _config.yml flag` | SPEC-031 | XS — adds `_config.yml` + `_includes/analytics.html` + FAQ line in both READMEs |

PR-A is gated only on Larry creating the GoatCounter site (1-min signup).
The PR can be opened with the snippet wired but `analytics_enabled: false`
in `_config.yml`; Larry flips the flag + adds his site code after merge.

## Open questions

- **Public dashboard or private?** GoatCounter supports both. Public is
  on-charter for transparency; private is the conventional choice. Default
  to **public** unless Larry says otherwise — visitor counts are not
  sensitive and public dashboards have been a positive signal for indie
  projects (e.g. `usefathom.com` itself).
- **Should the same script also load on `README.md` rendered on GitHub?**
  No — GitHub strips script tags from rendered markdown. The script only
  fires on the Pages site.
