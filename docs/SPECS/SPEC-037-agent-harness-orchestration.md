# SPEC-037 — Agent harness & orchestration

**Status:** proposal

## Goal

Make the contribution loop machine-executable. Today `AGENTS.md` is a manual a
human or a hand-prompted agent follows; nothing in the repo *runs* the
backlog → claim → branch → implement → draft-PR cycle. This spec proposes a
committed `.claude/` harness — named subagent roles, saved workflows, a trigger
layer, and a permissions/secrets model — so an agent can pick up a 🔵 task and
land a draft PR without a human kicking each step, while every irreversible or
outward action (merge, release, public post) stays behind a hard human gate.

Design-first: this PR adds the spec only. Implementation is a follow-up per
`AGENTS.md` (one PR adds the spec; a later PR builds it).

## Background

`.claude/` currently holds only `worktrees/`. There is no committed
`agents/`, `commands/`, `workflows/`, or `settings.json` — the orchestration
layer lives in whatever ad-hoc prompt a maintainer types. The repo already has
the *contract* an autonomous loop needs (specs-as-law, four bench harnesses,
issue/PR templates, persistent memory); what is missing is the *runner*.

Two adjacent capabilities are explicitly **not** built here and are cross-linked
instead of duplicated: the quality eval-gate the implementer/bench-runner roles
report against is **SPEC-038**, and the signed release the release-bot wants to
cut is **SPEC-025**. SPEC-037 is the harness that *defers to* 038 for quality
and *blocks on* 025 for the release cut.

## Mechanism

### Committed roles (`.claude/agents/`)

One file per role, each scoped to a single concern:

| Role | Does | May NOT |
|---|---|---|
| `spec-writer` | Drafts a `SPEC-XXX` for an ⚪ idea; opens a spec PR | implement before the spec PR merges |
| `implementer` | Claims a 🔵 task, branches, implements, opens a draft PR | merge; touch the dictation/agent hot path with new network IO |
| `reviewer` | Reviews a draft PR against its cited spec's acceptance criteria | approve-and-merge in one step |
| `bench-runner` | Runs the relevant `openquack-*bench`, reports the delta in the PR | gate on results (that is SPEC-038's CI job, not a local role) |
| `release-bot` | PREPs a release (version bump, cask SHA stub, draft notes) | cut a release — blocked until SPEC-025 signing lands |
| `gtm-drafter` | Drafts/schedules/scans posts into the gitignored `gtm/` workspace | post publicly; `git add gtm/` |

### Saved workflows (`.claude/workflows/`)

Named, replayable multi-step flows that compose the roles — e.g.
`claim-and-draft` (pick 🔵 → branch → implement → draft PR) and
`spec-from-idea` (⚪ → spec PR). A workflow is a committed file, not a live
prompt, so its steps and its gates are reviewable in a diff.

### The loop

`backlog → claim → branch → implement → draft-PR`, driven by `claim-and-draft`:
read `ROADMAP.md`, pick the highest-priority unclaimed 🔵 (Adoption focus
before Feature backlog, per the roadmap's own ordering), open the *Agent Task*
issue, branch, implement against the spec's acceptance criteria, run build +
test + any bench the change touches, open a **draft** PR citing the spec. The
loop stops at draft. It never marks ready, never merges.

### Trigger layer (`.claude/`)

- **cron** — periodic backlog scan; emit one `claim-and-draft` run when an
  unclaimed 🔵 exists and no draft PR already covers it.
- **GitHub events** — a new bug-report issue routes to `spec-writer` triage; a
  red CI on an agent's own draft routes back to `implementer`; a review comment
  routes to the PR author role.

Triggers may *start* work and *open drafts*. They may not advance state past a
draft.

### Permissions & secrets — hard human gates

The permissions model is deny-by-default at every outward or irreversible edge:

| Action | Gate |
|---|---|
| Merge a PR | human only — no role and no workflow holds merge capability |
| Cut a release | human only, **and** blocked until SPEC-025 (release-bot may PREP) |
| Public post | human only — `gtm-drafter` writes to local `gtm/`, never posts |
| Force-push / history rewrite / hot-path network call | forbidden per `AGENTS.md` |

Secrets (signing keys, API tokens) are never readable by the implementer,
reviewer, or gtm roles; only the release pipeline (SPEC-025) sees signing
secrets, and only inside its gated job. The harness adds no network call to the
dictation or agent-dispatch hot path.

## Privacy impact

Preserves the `docs/VISION.md` contract. The harness operates on repo source,
specs, and the GitHub API — no audio, transcript text, or user data. The
field-feedback loop the harness might one day consume stays consented and
opt-in (SPEC-036 / 033 / 034 own that); SPEC-037 does not collect or transmit
anything from users. The `gtm/` workspace stays gitignored and local; no role
may stage it. No new network call enters the dictation or agent-dispatch hot
path.

## Acceptance criteria

- [ ] `.claude/agents/` contains exactly the six role files above, each naming
      its allowed actions and its explicit deny-list. (file check)
- [ ] `.claude/workflows/` contains at least `claim-and-draft` and
      `spec-from-idea` as committed files. (file check)
- [ ] A dry-run of `claim-and-draft` against a seeded `Agent Task` issue
      produces a **draft** PR that cites the spec and runs build + test, with
      **no** human action between trigger and draft. (manual)
- [ ] `grep` over `.claude/workflows/` and `agents/` shows **no** role or
      workflow holds merge, release-cut, or public-post capability — every such
      step routes through an approval gate. (grep, verifiable)
- [ ] `release-bot` on a tagged commit produces a *prepared* release (version
      bump + draft notes + cask SHA stub) and **halts before the cut**, with a
      note that the cut is blocked on SPEC-025. (manual)
- [ ] The cron + GitHub-event triggers are committed and documented; firing one
      starts work but cannot advance a PR past draft. (file check + manual)
- [ ] `swift build && swift test` unaffected (harness is config, not product
      code). (CI)

## Out of scope

- **Autonomous public posting.** GTM is agent-*assisted* only — draft, schedule,
  scan, measure — with a human gate on every outward post. (`gtm-drafter`.)
- **Autonomous releases without signing.** release-bot PREPs; the cut is
  human-gated and blocked until **SPEC-025** lands notarisation.
- **The CI eval-gate.** WER/RTF gating on real corpora is **SPEC-038**; this
  spec's bench-runner only *reports*, it does not gate.
- **Self-merge under any condition.** Merge is human-only, full stop.