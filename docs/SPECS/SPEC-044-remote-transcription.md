# SPEC-044 — Remote transcription endpoint (bring your own)

## Goal

Let a user who wants a bigger model than their Mac can run point transcription at an OpenAI-compatible HTTP endpoint — any endpoint, any provider — without weakening the default local posture. Local stays the default; the remote path is explicitly opt-in, visibly indicated while active, and carries no vendor names in code.

## Background

Transcription today is 100 % on-device (WhisperKit; Lightning in bench). That is the right default and the product's identity, but two real user groups want more:

- users whose quality ceiling is the local model (e.g. heavy Chinese dictation, where Whisper is the bottleneck), who already run or rent a stronger STT endpoint;
- users with a company-internal gateway in front of a speech model.

The agent layer already made exactly this trade once: network use is allowed, but only user-configured, never default (VISION.md privacy contract, clauses 3–4). This spec extends the same carve-out to transcription.

Approval note: this change touches two AGENTS.md hard-rule areas (a network call in the dictation path; the privacy contract). Both were explicitly approved by the maintainer commissioning this spec.

## Mechanism

### Data model

```swift
public struct RemoteProfile: Sendable, Equatable {
    var baseURL: URL          // e.g. https://api.openai.com/v1
    var model: String         // e.g. whisper-1; sent only if non-empty
    var auth: RemoteAuth
}

public enum RemoteAuth: Sendable, Equatable {
    case none                 // local gateways, whisper.cpp server
    case bearer               // Authorization: Bearer <secret>
    case header(name: String) // <name>: <secret> — corporate gateways
}
```

No secret lives in the profile or in UserDefaults. Secrets go in the Keychain via `CredentialStore`, **keyed by endpoint host** (`KeychainCredentialStore`, one generic-password item per host). Keying by host is the security invariant: an engine can only ever attach the credential saved for the host the request targets, so editing the URL can never leak the old host's key to a new one.

### Engine

`RemoteEngine` implements the existing `TranscriptionEngine` protocol (no protocol changes). Per request:

1. Re-encode the recording to 16 kHz mono 16-bit WAV (`AudioResampler`, AVFoundation only — the recorder writes device-native rate, often 48 kHz stereo, which is ~6× the upload weight for zero quality gain). Above `compressAboveBytes` (700 KB, ~22 s) the WAV is further encoded to 32 kbps mono AAC/m4a — ~7× smaller, so long dictations stay inside gateway body caps and upload faster. Measured against a live endpoint, WAV and AAC transcripts matched on clean, noisy, and Chinese speech. Encoding runs through `AVAssetWriter` (`AVAudioFile` cannot write compressed formats), and any encoder failure falls back to the WAV rather than failing the dictation.
2. `POST {base}/audio/transcriptions` (path not appended if the user already pasted the full path), multipart: `file`, `model`, optional `language`, `response_format=json`.
3. Parse `{"text": …}`; plain-text bodies accepted as a fallback for non-conforming servers.

Transport rules: HTTPS required (plain HTTP allowed for loopback only, for local whisper.cpp/Ollama-style servers); HTTP redirects refused — audio and credential go only to the configured host, never wherever a 3xx points; URLs with embedded `user:pass@` rejected (and auto-stripped in Settings) so no secret can ride into UserDefaults; ephemeral `URLSession` so no response ever lands in the on-disk URL cache; 60 s request timeout. Requests never identify the app to the endpoint: the `User-Agent` is user-configurable (`remoteUserAgent`, folded to one header line; a neutral default when empty — the CFNetwork default would embed the bundle name) and the multipart boundary is app-neutral. Errors surface through the existing `EngineError` path — a misconfigured remote **errors**, it never silently falls back to local.

`EngineKind` is untouched: the app constructs `RemoteEngine` directly (as it already does `WhisperKitEngine`), because `makeEngine(model:)` cannot carry profile config. CLI/bench remote support is out of scope.

### App integration

