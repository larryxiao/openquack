# SPEC-027 — README demo gif + landing-page polish

**Status:** draft
**Tracks:** Adoption focus band (`docs/ROADMAP.md`)

---

## Problem statement

The README is the first surface every new user hits — from `brew install`,
from awesome-list links, from the Pages landing, from a future Show HN.
Today it has good prose and a static banner but no in-motion demo: a
visitor has to read three sections before they form a mental picture of
*what pressing the hotkey actually does*. A 15-30 s GIF closes that gap in
one glance. `docs/index.md` has the same gap.

This SPEC defines what the demo shows, how to capture and optimise it,
where it lives on both surfaces, and a tightening pass on `docs/index.md`.

## Goal

- One canonical GIF at the top of `README.md` and `docs/index.md`,
  **≤ 2 MB**, looping, sub-30 s.
- A realistic dictation example that incidentally showcases the speed and
  noise-robustness USPs without naming them.
- `docs/index.md` tightened so the install command sits above the fold on
  a 1440 × 900 viewport.

## Non-goals

- Multiple demo videos — one canonical artifact only.
- Animated SVG / WebM hero — GitHub doesn't autoplay video on README; GIF
  is the broad-compat choice.
- Marketing-speak rewrite — this SPEC reshapes the hero only, the rest of
  the README stays.
- Per-language asset variants — translated READMEs reuse the same GIF;
  only `alt` translates.

---

## Demo content design

### Scenario

A working dev in TextEdit, cursor in a blank doc. Full take:

1. Hotkey press.
2. Menu-bar overlay shows **"Listening"**, level meter pulsing realistically.
3. User says, at conversational pace:
   > *"i need to send the quarterly numbers to claude code first before the
   > design review"*
4. Hotkey press to stop.
5. 1-2 s pause — load-bearing proof of speed, do not trim.
6. Transcript appears at the cursor verbatim, with correctly cased
   **"Claude Code"**.
7. Menu-bar popover briefly shows **"Pasted at cursor"** before closing.

### What this proves, in viewing order

1. Global hotkey — TextEdit isn't OpenQuack.
2. Non-intrusive overlay — top-centre, no focus steal.
3. Real speech, not bot — the level meter is the audibility proxy in a
   silent GIF.
4. Real transcript — multi-word, contains "Claude Code", a known Whisper
   failure case. Correct transcription is the noise-robustness USP without
   a caption.
5. Speed — sub-2-second turnaround from stop to paste.

### What this avoids

Polish / agent dispatch (SPEC-007 / SPEC-006 territory). Any LLM features.
Audio (GIFs are silent). Titles, lower-thirds, watermarks — they eat
attention and bloat the file.

---

## Capture and optimisation

