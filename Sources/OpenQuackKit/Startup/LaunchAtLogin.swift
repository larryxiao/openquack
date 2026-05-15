import Foundation
import ServiceManagement

// SPEC-023 — Launch at login.
//
// Pure reconciliation between the user's desired state (persisted in
// UserDefaults as a `Bool` under "launchAtLogin") and the OS-side state
// reported by `SMAppService.mainApp.status`. The Settings toggle writes
// to UserDefaults and triggers the corresponding register/unregister
// call directly; on app launch, the reconciler aligns the two in case
// the user toggled the login item off in System Settings → Login Items
// while OpenQuack wasn't running.
//
// The function is intentionally pure so the full state table is unit
// tested without an `SMAppService` mock. The caller is responsible for
// invoking `SMAppService.mainApp.register()` / `.unregister()` and for
// writing `false` back to UserDefaults when `resetToggleOff` is
// returned. See SPEC-023 §Reconciliation for the action table.

public enum LaunchAtLoginAction: Equatable, Sendable {
    /// State already matches: do nothing.
    case noop
    /// User wants it on and the OS doesn't have a BTM record for us yet —
    /// `register()`. Covers both `.notRegistered` (legacy) and `.notFound`
    /// (no BTM record exists at this bundle path, i.e. the bootstrap state
    /// for `SMAppService.mainApp` before any successful register call).
    case register
    /// User wants it off and the OS has us registered — `unregister()`.
    case unregister
    /// User wants it on but the OS reports `.requiresApproval` — the BTM
    /// record exists but the user has actively disabled us in System
    /// Settings → Login Items. Write `false` back to UserDefaults so the
    /// Settings toggle reflects reality, and surface the approval-hint copy.
    case resetToggleOff
}

/// Reconcile the persisted "launchAtLogin" toggle with the OS-side status.
/// Pure; the caller performs the IO.
public func reconcileLaunchAtLogin(
    desiredEnabled: Bool,
    currentStatus: SMAppService.Status
) -> LaunchAtLoginAction {
    switch (desiredEnabled, currentStatus) {
    case (true,  .enabled):          return .noop
    // `.notFound` is the bootstrap state for `SMAppService.mainApp`: BTM
    // simply has no record at this bundle path yet. Treat it like
    // `.notRegistered` and try to register — the system will only build
    // the record after a successful `register()` call.
    case (true,  .notRegistered),
         (true,  .notFound):         return .register
    case (true,  .requiresApproval): return .resetToggleOff
    case (false, .enabled):          return .unregister
    case (false, _):                 return .noop
    @unknown default:                return .noop
    }
}