- New Settings rows under Speech-to-text: a `Transcription` picker (`On this Mac` / `Remote endpoint (experimental)`), and when remote: endpoint URL, model, user agent, auth method, and a Keychain-backed API-key field tied to the URL's host. UserDefaults keys: `transcriptionBackend`, `remoteEndpoint`, `remoteModel`, `remoteUserAgent`, `remoteAuthMethod`, `remoteAuthHeaderName`.
- Dictation flow: the backend is **snapshotted at recording start**, so the destination the overlay disclosed is the destination used at stop (a Settings change applies to the next dictation). When remote is selected the offline file path is always used, the local streaming transcriber is not fed (no wasted local compute), the local warm-engine guard is skipped, and diagnostics record `path=remote`; failures log a diagnostics event too (backend kind + error, never transcript).
- Launch: with remote selected, the local model warm-up (and its potential multi-GB download) is skipped and the app goes straight to idle; switching back to local in Settings warms lazily, as does history recovery.
- History rows record the backend (`modelID` becomes `"<model> @ <host>"` for remote runs). Pending-recovery re-transcription stays local.
- Agent-kickoff recordings follow the same transcription backend as dictation.

### Privacy indicator

While a remote profile is active, the recording overlay must never claim locality:

- an amber `globe · remote` chip is shown during recording and transcribing (same treatment as the SPEC-031 kickoff chip, which is the contract's existing network indicator); a kickoff recording with a remote backend shows **both** chips — each network hop gets disclosed;
- the transcribing subline reads `via <host>` instead of `On your Mac` (polishing keeps `On your Mac` — polish stays local);
- the menu-bar popover follows suit (`Sending to <host>…` / `transcribing via <host>` instead of the local claims);
- the polish debug log (which embeds raw + polished text) is suppressed for remote dictations.

VISION.md privacy-contract clause 1 and README wording change from unconditional to default-scoped in the same PR; the sentence pattern follows the agent carve-out already in VISION.md.

## Privacy impact

This is the first feature that can send audio off-device, so the change is fenced:

- **Off by default.** The default build's dictation path performs no network IO; none of the new code runs unless the user selects the remote backend.
- **User-configured destination only.** No default endpoint, no vendor name in code; the destination is a URL the user typed.
- **Visible while active** (overlay chip + `via <host>` subline).
- **Secrets in Keychain only**, keyed by host; never in UserDefaults, logs, or history.
- **No transcript/audio logging** on the remote path; diagnostics log backend kind and timing only.

## Acceptance criteria

- [ ] Default build behaviour unchanged: with `transcriptionBackend` unset or `local`, no code in this spec executes on the dictation path (code review + existing tests green).
- [ ] `RemoteEngine` sends a well-formed OpenAI-compatible multipart request with bearer / custom-header / no auth (unit tests: request shape, auth headers, full-path URL not doubled).
- [ ] Credential is looked up strictly by request host; missing credential fails **before** any network IO (unit test).
- [ ] Non-HTTPS endpoints rejected except loopback; embedded `user:pass@` rejected; redirects refused without a second request (unit tests).
- [ ] Upload is 16 kHz mono WAV regardless of capture format (unit tests: resampler output format; multipart size bound).
- [ ] Non-2xx responses surface status + body detail as an `EngineError` (unit test).
- [ ] Overlay shows the remote chip and `via <host>` subline during a remote dictation, and `On your Mac` never appears while remote is active (manual: configure endpoint, dictate, observe overlay).
- [ ] History entry for a remote dictation shows `<model> @ <host>` (manual).
- [ ] Manual end-to-end: against a live OpenAI-compatible endpoint, hotkey → speak → paste lands the remote transcript; with a wrong key, dictation shows the HTTP 401 error and nothing is pasted.

## Out of scope

- **Cloudflare Access / SSO auth** (browser login → JWT, service tokens) — follow-up spec; `RemoteAuth` is a closed enum designed to grow cases without touching transport.
- **Ogg Opus upload encoding** — superseded by AAC/m4a above (also an OpenAI-accepted format, and encodable with no new dependency; macOS can only put Opus in a CAF container, so shipping `.ogg` would mean bundling libopus + libogg for a marginal size win).
- **Multiple profiles / per-app or per-language routing.**
- **CLI + bench remote support**, and bench methodology for network-dominated latency.
- **Automatic fallback to local on remote failure** — deliberate: silent fallback hides misconfiguration; revisit with real usage data.
- **Remote polish** — the polish layer could reuse `RemoteProfile`, but that is its own spec.
- **Translated README stubs** (`docs/i18n/*`) — machine-translated; the "nothing leaves" → "by default" sweep lands with the next translation refresh (English README, zh-CN README, docs site, VISION, and in-app copy are amended in this spec).
- **`detectedLanguage` from remote** (`verbose_json` is not universally supported; SPEC-035 normalisation falls back to system language).
