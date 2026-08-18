# SPEC-045 — Cloudflare Access auth for remote transcription

## Goal

Let a user whose remote endpoint (SPEC-044) sits behind Cloudflare Access authenticate with a browser SSO login instead of a pasted key: fill the endpoint URL, click *Sign in*, complete the company IdP flow in the browser — no credential to obtain, store, or rotate by hand. The auth layer stays organisation-agnostic: the only parameter is the URL the user typed; the code never knows (or names) which IdP sits behind it.

## Background

SPEC-044 shipped `.none` / `.bearer` / `.header(name:)` — enough for hosted APIs and simple gateways, but structurally unable to reach an Access-protected endpoint: Access accepts only a browser-SSO JWT or an admin-issued service token (two headers), neither of which a user can express as a single pasted key. For teams whose STT gateway lives behind Access, SSO login is therefore the *only* practical path, not a convenience.

`RemoteAuth` was designed as a closed enum precisely so this lands as an added case with the transport untouched.

## Mechanism

### Auth case and token flow

```swift
public enum RemoteAuth {          // existing cases unchanged
    case cloudflareAccess         // ← new; app URL = the endpoint's origin
}
```

The browser round-trip is delegated to the `cloudflared` CLI (user-installed, e.g. `brew install cloudflared`) — no OAuth implementation of our own:

```
cloudflared access login  <origin>   # opens the browser, blocks until the IdP flow completes
cloudflared access token --app <origin>   # prints the freshly minted JWT
```

`CloudflareAccessClient` (OpenQuackKit/Auth) drives both via `Process` with an argument array (no shell interpolation), a timeout, and shape validation on the result (three dot-separated base64url segments). The JWT then goes into the existing `CredentialStore` **as the endpoint host's secret** — SPEC-044's host-keying and "edited URL can't carry the old credential" invariant are inherited, not re-implemented.

At request time `RemoteEngine.attachAuth` adds one branch: read the host's secret, decode its `exp`, and attach `cf-access-token: <jwt>` — or refuse.

### JWT lifecycle rules

1. **An expired (or expiring within 60 s) JWT is never sent.** Access treats an expired token as a failed authentication, which can be worse than sending none. Expired → the request fails fast with "Session expired — sign in again in Settings".
2. **No browser at dictation time.** Sign-in is always a deliberate action in Settings; a hotkey press never launches a browser. A dictation that finds no valid JWT errors out like any other misconfiguration (SPEC-044: no silent local fallback).
3. **Sign out = delete the host's Keychain item.** Nothing else to clean up on our side (`cloudflared`'s own `~/.cloudflared` cache is its business and is noted in the UI copy).

### Settings UI

The SPEC-044 *Authentication* picker gains `Company SSO (Cloudflare Access)`. Selecting it replaces the API-key field with a status row driven by a four-state machine:

- **cloudflared missing** — explanatory hint (`brew install cloudflared`), sign-in disabled; detection (`which cloudflared` + common install paths) runs when the pane appears, so the user is told *before* clicking, not failed *after*.
- **Signed out** — `Sign in with your browser…` button; runs login → token → Keychain, with a progress state while the browser flow is pending.
- **Signed in** — `✓ Signed in · expires <relative time>` + *Sign out*.
- **Expired** — `Session expired` + *Sign in again*.

The Access "app URL" is not a separate field: it defaults to the endpoint URL's origin, which is what Access binds to in practice. (An advanced override can be added later if a real deployment needs it.)

## Privacy impact

Strictly narrower than a pasted key, and the SPEC-044 fences all still apply (opt-in, user-typed destination, overlay indicator, Keychain-only, host-keyed, redirects refused):

- The IdP login happens in the user's browser on the IdP's pages; OpenQuack and `cloudflared` never see the password or MFA.
- What OpenQuack holds afterwards is a short-lived JWT scoped to that one Access application — revocable centrally by the org's admin, unusable against anything else in the user's account.
- Trust surface added: the `cloudflared` binary itself (user-installed via their own package manager, never bundled) and its on-disk token cache in `~/.cloudflared` (outside our control; our copy lives in the Keychain).
- The JWT is never logged; diagnostics record the auth *kind* only.

## Acceptance criteria

- [ ] `RemoteAuth.cloudflareAccess` attaches `cf-access-token` with a valid stored JWT; existing `.none`/`.bearer`/`.header` behaviour unchanged (unit tests).
- [ ] An expired or near-expiry (≤ 60 s) JWT is refused **before** any network IO, with a sign-in-again error; a missing JWT likewise (unit tests, using locally constructed unsigned JWTs).
- [ ] JWT `exp` parsing handles base64url padding variants and rejects malformed tokens (unit test).
- [ ] `cloudflared` absent → Settings shows the install hint and sign-in is disabled; present → sign-in runs login + token and the row flips to signed-in with an expiry (manual).
- [ ] Sign out removes the host's Keychain item and the row returns to signed-out (manual).
- [ ] Dictation with an expired session shows the overlay error and never opens a browser (manual).
- [ ] End-to-end against a real Access-protected endpoint: sign in via company IdP, dictate, transcript pastes; after token expiry, dictation fails with the sign-in-again message until re-login (manual).

## Out of scope

- **Service tokens** (`CF-Access-Client-Id`/`-Secret` pair) — headless/CLI concern; needs a two-header auth case and admin-issued credentials. Follow-up when CLI remote support lands.
- **Native `ASWebAuthenticationSession` flow** (removing the `cloudflared` dependency) — requires reimplementing Access's login URL construction and callback server; revisit if the CLI dependency proves to be real friction.
- **Automatic token refresh / background re-login** — deliberate; sign-in stays a user action.
- **Custom Access app URLs** differing from the endpoint origin.
