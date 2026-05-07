# SPEC-019 — App localisation (i18n)

**Status:** draft (M3 — community-translation foundation)
**Owner:** `OpenQuackApp/Localizable.xcstrings` (new) + `OpenQuackKit`
**Last updated:** 2026-05-07

## Goal

OpenQuack's UI is English-only today. The app already transcribes 99
Whisper languages, and we have organic non-English signal (Chinese
audience trickling from awesome-mac). Localised UI lets users dictate
in their language **and** read the menus, settings, and onboarding in
their language — closing the loop.

This spec ships the **infrastructure**, not the translations. Empty
`.xcstrings` files for each target locale are the deliverable; the
actual translations come from community contributors via PR (per the
`docs/CONTRIBUTING.md` translation flow and the `README.zh-CN.md` /
`README.ja.md` / etc. precedent).

## Why this is M3 priority

- The international-venues research (2026-05-07) found that
  jaywcjlove/awesome-mac auto-syndicates our entry to its
  README-zh / README-ja / README-ko parallel lists. So drive-by
  visitors already arrive in their native language to a localised
  list — a localised README + localised app closes the loop.
- The polish bench (M2.5) is built around 99 Whisper languages, so
  the model side scales naturally. The UI was the bottleneck.
- Calling for translators is a strong contributor on-ramp — a
  single-language PR is much smaller than a code contribution and
  builds attachment from translators who feel ownership.

## Non-goals

- Translating the documentation (`docs/*.md`) in this SPEC. README
  translations exist (zh-CN, ja, ko, fr, es, de via auto-translation
  with native-speaker-correction PRs). Other docs follow if there's
  signal.
- Locale-specific feature behaviour (e.g., different default models
  per locale). Defaults stay global.
- Right-to-left layout support (Arabic, Hebrew). Defer to a later
  SPEC if signal arrives.
- Translating SPECs / contributor docs. AGENTS.md, ROADMAP.md, etc.
  stay English-only — they're for contributors who are already in
  the dev workflow.

## Target locales (initial)

Match the language picker in `Sources/OpenQuackApp/SettingsView.swift`
(Settings → General → Transcription language) — same locales the
app already understands for Whisper:

- `zh-Hans` (Simplified Chinese)
- `ja` (Japanese)
- `ko` (Korean)
- `fr` (French)
- `es` (Spanish)
- `de` (German)
- `it` (Italian)
- `pt` (Portuguese)

`zh-Hant` (Traditional Chinese) deferred — Whisper's Chinese output
already has a script picker (`zh-Hans` / `zh-Hant` / `auto`); we
default zh- to zh-Hans for UI strings until traditional-script signal
shows up.

The infrastructure ships **empty** for all locales. Translations land
as PRs.

## Public surface (sketch)

### File layout

```
Sources/OpenQuackApp/Resources/
└── Localizable.xcstrings    # NEW — String catalog file
```

`.xcstrings` is the modern Xcode 15+ string-catalog format. Single
file, all locales co-resident, JSON-backed. Replaces the older
per-locale `.strings` + `.stringsdict` directory layout.

### Migration

Every visible string in the app gets converted from a literal to a
localised lookup:

```swift
// Before
Text("Send feedback…")

// After
Text(String(localized: "settings.menu.send_feedback", defaultValue: "Send feedback…"))

// Or in SwiftUI shorthand:
Text("Send feedback…", comment: "Status-item right-click menu item")
```

The `comment:` parameter is what translators see — make every comment
descriptive (where the string appears, what action it represents).
The `defaultValue` (or the literal string itself) is the English
source of truth.

Key files to migrate (~20-30 strings each):
- `Sources/OpenQuackApp/MenuBarContent.swift`
- `Sources/OpenQuackApp/SettingsView.swift`
- `Sources/OpenQuackApp/RecordingOverlay.swift`
- `Sources/OpenQuackApp/OnboardingFlow.swift`
- `Sources/OpenQuackApp/OpenQuackApp.swift` (right-click menu)
- `Sources/OpenQuackApp/SettingsWindowController.swift`

Total estimated: ~150-200 user-visible strings across the app.

### Locale detection + override

Default behaviour: follow the system locale. macOS gives us
`Locale.current.language.languageCode?.identifier` — if it matches a
target locale, use it; otherwise fall back to English.

Override surface: a new picker in **Settings → General**:

```swift
@AppStorage("displayLanguage") private var displayLanguage: String = "system"

Picker("Display language", selection: $displayLanguage) {
    Text("System").tag("system")
    Text("English").tag("en")
    Text("简体中文").tag("zh-Hans")
    Text("日本語").tag("ja")
    // …
}
```

