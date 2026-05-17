# Contributing to OpenQuack

OpenQuack is a one-person side project that ships in public. Most of
the help we want isn't code — it's bench results from your Mac, beta
testing on your hardware / language, translation, and feedback when
something doesn't fit your workflow.

If you want to help, here's where each kind of contribution goes.

## Help us test it (any Mac, any language)

OpenQuack is in alpha. The dictation path is solid, the polish path
(M2.5) is in progress, the agent layer (M3) is on the roadmap. What
we need most: people running it on configurations we can't —
non-M4 Macs, 8 GB and 24+ GB memory tiers, Intel Macs, less-common
languages (the Whisper model handles 99 of them; we've validated a
handful).

**How to help:**

1. Install via [`brew tap larryxiao/openquack && brew install --cask openquack`](README.md#install) or grab the [DMG](https://github.com/larryxiao/openquack/releases).
2. Use it for a few real dictations — short, long, in your primary
   language.
3. If something feels off, [file a bug report](https://github.com/larryxiao/openquack/issues/new?template=bug_report.yml).
   The bug template asks for OpenQuack version + macOS + hardware +
   model — please fill those in, they're the load-bearing fields.
4. If something is missing, [request a feature](https://github.com/larryxiao/openquack/issues/new?template=feature_request.yml).
5. Quick questions or "is this normal?" → [Discussions](https://github.com/larryxiao/openquack/discussions).

## Help us benchmark on your Mac

OpenQuack picks default models per memory tier based on bench data —
but our matrix is M4 / 16 GB only. Adding rows from M1, M2, M3, Intel
Macs, 8 GB, 24+ GB is the **single most useful contribution** at
this stage.

[`bench/CONTRIBUTING.md`](bench/CONTRIBUTING.md) walks through it:

```sh
bash bench/corpus/fetch.sh
swift run openquack-bench \
  --engines whisperkit \
  --models tiny,small,large-v3-turbo \
  --corpus bench/corpus \
  --verbose
```

Output lands in `bench/out/<host-tag>/`. PR that directory; we merge
quickly.

## Help us size the ANE cache footprint (volunteer measurement campaign)

We're investigating whether OpenQuack can drop the ~1.5 GB on-disk
Whisper-medium weights once macOS has compiled them for the Neural
Engine — see [SPEC-029](docs/SPECS/SPEC-029-ane-cache-only-model.md).
To decide whether that's worth shipping, we need numbers from Macs
we don't own: M1 / M2 / M3 / M4 across 8 / 16 / 24+ GB tiers, and at
least one Intel Mac. The full hardware-coverage matrix is in
[SPEC-030](docs/SPECS/SPEC-030-ane-cache-volunteer-bench.md).

**How to help (≈3 minutes):**

```sh
bash scripts/bench_ane_cache.sh
```

That's the whole ask. The script is read-only outside `bench/out/`,
makes zero network calls, and uploads nothing on its own. It:

1. Locates your installed OpenQuack and its WhisperKit model cache.
2. Sums on-disk source weights + e5rt (ANE) compiled cache sizes.
3. Times one cold and one warm transcribe of a short sample clip
   (or prints copy-pasteable manual instructions if you don't have
   `openquack-cli` installed).
4. Writes `bench/out/<host-tag>/cache-report.json` and prints a
   one-screen markdown summary.

**Where to send the result:**

- **Casual** — paste the printed summary block into the
  [#cache-footprint Discussion](https://github.com/larryxiao/openquack/discussions).
- **Power-user** — PR `bench/out/<host-tag>/cache-report.json`.

No audio, no transcripts, no identifiers beyond chip / RAM / macOS
build leave your Mac. The data feeds directly into SPEC-029's
go/no-go decision — your one report meaningfully moves a real call.

If you happen to update macOS, running the script **once before** and
**once after** is the single highest-value contribution: it tells us
whether the ANE cache survives OS updates or has to be rebuilt from
scratch. We're not asking you to update on our behalf — only to
re-run if you were updating anyway.

## Help us translate the app and docs

OpenQuack supports 99 Whisper languages for dictation, but the UI
and documentation are English-only today. Translation contributions
are very welcome:

- **README translations** — there are machine-translated stubs in
  `README.zh-CN.md`, `README.ja.md`, `README.ko.md`, `README.fr.md`,
  `README.es.md`, `README.de.md`. Each has a "machine-translated;
  native-speaker contributions welcome" disclaimer. PRs improving
  any of these are merged on sight.
- **App UI translations** — see [SPEC-019](docs/SPECS/SPEC-019-i18n.md)
  for the i18n infrastructure. Once PRs 1-5 of that sequence land,
  community translators can fill `Sources/OpenQuackApp/Resources/Localizable.xcstrings`
  per-locale via PR.
- **A new language not in the list** — if you want to translate
  OpenQuack to a language we don't list yet (e.g. Vietnamese, Hindi,
  Arabic), open a Discussion thread first so we can sequence it.

Native speakers only, please. Auto-translation tells in body prose
hurt more than no translation in target communities — same rule we
apply to ourselves (we don't auto-translate any promo or
discussions copy). The README files use machine translation **with
explicit disclaimers** because they're reference docs that benefit
from imperfect translation; promo and Discussions are different.

## Contribute code

[`AGENTS.md`](AGENTS.md) is the full workflow doc — applies equally to
human contributors and AI agents. Quick form:

1. Pick a 🔵 task in [`docs/ROADMAP.md`](docs/ROADMAP.md).
2. Read the cited SPEC under `docs/SPECS/`.
3. Open a draft PR within ~24h naming the task in the title.
4. Atomic — one PR, one SPEC.
5. Tests are non-optional (unit test for logic, manual repro steps
   for UX).
6. The PR template at `.github/pull_request_template.md` is enforced.

The hardest parts of the codebase — Streaming transcription
(SPEC-012), Polish engine (SPEC-007), Agent dispatch (SPEC-006) —
all have detailed SPECs. Reading the SPEC before opening a PR
prevents most rework.

## Spread the word — only if it works for you

If OpenQuack genuinely fits your workflow, telling others helps.
But please:

- Don't post in communities you haven't been participating in.
- Don't lead with the marketing voice (the README's lead
  paragraph is fine to quote; the rest is yours to summarise).
- Real comparisons against tools you've used both of are way more
  useful than generic praise.

If you write something about OpenQuack — a blog post, a thread, a
review — link it back via [Discussions](https://github.com/larryxiao/openquack/discussions/new?category=show-and-tell)
in the "Show and tell" category. We'll read everything.

## Privacy and conduct

- **Privacy contract** is binding for every contribution: audio
  never leaves the user's Mac; no telemetry; default agent does no
  network IO. Contributions that introduce a network call in the
  dictation hot path will be rejected. See [`docs/VISION.md#privacy-contract`](docs/VISION.md#privacy-contract).
- **Code of conduct**: assume good faith, prefer questions over
  accusations, and be patient — the maintainer responds in their
  own timezone, on a side-project schedule. Most issues triaged
  within a week; bench-result PRs faster.

## Where to start if you have 30 minutes

- **Cache-footprint contributor (3 min)**: run
  `bash scripts/bench_ane_cache.sh` and paste the summary into the
  [#cache-footprint Discussion](https://github.com/larryxiao/openquack/discussions).
  See [SPEC-030](docs/SPECS/SPEC-030-ane-cache-volunteer-bench.md) for the
  hardware we still need.
- **Bench contributor**: run the bench on your Mac, PR the output
  directory.
- **Translator**: fix a section in any of the `README.<lang>.md`
  files (machine translation isn't great).
- **Tester**: install, dictate for 30 minutes, file one issue if
  anything fits the bug-report template.
- **Reader**: open `docs/VISION.md` and `docs/ROADMAP.md`, see if
  any 🔵 task feels like yours.

Thanks for being here. The duck quacks because of you.
