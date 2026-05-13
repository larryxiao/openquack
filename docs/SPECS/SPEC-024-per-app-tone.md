# SPEC-024 — Per-app tone profiles

**Status:** draft
**Tracks:** [#24](https://github.com/larryxiao/openquack/issues/24)
**Depends on:** [SPEC-007](SPEC-007-llm-polish.md) — the `TextPolishEngine`
protocol must land in code, not just spec-merged
**Effort:** M

Supersedes SPEC-007b's *"per-app polish profiles — defer to SPEC-008 / 009"*
note, and resolves SPEC-007's *"Custom system prompts — defer to M3+"*
open question.

---

## Problem statement

The same dictated phrase reads differently depending on the foreground app.
*"hey can you look at the build failure"* is fine in Slack and wrong in an
email to the team's principal engineer. Today every transcript runs
through the same Whisper prompt and the same polish prompt, so users either
pick a tone that's right for some apps and wrong for others, or they
manually toggle settings between dictations — which defeats the speed
advantage that made them install a voice-input tool.

---

## Goal

1. **Auto-detect the frontmost app's bundle ID at hotkey-fire time** and
   resolve it to a stored *tone profile* before transcription starts.
2. **Apply the profile to both stages of the pipeline**:
   - Whisper decoder — merge the profile's jargon hint into the existing
     custom-dictionary prompt seed.
   - Polish engine — pass the profile's system prompt as a per-call
     override into `TextPolishEngine.polish(...)`.
3. **Let the user edit mappings and define custom presets** from Settings
   without restarting the app.
4. **Fall back to a global default profile** when no rule matches the
   detected bundle ID (or detection fails).

---

## Data model

```swift
struct ToneProfile: Codable, Identifiable {
    let id: String              // "technical" | "formal" | "casual" | "neutral"
                                // or a UUID string for user-created presets
    let displayName: String
    let whisperPromptHint: String   // appended to DecodingOptions.prompt
    let polishSystemPrompt: String  // overrides default polish system prompt
    let isBuiltIn: Bool         // built-ins are read-only; clone-and-edit only
}

struct AppToneMapping: Codable, Identifiable {
    let id: UUID
    let bundleID: String        // "com.apple.Terminal"
    let profileID: String       // FK into ToneProfile.id
}
```

Built-in presets (`technical`, `formal`, `casual`, `neutral`) ship with
the app and are **read-only**. A user who wants to tweak one clones it
into a new `ToneProfile` with `isBuiltIn = false` and a fresh UUID. This
lets future versions ship prompt updates without overwriting user edits,
and keeps "Reset to default" meaningful.

The mapping FK references `profileID` by string, not by index, so renaming
a custom preset doesn't break its mappings.

### Storage

Mirror SPEC-022 §2.4's persistence convention. Two JSON files under
`~/Library/Application Support/OpenQuack/`:

- `tone_profiles.json` — user-created custom presets only (built-ins live
  in the app bundle, surfaced at read time).
- `app_tone_mappings.json` — bundle-ID → profile-ID list, plus a
  `defaultProfileID` field for the "no rule matches" fallback.

Splitting them means renaming a preset doesn't rewrite the mapping file,
and a busy mapping-edit session doesn't churn the presets file. Both load
at app start; writes are debounced and atomic (write-to-temp → rename) per
the SPEC-022 pattern.

---

## Detection

`NSWorkspace.shared.frontmostApplication?.bundleIdentifier` returns the
foreground app's bundle ID. No entitlement, no Accessibility prompt — the
read is available to every macOS app.

**Snapshot at recording start, not at transcription start.** The user may
alt-tab away mid-recording (to check a URL, to read a chat message); their
*intent* was captured when the hotkey fired. The bundle ID is read inside
the hotkey-down handler, stashed onto the recording session, and consumed
once transcription begins.

**Edge cases:**

- **Full-screen / wrapper bundle IDs.** Browsers, Electron apps, and some
  game launchers report a parent process bundle ID that doesn't match the
  visible window. v1 treats the reported ID as authoritative — page-URL
  introspection is out of scope (§10).
- **Secondary windows.** A floating panel or HUD reports its host app's
  bundle ID; that's the desired behaviour.
- **Detection fails** (`nil` return, no frontmost app). Fall back to the
  user's `defaultProfileID`. The recording overlay surfaces a one-line
  caption — *"Using default tone — couldn't detect active app"* — so the
  user understands why a familiar app got the generic profile.

---

## Application surface

Three integration points: two in `OpenQuackKit`, one in pipeline glue.

### 1. `WhisperKitEngine.transcribe(...)` — new `whisperPromptHint`

Add a third parameter to the existing extended `transcribe` overload:

```swift
public func transcribe(
    audioFile url: URL,
    language: String?,
    customWords: String?,
    whisperPromptHint: String? = nil  // NEW
) async throws -> EngineTranscription
```

The hint is **appended** to the custom-words string with a sentence-
boundary separator (`". "`) before tokenisation. Order matters: user's
custom dictionary first, then profile hint. When the combined string
exceeds Whisper's ~224-token prompt cap, the profile hint is truncated
first — the user's explicitly-typed proper nouns outrank a profile's
jargon list.

### 2. `TextPolishEngine` — amend `PolishContext`

SPEC-007 already defines `PolishContext.foregroundApp: String?` as "best-
effort, may be nil." This SPEC promotes that field from best-effort to
load-bearing (always populated when a mapping resolved), and adds one new
per-call channel:

```swift
public struct PolishContext: Sendable {
    public let language: String?
    public let foregroundApp: String?       // now always populated when known
    public let timestamp: Date
    public let systemPromptOverride: String?  // NEW — wins over engine default
}
```

The engine consults `systemPromptOverride` ahead of its built-in template
(SPEC-007 §"Prompt template"). When `nil`, behaviour is unchanged.

**Blocks on SPEC-007 landing in code.** The protocol and struct don't
exist yet; this SPEC's PR-C is gated on SPEC-007 PR-A merging.

### 3. Pipeline glue (`AppDelegate.stopAndTranscribe`)

Between recording-stop and transcribe-start:

```
bundleID (snapshotted at recording start)
  → mappingStore.profile(forBundleID:) ?? mappingStore.defaultProfile
  → pass profile.whisperPromptHint into transcribe(...)
  → pass profile.polishSystemPrompt into PolishContext.systemPromptOverride
```

If no mapping resolves and there is no default set, the engines see `nil`
for both — i.e. pre-SPEC-024 behaviour, no regression.

---

## Settings UI

The natural home is the existing **Settings → Polish** pane (SPEC-007b),
not a new pane: per-app *tone* is conceptually a polish-prompt variant
plus a Whisper-prompt nudge, and keeping related controls together matches
how users will reason about them. Final placement should be revisited
after SPEC-007b's layout settles; the working assumption is a new
sub-section below the existing mode picker.

### Sub-section A — "Per-app profiles"

A list of mappings, each row showing the app's localised name + icon
(resolved via `NSWorkspace.shared.icon(forFile:)` / `Bundle.localizedName`)
and a profile picker. When the bundle ID does not resolve to an installed
app, the raw bundle ID renders instead so the user can still identify the
row.

Adding a row opens an `NSOpenPanel` filtered to `.app` bundles — a Mac-
native pattern users recognise. Below the list, a *Default profile*
picker controls the fallback. Defaults to `neutral`.

### Sub-section B — "Presets"

Lists all `ToneProfile`s. Built-ins are read-only with an inline "Clone
to edit" button. User-created presets expose: display name field,
`whisperPromptHint` text area, `polishSystemPrompt` text area, delete
button.

### Default mappings shipped out-of-the-box

Seeded on first run if `app_tone_mappings.json` is absent — never
overwriting a returning user's edits:

| Bundle ID | Profile |
|---|---|
| `com.apple.Terminal`, `com.googlecode.iterm2`, `com.mitchellh.ghostty` | technical |
| `com.apple.mail`, `com.microsoft.Outlook` | formal |
| `com.tinyspeck.slackmacgap`, `com.apple.MobileSMS` | casual |
| Browser bundles (`com.apple.Safari`, `com.google.Chrome`, `org.mozilla.firefox`, `com.brave.Browser`, `company.thebrowser.Browser`) | neutral |

Browsers default to `neutral` because the real signal is the page URL,
not the bundle ID — and URL introspection is out of scope (§10).

---

## Privacy & telemetry

No telemetry. Mappings and presets stay on disk in App Support, never
leave the Mac. Bundle-ID detection is read-only — it fires only inside
the hotkey-down handler and reads only the foreground app's identifier,
not its contents — but it deserves a one-sentence explanation in the
Settings sub-section header:

> *OpenQuack reads which app is in front when you press the hotkey, so it
> can pick the right tone. This never leaves your Mac.*

---

## Out of scope

- **Page-URL detection inside browsers** — would need a browser extension
  or per-browser AppleScript scraping. Tracked separately; browser
  bundles default to `neutral` until that lands.
- **Auto-learning profiles from user corrections.** SPEC-022 handles
  dictionary auto-learn from corrections; tone auto-learn is strictly
  bigger (tone is structural, not lexical). Defer.
- **Cross-device sync** of profiles or mappings. Local-only by
  construction, matching every other OpenQuack state file.
- **Whisper-side language switching driven by app** ("Mandarin in
  WeChat"). That's a language-selection SPEC, not a tone SPEC — the
  `whisperPromptHint` channel is for jargon priming, not for forcing
  `DecodingOptions.language`. Called out here so reviewers don't confuse
  the two threads.
- **Window-level granularity** ("Slack DM" vs "Slack channel"). v1 is
  app-level; see open question below.

---

## PR shape

| PR | Title | Effort | Blocked on |
|---|---|---|---|
| this | `docs(SPEC-024): per-app tone profiles` | XS | — |
| PR-A | `feat(tone): ToneProfile + AppToneMapping store, defaults seeding` | S | this |
| PR-B | `feat(transcription): WhisperKitEngine whisperPromptHint + pipeline glue` | S | PR-A |
| PR-C | `feat(polish): PolishContext.systemPromptOverride + pipeline glue` | S | PR-A, SPEC-007 PR-A in code |
| PR-D | `feat(settings): per-app profiles + presets UI in Polish pane` | M | PR-A |

PR-A is a pure-data change with unit tests (load / save / FK resolution /
default seeding) and no UI — it can land while SPEC-007 is still in
flight. PR-B unblocks the Whisper-side benefit immediately. PR-C waits on
SPEC-007. PR-D can land any time after PR-A but is most useful once PR-B
or PR-C is in.

---

## Open questions

- **Whisper prompt hint — append vs replace?** v1 appends, with the
  user's custom dictionary winning when the combined string overflows
  Whisper's ~224-token cap. The alternative (replace) would trade the
  user's explicit terms for a profile's generic jargon list and is
  rejected. Worth re-evaluating once we have per-language token-count
  data for the seeded preset hints.
- **Window-level vs app-level granularity.** v1 is strictly app-level.
  A power user wanting *"casual in Slack DMs, formal in #leadership"*
  has no path. The wedge would be `kAXFocusedWindowAttribute` + window-
  title regex. Defer until a real user asks twice.
- **Multi-app workflow within one recording.** User starts dictation
  with Terminal frontmost, alt-tabs to Mail mid-sentence, releases the
  hotkey while Mail is forward. v1 uses the *recording-start* snapshot
  (Terminal, technical). Alternative: re-read at recording-stop, or
  take the more recent of the two. The recording-start choice is
  documented to the user via the overlay caption (§5); monitor reports
  before reconsidering.
- **Built-in preset prompt content.** PR-A ships the four built-in
  presets with placeholder `polishSystemPrompt` strings derived from
  SPEC-007's prompt template. Final wording should be finalised
  alongside SPEC-007's bench (SPEC-007a tier defaults) so presets are
  tuned against the same eval set as the engine default. Built-ins are
  functional but conservative until then.
