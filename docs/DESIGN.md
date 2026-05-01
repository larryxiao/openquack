# Design

OpenQuack's visual + content language. The token spine lives in code (`Sources/OpenQuackApp/Theme.swift`) — this doc explains *why* the tokens look the way they do and how to use them.

The design system was distilled with [Claude Design](https://claude.ai/design). The handoff covered: color tokens, type roles, spacing scale, iconography, brand-mark exploration, and component sketches for every shipped surface (popover, recording overlay, onboarding, settings).

## Tagline

> **Speak. Send. Privately.**

The three-word rhythm is part of the brand. You'll see it reused as section taglines and feature openers — *"Local. Fast. Open."*, *"Voice → action, sustained."* Each period is doing work.

## Voice

Direct, technical, confident. Senior engineer who's tired of marketing fluff.

- **Trust by mechanism, not adjectives.** *"Confidential work stays confidential, by construction"* — never *"safe and secure."*
- **Numbers, sources, mechanisms.** *"~2.6% word-error rate on real human speech on a baseline M4 / 16 GB"* with a link to the bench. Never *"fast and accurate."*
- **Sentence case** for almost everything. *"Open System Settings,"* not *"Open System settings."*
- **Title case** is reserved for proper nouns (OpenQuack, WhisperKit, Claude Code, MIT) and the duck.
- **British spelling** when in doubt — *"Behaviour"*, *"capitalisation"*, *"multilingual"*.
- Talks **about** the product in third person on marketing copy: *"OpenQuack downloads…"*, *"Whisper handles 99 languages…"*. Talks **to** the user in second person inside the UI: *"Press your hotkey,"* *"You're on the latest."* Never "we" or "our team" — there is no team voice. Just the duck and the user.

The product takes itself seriously; the duck does not. *"The duck has bigger plans."* *"🦆 has more tricks up its feathers."* That's voice — emoji in *prose* is fine; emoji as chrome was retired (see Iconography below).

## Color

A two-track palette.

**Reception track** — onboarding, About, Settings panes. Cream surfaces meant to feel calm and paper-like.

| Token         | Hex      | Use                                            |
|---------------|----------|------------------------------------------------|
| `Theme.cream` | `#F5F2EC` | Primary onboarding / Settings background       |
| `creamRaised` | `#E8DFC9` | Glyph circles, raised cream chips              |
| `Theme.ink`   | `#2B2722` | Body text on cream, primary button fill        |

**Material track** — popover, recording overlay. Native macOS materials (`NSVisualEffectView .ultraThinMaterial`); colour comes from system, not us.

**Status palette** — muted, native-feeling. Never the system rainbow.

| Token         | Hex      | Use                                            |
|---------------|----------|------------------------------------------------|
| `Theme.coral` | `#CA564A` | Recording / live / destructive                 |
| `Theme.amber` | `#D9AB4A` | Warming / transcribing / warnings              |
| `Theme.moss`  | `#59844F` | Idle / ready / success / updates               |

System blue (`#007AFF`) is permitted only on macOS-native controls (toggles, prominent system buttons we don't own). Never as a brand colour.

Hairlines: `Color.primary.opacity(0.08)` on light surfaces, `0.06` on cream.

## Type

Apple system fonts; web fallbacks listed for design mocks.

| Role            | Family               | Size    | Weight | Use                                       |
|-----------------|----------------------|---------|--------|-------------------------------------------|
| `oqHeroSerif`   | New York (system)    | 34      | 400    | Onboarding welcome                         |
| `oqTitleSerif`  | New York             | 28      | 400    | Step titles, About wordmark                |
| `oqTaglineSerif`| New York italic      | 15      | 400    | Tagline                                    |
| `oqHeadline`    | SF Pro               | 14      | 500    | Popover header, overlay headline           |
| body            | SF Pro               | 13      | 400    | Form rows, body                            |
| caption         | SF Pro               | 11      | 400    | Hints, secondary text                      |
| caption2        | SF Pro               | 10      | 400    | Tertiary chrome                            |
| mono            | SF Mono              | 12      | 400    | Tabular elapsed time, custom dictionary    |

**Section header** — the unifying typographic motif: `caption2.weight(.semibold) + tracking(1.4) + .uppercase`. Used above every logical group: `STATUS`, `SPEECH-TO-TEXT`, `BEHAVIOUR`. Implemented as the `SectionHeader` view in `Theme.swift`.

**Web fallbacks**: Source Serif 4 / Inter / JetBrains Mono.

## Spacing & radius

Linear scale, no in-between values.

| Token        | px |
|--------------|----|
| `Theme.s4`   | 4  |
| `Theme.s8`   | 8  |
| `Theme.s12`  | 12 |
| `Theme.s16`  | 16 |
| `Theme.s24`  | 24 |
| `Theme.s32`  | 32 |

No 6, no 10, no 20. Section spacing is almost always 16; intra-card 12; inline 8.

| Radius             | px | Use                                       |
|--------------------|----|-------------------------------------------|
| `Theme.rInline`    | 8  | Status badges, small chips, buttons       |
| `Theme.rCard`      | 12 | Banners, transcript card, settings rows   |
| `Theme.rFloating`  | 16 | Overlay pill, popover edges               |

## Buttons

Three variants in `OQButtonStyle` (Theme.swift):

- **`.oqNeutral`** — paper-white fill (`Color.white @ 0.7`), hairline edge. Default ask. Reversible actions: *Export…*, *Copy*, *Settings*.
- **`.oqPrimary`** — deep ink fill (`Theme.ink`), cream-on-ink type, soft top highlight gradient. The primary CTA. Used at most once per surface.
- **`.oqDestructive`** — coral fill (`Theme.coral @ 0.92`), white type. Anything irreversible: *Reset stats*, *Delete all history*.

System-style buttons (`.bordered`, `.borderedProminent`) are reserved for AppKit-native controls we don't own (toggles, the keyboard-shortcut recorder).

Press state: `~85%` opacity. Disabled: `0.4` opacity. Hover is delegated to AppKit's native feedback.

Prefer the `.small` variant in compact chrome (popover footer, banner CTAs). Examples: `.buttonStyle(.oqNeutralSmall)`, `.buttonStyle(.oqPrimarySmall)`.

## Iconography

Two systems, used in different places.

### Menu-bar status item — phase-driven duck silhouettes

Live in `Sources/OpenQuackApp/Resources/MenuIcons/`. Solid-fill silhouettes rendered as `NSImage.isTemplate = true` so macOS auto-tints to the menu-bar text colour (black/light, white/dark, dimmed inactive).

| Phase          | Icon                          | What it conveys                |
|----------------|-------------------------------|--------------------------------|
| `warming`      | `duck-warming` (standing)     | Model loading, alert           |
| `idle`         | `duck-idle` (sitting)         | Calm default                   |
| `recording`    | `duck-recording` (quacking)   | Active mic + sound waves       |
| `transcribing` | `duck-transcribing` (feather) | Writing what was heard         |
| `ready`        | `duck-ready` (swimming)       | Just finished, settling        |
| `error`        | ❌ glyph (fallback)            | Hard failure                   |

### Brand mark — line-art duck variants

Live in `Sources/OpenQuackApp/Resources/Brand/`. Pond-blue line art on transparent background. Used at large sizes on cream / neutral surfaces — About hero, popover header, onboarding welcome, README, app icon.

| Asset              | Source row | Where it's used                         |
|--------------------|------------|-----------------------------------------|
| `duck-in-pond`     | row 5      | About hero, onboarding step 1, README   |
| `duck-quacking`    | row 2      | Menu-bar popover header                 |

Loaded via `DuckMark(size:)` and `QuackingDuck(size:)` in `Theme.swift`. Both pull `@1x` and `@2x` reps from the resource bundle so retina renders crisp.

### SF Symbols

For functional icons inside the app — `lock.shield`, `mic`, `keyboard`, `arrow.down.circle`, `exclamationmark.triangle`, `checkmark.circle.fill`, `gearshape`, `info.circle`. Regular weight, never bold or light.

### App icon

`scripts/make_icon.swift` composites the `duck-in-pond` mark on the cream rounded-rect with a hairline rim, rendered at every `iconset` size. Per-size scale curve: smaller canvases (16/32) draw the mark wider so the line weight stays visible at Finder thumbnail sizes.

## Surfaces

**Reception surfaces** sit on cream — `CreamSurface()` in Theme.swift. Onboarding, About, every Settings tab. These are calm, paper-like, low-tech in feel.

**Material surfaces** use macOS native materials. The popover hosts on `.transient` + system material; the recording overlay pill is `NSPanel` with `.popover` material. No fills, no patterns, no gradients on inline content.

**Cards** = 1 px hairline + `controlBackgroundColor @ 0.5` fill (or `Color.white @ 0.6` on cream) + 12 px radius + 12 px padding. **No drop shadow.** Floating chrome (popover, overlay panel) gets the system shadow only.

## Animation

Restrained.

- **State fades** — `easeInOut`, 0.18 s. Onboarding step transitions, overlay alpha.
- **Phase progress** — `easeOut`, 0.20 s. The amber wash that fills the overlay during transcribing.
- **One-shot bounce** — `.symbolEffect(.bounce)` on the update arrow when a new version arrives.

No springs. No parallax. No particles.

## Layout invariants

| Surface           | Dimension                                    |
|-------------------|----------------------------------------------|
| Popover           | 340 × variable                               |
| Onboarding modal  | 580 × 560                                    |
| Settings window   | min 580 × min 500                            |
| Recording overlay | 320 × 60                                     |

Content is **left-aligned** (LTR reading rhythm). Onboarding step titles and the About hero are **centred** (reception ceremony).

## What's deferred

- A real macOS-native app icon at notarised quality (today's icon is composited from the line-art mark; replace with hand-drawn art once we ship a 1.0).
- Per-state custom menu-bar icons with sub-badges (e.g. update available overlaid on the duck).
- A motion design pass — adding `.symbolEffect` for state transitions where it'd add information, not noise.
- Dark-mode tuning of the cream surfaces (currently defers to `NSVisualEffectView .underWindowBackground`).

## References

- Token spine: [`Sources/OpenQuackApp/Theme.swift`](../Sources/OpenQuackApp/Theme.swift)
- Brand assets: [`Sources/OpenQuackApp/Resources/Brand/`](../Sources/OpenQuackApp/Resources/Brand/), [`docs/images/`](images/)
- Menu-bar phase icons: [`Sources/OpenQuackApp/Resources/MenuIcons/`](../Sources/OpenQuackApp/Resources/MenuIcons/)
- App-icon generator: [`scripts/make_icon.swift`](../scripts/make_icon.swift)
- Vision and privacy contract: [`docs/VISION.md`](VISION.md)
- Original handoff: [Claude Design](https://claude.ai/design)
