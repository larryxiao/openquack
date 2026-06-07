# SPEC-033 — Crash-sentinel bug-report prompt

## Goal

When OpenQuack detects it didn't exit cleanly (crash, force-quit, unexpected power loss),
show a one-time alert on the next launch offering to file a GitHub bug report.

## Background

SPEC-014's `offerRecoveryIfNeeded()` surfaces incomplete recordings, but only when audio
history is enabled — which is OFF by default. Most crashes are invisible to that path.
A clean-exit sentinel closes the gap: it fires for any unclean exit regardless of whether
audio was being saved.

## Mechanism

**Clean-exit sentinel** stored in `UserDefaults` under key `"crashSentinel"` (Bool).

| Event | Action |
|---|---|
| App launches | Read value. If `true` → unclean exit detected. Immediately write `true` (this session is now running). |
| App terminates cleanly | `applicationWillTerminate` writes `false`. |
| App crashes / force-quit / power-loss | `applicationWillTerminate` never runs → value stays `true`. |

First launch: key absent → `bool(forKey:)` returns `false` → no prompt.

## UI

`NSAlert` (same pattern as SPEC-014 recovery alert, modal).

- **Message**: "OpenQuack didn't exit cleanly last time."
- **Informative text**: "This is usually a crash or force-quit. Filing a report helps us fix it."
- **Button 1 (default)**: "Report Bug" → opens `https://github.com/larryxiao/openquack/issues/new?template=bug_report.yml`
- **Button 2**: "Dismiss" → no-op

Alert is shown **before** the recovery alert so both can appear in a single launch without
reordering surprises (crash → report → then recover the audio).

## Non-goals

- No auto-uploader, telemetry, or Sentry/Crashlytics integration.
- No opt-in toggle — the prompt is one-time per event; dismissing it is enough.
- No URL prefilling for now (GitHub YAML form prefill is inconsistent across browsers).
- Not distinguishing crash vs. force-quit vs. power-loss — "unclean exit" is sufficient.

## Acceptance criteria

- [ ] After a simulated crash (force-quit the app), next launch shows the alert.
- [ ] "Report Bug" opens the bug-report template in the default browser.
- [ ] "Dismiss" closes without opening a browser.
- [ ] Clean exit (`⌘Q` / "Quit OpenQuack") suppresses the alert on next launch.
- [ ] First-ever launch does not trigger the alert.
- [ ] The alert does not appear a second time for the same event.