**Capture:** macOS `Cmd + Shift + 5` → Record Selected Portion is enough.
[`Kap`](https://getkap.co/) only if a higher-quality intermediate is
needed. Record the choice in the PR.

**Edit:** trim head/tail. No titles, no cursor effects.

**GIF generation** — two-pass palette via `ffmpeg`:

```sh
ffmpeg -i demo.mov -vf "fps=15,scale=900:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" demo.gif
```

900 px matches the GitHub README content column; 15 fps is enough for
mostly-text motion; loop is on by default.

**Target ≤ 2 MB.** If over: drop fps → 12, then width → 720, then trim
more aggressively (the 1-2 s post-stop pause stays).

---

## Hosting and reference

Asset path **`docs/assets/demo.gif`**. The `docs/assets/` directory does
not exist today (`docs/images/` does); the implementing PR creates it.
`docs/images/` keeps static stills, `docs/assets/` is for kinetic /
downloadable artifacts.

| Surface          | Markup path             | Why                                    |
|------------------|-------------------------|----------------------------------------|
| `README.md`      | `docs/assets/demo.gif`  | Repo-root markdown; GitHub serves raw. |
| `docs/index.md`  | `assets/demo.gif`       | Jekyll site root is `docs/`; relative. |

### README hero

Replace the current static banner block at `README.md` lines 1-3
(`<p align="center"><img src="docs/images/banner.png" ...></p>`) with:

```html
<p align="center">
  <img src="docs/assets/demo.gif" width="900"
       alt="OpenQuack dictation demo: press hotkey, speak a sentence, the transcript appears at the cursor in TextEdit; the menu bar confirms 'Pasted at cursor.'" />
</p>
```

The badges row, language switcher, and "What's new" banner stay in place.
The GIF *is* the new banner — stacking a static banner above a kinetic
hero is visual noise. `banner.png` stays in-repo as the `og:image` for
`docs/index.md` (SHA 54d558d).

---

## Landing-page polish — `docs/index.md`

### Above the fold (install command visible at 1440 × 900)

```
H1     # OpenQuack
Lead   Local-only voice dictation for macOS. Press a hotkey, speak,
       the transcript appears at your cursor.
GIF    <img src="assets/demo.gif" width="900" alt="..." />
3 bullets (single line each):
  - **Private** — nothing leaves your device, no telemetry, MIT licensed.
  - **Fast** — ~2.6% WER, sub-3-second turnaround on a 5-minute clip.
  - **Robust** — holds up in real office noise (6.3% WER, noisy bench).
Install
  brew tap larryxiao/openquack https://github.com/larryxiao/openquack
  brew install --cask openquack
  (Or DMG download; macOS 13+ on Apple Silicon.)
```

Below the fold: Documentation links → Blog → FAQ (keep all eight Qs
as-is) → License.

**Cut:** the current "MIT licensed / All local / Fast / 99 languages /
Tiny" bullet block (`docs/index.md` lines 13-18; pre-dates the hero, now
duplicates) and the "[View the repository on GitHub →]" link before
install (the header already links to the repo).

**Keep:** full front-matter (`og:image` / `twitter:image`), full FAQ, all
link lists.

---

## Translated READMEs

`README.{de,es,fr,ja,ko,zh-CN}.md` all reuse the same
`docs/assets/demo.gif`. Only `alt` translates. The implementing PR is
**not** required to translate alt text — leave English alt as a stop-gap
and let SPEC-019 catch up. Note this in the PR description.

## Accessibility

- `alt` describes the action, not "demo".
- "Pasted at cursor" confirmation must be legible at 900 px — verify
  before committing.
- No information conveyed by colour alone; the transcript text appearing
  is the proof.

## Out of scope

- Video (`.mp4` / `.webm`) hero — deferred; GIF is the compat hero.
- Dark-mode variant via `<picture media="(prefers-color-scheme: dark)">` —
  doubles asset maintenance; TextEdit chrome reads in both themes.
- Per-feature mini-GIFs — one canonical hero, not a feature parade.
- YouTube fallback link — deferred.
- `prefers-reduced-motion` swap — deferred.

## Open questions

1. **Commit the source `.mov` alongside the `.gif`?** Lean **no** —
   large, re-encode is cheap; store source in local notes / release
   artifact.
2. **YouTube fallback link?** Deferred.

---

## Test plan

- **README visual:** open the PR on GitHub web; GIF renders inline,
  loops, ≤ 2 MB, alt text reads correctly in view-source.
- **Pages visual:** load `https://larryxiao.github.io/openquack/` (or
  local `bundle exec jekyll serve` from `docs/`); GIF appears above the
  fold on 1440 × 900 **and** the install command is visible without
  scrolling.
- **Mobile:** reload Pages at 375 px; GIF scales (default Jekyll
  `max-width: 100%`) and isn't broken by an explicit width attribute.
- **Translated:** open `README.ja.md`; confirm English alt is an
  acceptable stop-gap.

## PR shape

| PR    | Title                                                              | SPEC cite | Effort |
|-------|--------------------------------------------------------------------|-----------|--------|
| this  | `docs(SPEC-027): README demo gif + landing-page polish`            | SPEC-027  | XS     |
| PR-A  | `docs(README, index): demo gif hero + landing-page polish`         | SPEC-027  | S      |

PR-A is a single atomic PR: adds `docs/assets/demo.gif` (≤ 2 MB), swaps
the README hero block, rewrites `docs/index.md` above the fold per the
layout above. No Swift, no build, no bench — reviewer load is purely
visual. The PR description records the exact `ffmpeg` invocation and
final byte count so the artifact is reproducible.
