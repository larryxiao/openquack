# Getting help with OpenQuack

A few different ways, depending on what you're after.

## Something's broken

[Open a bug report.](https://github.com/larryxiao/openquack/issues/new?template=bug_report.yml) Two minutes; we'll triage within a day.

If it's a crash, a misfired hotkey, a wrong transcript on real speech, or auto-paste landing in the wrong app — that's a bug, please file it.

## Something's missing

[Open a feature request.](https://github.com/larryxiao/openquack/issues/new?template=feature_request.yml) Even if you're not sure it's the right design — that's our job to figure out.

Please check [`docs/ROADMAP.md`](docs/ROADMAP.md) first; if it's already there, comment on the existing issue instead of filing a new one.

## You have a question, an idea, or want to share a use case

[GitHub Discussions](https://github.com/larryxiao/openquack/discussions) is the right place. Lower friction than an issue. Examples:

- "Is this normal? My medium model takes 5s on a 30s clip."
- "Anyone tried this with Cursor / Claude Code / Aider?"
- "Here's how I use OpenQuack for Chinese messaging."
- "What model would you suggest on an M1 / 8 GB?"

Quick replies welcome. We read everything.

## You want to contribute

Code, docs, bench results, design feedback — all welcome. Read [`AGENTS.md`](AGENTS.md) (the workflow is the same for humans), pick a 🔵 task in [`docs/ROADMAP.md`](docs/ROADMAP.md), open a draft PR.

If you have an M1 / M2 / M3 / Intel / 8 GB / 24 GB+ Mac and want to contribute a benchmark row, that's [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md) — the easiest contribution and the most useful to other users.

## Privacy, in one screen

- Audio never leaves your Mac. Same for transcripts.
- No analytics, no telemetry, no signup.
- Verify with Little Snitch / Lulu, or by reading the source.
- Full contract: [`docs/VISION.md#privacy-contract`](docs/VISION.md#privacy-contract).

If a bug report or feature request would require sharing a recording or a transcript that's sensitive — don't. A short paraphrased description is fine. We can repro most things from a description.

## Security disclosures

Please email `security@<the-domain-on-the-repo>` privately rather than filing a public issue. (Or open a GitHub Security Advisory if you prefer that flow.)

## Response time

This is an open-source side project, not a SaaS. Realistic expectation:

- Critical bugs (crashes, dictation broken on common configs): within 48h.
- Other bugs: within a week.
- Feature requests: triaged within a week, queued by priority.
- Discussions: usually within a day.

If something's been sitting >2 weeks with no response, ping it — we may have missed it.
