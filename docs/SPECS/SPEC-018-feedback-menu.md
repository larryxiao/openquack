# SPEC-018 — Send-feedback menu item

**Status:** draft (M3 — adoption-supporting infra)
**Owner:** `OpenQuackApp/OpenQuackApp.swift` (right-click status-item menu)
**Last updated:** 2026-05-06

## Goal

Most users won't open a GitHub issue from a browser to report a bug or
request a feature. Add a one-click path from the menu-bar status item to
the right repo issue template, so the friction from "this is broken" to
"filed" is one click.

## Why

After the May 5 launch, the bottleneck on adoption isn't the product; it's
the feedback loop. The repo has bug-report and feature-request issue
templates (`.github/ISSUE_TEMPLATE/bug_report.yml`,
`feature_request.yml`) and a `SUPPORT.md` page, but a user dictating
into Slack at 2 PM is unlikely to navigate to GitHub manually. A single
"Send feedback" item in the status-item right-click menu collapses that
to one click.

## Non-goals

- In-app feedback form. We don't want a custom form widget; GitHub's
  templates are already structured and cover what we need.
- Telemetry. The menu item opens a browser; nothing is sent
  automatically.
- Crash reporting. That's a separate spec (M3+, opt-in only).

## Public surface

A new `NSMenuItem` titled "Send feedback…" appears in the right-click
menu (`OpenQuackApp.showStatusItemMenu`), between "Show app" and the
separator before "Quit". Hotkey: none.

Behaviour: opens
`https://github.com/larryxiao/openquack/issues/new/choose` in the user's
default browser via `NSWorkspace.shared.open(_:)`. The chooser page
shows our two templates plus the Discussions / bench-PRs config-yml
contact links.

If a future telemetry channel exists (opt-in only), it can append a
prefilled query-string in this URL — out of scope for this spec.

## Open questions

- Should the menu item link to `/issues/new/choose` (chooser) or directly
  to `bug_report.yml`? Chooser is more general but adds one click;
  bug-report is more common but assumes intent. Default: chooser.
- Should there be a "Star on GitHub" item too? Probably yes, but as a
  separate spec — different concern.

## Privacy impact

None. The menu item opens a URL in the user's browser. No app-side IO.
The privacy contract is unchanged.

## Test

Unit-testable by inspecting the menu structure on `OpenQuackApp` after
construction. Manual repro: launch app, right-click status item, click
"Send feedback…", verify GitHub chooser page opens.