This is **distinct** from the existing "Transcription language" picker
(which controls Whisper) — display language is for the UI, transcription
language is for the speech model. Both live in Settings → General.

The `displayLanguage` UserDefault is read at app launch via
`Bundle.main.preferredLocalizations` override (set
`AppleLanguages` defaults key). Locale change requires app restart;
surface a "restart to apply" hint when the user changes it.

### Pluralization

Swift's `String(localized:)` supports plurals via `.xcstrings` plural
variations. Strings that pluralize (e.g., "%d transcript" /
"%d transcripts") use the variation form per locale.

Example:
```swift
Text("\(history.count) recorded", comment: "History count, plural-aware")
```

Translators handle the plural rules per locale (e.g., Russian has 3
plural categories, Polish has 4, Japanese has 1).

### Privacy contract — no change

Localisation is pure UI; no audio, no network, no telemetry. The
privacy contract in `docs/VISION.md#privacy-contract` is unaffected.

## Implementation order

Atomic PRs:

| # | Title | Branch | Effort | Files |
|---|---|---|---|---|
| 1 | Add `Localizable.xcstrings` (empty) + Settings → Display Language picker | `feat/spec-019-infra` | S | `Sources/OpenQuackApp/Resources/Localizable.xcstrings` (new), `Sources/OpenQuackApp/SettingsView.swift` (edit) |
| 2 | Migrate `MenuBarContent.swift` strings to localised lookups | `feat/spec-019-menubar` | S | `MenuBarContent.swift` (edit), `Localizable.xcstrings` (auto-extracted) |
| 3 | Migrate `SettingsView.swift` strings | `feat/spec-019-settings` | M | `SettingsView.swift` (edit) — biggest single file |
| 4 | Migrate `RecordingOverlay.swift` + `OnboardingFlow.swift` strings | `feat/spec-019-overlay-onboarding` | S | both files |
| 5 | Migrate `OpenQuackApp.swift` (right-click menu) + remaining surfaces | `feat/spec-019-app-menus` | S | OpenQuackApp.swift + any leftovers |
| 6 | First community translation lands (e.g., zh-Hans) | external PR | — | `Localizable.xcstrings` (translator fills the zh-Hans column) |

PRs 1-5 are infrastructure (we write them). PR 6+ are community
contributions.

### CI: lint that strings are localised

After PR 5 lands, add a CI check that fails if a SwiftUI `Text("…")`
literal appears outside a `String(localized:)` / commented form. Cheap
guard against regressions.

## Translation contribution flow

Documented in `docs/CONTRIBUTING.md` and the language switcher
section of each `README.<lang>.md`:

1. Fork the repo.
2. Open `Sources/OpenQuackApp/Resources/Localizable.xcstrings` in
   Xcode 15+ (renders as a string-catalog editor with per-locale
   columns).
3. Translate the English source strings to your locale.
4. Open a PR titled `i18n: translate to <locale-name>`.
5. We merge if the translations are complete enough to be useful
   (≥80% coverage, no UI-breaking length issues — long German
   strings need testing).

Maintainer responsibilities:
- Don't write translations ourselves unless we're a native speaker
  (the same hand-write-or-native-speaker rule that applies to promo
  copy).
- Merge community translations promptly (≤7 days).
- If a translator vanishes mid-locale, mark the locale "partial" in
  the README and welcome follow-on PRs.

## Open questions

- **Bundle vs runtime locale switch.** macOS prefers per-app
  `AppleLanguages` defaults. Our override picker writes that key
  and prompts restart. Verify on macOS 13 (our minimum) — the API
  is stable but the key name has had variations.
- **Onboarding-flow first-launch locale.** First-launch onboarding
  runs before the user can change preferences — should it use the
  system locale or English? Lean system; if the user picks a
  display language during onboarding, that becomes their override.
- **Long-string fallback.** Some translations are 1.5-2× longer
  than English (notably German). Verify Settings layout doesn't
  truncate. Add max-width hints in `comment:` where the layout is
  tight.
- **Translation-currency badge.** As Whisper / model menus evolve,
  some strings may go stale. Consider a "translation currency"
  display in About — shows the % of strings translated per locale.
  Defer to post-PR-5.

## References

- [Swift String Catalogs WWDC 2023](https://developer.apple.com/videos/play/wwdc2023/10155/) — the introduction.
- [`String.LocalizationValue`](https://developer.apple.com/documentation/swift/string/localizationvalue)
  — the API surface.
- AGENTS.md — atomic PR + SPEC-cite workflow applies to all 6 PRs.
- `docs/CONTRIBUTING.md` — community-side guidance for translators.
- `docs/VISION.md#privacy-contract` — preserved (UI-only change).
