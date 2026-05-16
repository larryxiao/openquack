# SPEC-023 — Launch at login

**Status:** draft
**Tracks:** [#29](https://github.com/larryxiao/openquack/issues/29)

---

## Problem statement

OpenQuack is a menu-bar app whose value depends on it being always-on — the
hotkey only works when the app is running. Today, after every restart the user
has to manually launch from `/Applications` (or Spotlight) before dictation
works. For a tool that's supposed to feel like a system feature, that's a
recurring papercut and a known reason new users churn after their first reboot.
Issue #29 asks for the standard macOS toggle.

## Goal

- A single "Launch OpenQuack at login" toggle in **Settings → General**.
- When on, OpenQuack starts headlessly at user login and shows up in the menu
  bar — no Dock icon, no Settings window, no onboarding flow.
- When off, behaviour is exactly what we have today.
- First-run default is **off** (opt-in).
- App state reconciles itself on launch if the user toggles the OS-side
  permission outside our UI (e.g. revokes us in System Settings → General →
  Login Items).

## Non-goals

- **Pre-macOS-13 fallback via `LSSharedFileList`.** `Package.swift` already
  pins `.macOS(.v13)`, so `SMAppService` is always available.
- **Separate Login Items pane.** A single toggle does not warrant a new pane.
- **Auto-enabling on first run or after install.** Surprise auto-enrolment is
  a trust violation; the user has to flip the toggle.
- **"Launch at login *and* start recording immediately"** — different feature,
  different spec, different consent surface.

## Technical approach

### API

Use [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice)
(macOS 13+):

```swift
import ServiceManagement

try SMAppService.mainApp.register()    // user toggle on
try SMAppService.mainApp.unregister()  // user toggle off
let status = SMAppService.mainApp.status  // .enabled / .notRegistered / .requiresApproval / .notFound
```

No `LaunchAgent` plist, no helper bundle, no embedded XPC service — the app
bundle itself is the login item.

### State

A single `Bool` in `UserDefaults` under the key **`launchAtLogin`**, matching
the existing unqualified-camelCase convention (`autoPaste`, `playSounds`,
`saveAudio`, …). Bound to the Settings UI via `@AppStorage("launchAtLogin")`.

### Reconciliation

On app launch, run a pure reconciliation step to align the persisted toggle
with the actual OS state. The implementer should extract it as a free function
for direct unit testing:

```swift
enum LaunchAtLoginAction { case register, unregister, resetToggleOff, noop }

func reconcile(desiredEnabled: Bool, currentStatus: SMAppService.Status) -> LaunchAtLoginAction
```

| desired | currentStatus           | action            |
|---------|-------------------------|-------------------|
| true    | `.enabled`              | `noop`            |
| true    | `.notRegistered`        | `register`        |
| true    | `.requiresApproval`     | `resetToggleOff`  |
| true    | `.notFound`             | `register`        |
| false   | `.enabled`              | `unregister`      |
| false   | anything else           | `noop`            |

`resetToggleOff` writes `false` back to `UserDefaults` so the Settings UI
reflects reality on next render, and surfaces a single-line hint under the
toggle (see "Settings UI" below). We do **not** silently retry registration
when the user has revoked approval — that's the user's stated preference.

### Toggle write path

When the user flips the toggle, perform `register()` / `unregister()`
synchronously on the main actor:

- `register()` throws → roll the toggle back to off, log via `Logger`, surface
  the hint string.
- `unregister()` throws → leave the toggle off (the goal state was already
  off); log only.

`SMAppService` calls are cheap and need no debounce.

### Headless-launch behaviour

OpenQuack already runs as an `accessory` app (no Dock icon, menu bar only), so
"started by `launchd` at login" looks identical to "started by the user" from
the app's perspective. The only thing that must **not** happen on a headless
launch is the onboarding flow auto-presenting; that's already gated on the
existing `hasCompletedOnboarding` UserDefaults key, so once the user has
completed onboarding once the launch-at-login path is silent by construction.
No new "was I launched at login?" detection is required.

## Settings UI

In `Sources/OpenQuackApp/SettingsView.swift`'s `GeneralPane`, add a new section
at the end of the pane (after "Custom dictionary"):

```swift
Section {
    Toggle("Launch OpenQuack at login", isOn: $launchAtLogin)
        .help("Start OpenQuack automatically when you sign in to your Mac, so the menu-bar icon and global hotkey are ready without launching the app manually.")
    if showsApprovalHint {
        Text("macOS blocked OpenQuack from auto-starting. Enable it in System Settings → General → Login Items, then toggle this on again.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
} header: {
    SectionHeader("Startup")
}
```

`showsApprovalHint` is `true` for the rest of the session whenever
reconciliation returns `.resetToggleOff` or the toggle-write path catches a
register error. Dismissed on next successful `register()`.

## Out of scope

- Migration: no prior login-item state exists; nothing to migrate.
- Telemetry on toggle usage.
- Deep-linking the hint into the System Settings Login Items pane via
  `x-apple.systempreferences:` — nice-to-have, follow-up if users ask.
- Localised strings: `i18n` is its own track (SPEC-019); land English here.

## Test plan

- **Unit test:** drive `reconcile(desiredEnabled:currentStatus:)` through the
  full table above; assert each row returns the expected `LaunchAtLoginAction`.
  No `SMAppService` mocking required — the function is pure.
- **Manual repro (happy path):** enable the toggle in Settings → General →
  Startup, run *System Settings → General → Login Items* and confirm
  *OpenQuack* appears there; restart the Mac; verify the menu-bar icon appears
  within a few seconds of login with no Dock bounce and no Settings window.
- **Manual repro (revoke):** enable the toggle, then *System Settings → Login
  Items* → toggle OpenQuack off; relaunch the app; confirm the General-pane
  toggle has flipped to off and the one-line hint is visible.
- **Manual repro (first run):** fresh install → onboarding completes →
  Settings → General → Startup toggle reads off (opt-in default).
- `swift build && swift test` green.

## PR shape

| PR  | Title                                                              | SPEC cite | Effort |
|-----|--------------------------------------------------------------------|-----------|--------|
| this| `docs(SPEC-023): launch at login`                                  | SPEC-023  | XS     |
| PR-A| `feat(settings): launch-at-login toggle (SMAppService)`            | SPEC-023  | S      |

PR-A is small enough to land in one go: a reconciliation function in
`OpenQuackKit` (unit-tested), an `@AppStorage("launchAtLogin")` Toggle wired
into `GeneralPane`, an `SMAppService.mainApp` register/unregister call on
toggle change, and a single reconciliation call from
`OpenQuackApp.applicationDidFinishLaunching`.
