# SPEC-041 — "Money saved" estimate in usage stats

## Goal

Show the user, in Settings → Stats, roughly how much their on-device dictation
would have cost on a paid cloud alternative — so the free + private value is
legible, not implied. Two comparison bases, user-selectable:

- **Usage-metered** (transcription APIs): audio minutes × $/min.
- **Subscription** (consumer dictation apps): months active × $/month.

## Background

SPEC-013's Stats pane already tracks `audioSeconds`, `wordsDictated`,
`dictationCount`, and `firstRecordedAt` locally, and frames a value story
("Time saved vs. typing"). "Money saved" is the natural companion: OpenQuack
transcribes on the user's Mac for free, while the alternatives are metered APIs
(OpenAI, Deepgram, …) or flat subscriptions (Wispr Flow, Superwhisper, …). The
two billing models give two honest framings; the user picks which they find
meaningful, or supplies a custom rate.

## Mechanism

`MoneySaved` (OpenQuackKit/Stats) is a pure, table-driven calculator — no UI, no
network, prices baked in and dated so the numbers are auditable and unit-tested.

```
Basis = .perAudioMinute(usd)   // saved = audioMinutes × usd
      | .perMonth(usd)         // saved = monthsActive × usd  (monthsActive ≥ 1)
```

`monthsActive` derives from `firstRecordedAt`..`now`, floored at 1 (a
subscription bills from day one). Per-minute is the precise, assumption-free
default; per-month is the relatable alternative with an explicit caveat that it
assumes you'd have carried the subscription the whole time.

**Built-in baselines** (prices verified June 2026; the UI offers a custom rate
for anything unlisted or out of date):

| Baseline | Basis | Price |
|---|---|---|
| OpenAI gpt-4o-transcribe | per minute | $0.006 / min |
| OpenAI gpt-4o-mini-transcribe | per minute | $0.003 / min |
| Wispr Flow | per month | $15 / mo |
| Superwhisper Pro | per month | $9.99 / mo |

The Stats pane adds a **Money saved** section (gated behind the existing
`showUsageStats` toggle): a "Compared to" picker (the baselines + "Custom rate…"),
the headline dollar figure, the transparent math (`X min × $0.006/min` or
`Y months × $15/mo`), and a dated-source caption. Only shown once there is audio
to compare.

## Privacy impact

Preserves the `docs/VISION.md` contract. Prices are compiled-in constants;
**no network IO**, no third-party calls, no new data collected. The estimate is
computed from the same local counters the pane already shows — nothing leaves the
Mac.

## Acceptance criteria

- [ ] `MoneySaved.savedUSD` returns `$0.36` for 1 hour of audio at
      `.perAudioMinute(0.006)`, `$0` for zero audio, and `$45` for a 3-month-old
      `firstRecordedAt` at `.perMonth(15)`. (unit test)
- [ ] Per-month is floored at 1 month: a 5-day-old start at `.perMonth(15)`
      returns `$15`, not a fraction. (unit test)
- [ ] `.perMonth` with no `firstRecordedAt` returns `$0`. (unit test)
- [ ] Settings → Stats shows a "Money saved" section (when stats are revealed and
      audio > 0) with a working "Compared to" picker, a custom-rate option, the
      headline figure, and the transparent math line. (manual)
- [ ] `swift build && swift test` green.

## Out of scope

- Live price fetching / per-provider API integration — prices are static + dated;
  a custom rate covers drift.
- Currencies other than USD (format is `$`); localise later if asked.
- Counting tiers/free-allowances of the paid alternatives — the estimate is a
  simple upper-bound-ish "list price × usage", stated as an estimate.
