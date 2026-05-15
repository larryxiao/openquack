import Foundation
import os.log
import ServiceManagement
import OpenQuackKit

// SPEC-023 — App-side integration. Wraps the pure reconcileLaunchAtLogin
// (in OpenQuackKit) with the SMAppService IO, the UserDefaults rollback
// when the user has revoked us, and the session-level approval-hint flag
// that GeneralPane observes.
//
// All methods must be called from the main thread. SwiftUI's @MainActor
// view bodies and AppDelegate.applicationDidFinishLaunching satisfy that.
final class LaunchAtLoginController: ObservableObject {
    private static let defaultsKey = "launchAtLogin"
    private static let logger = Logger(
        subsystem: "org.openquack.OpenQuack",
        category: "launchAtLogin"
    )

    @Published private(set) var showsApprovalHint: Bool = false

    /// Called once from `AppDelegate.applicationDidFinishLaunching`. Aligns
    /// the persisted toggle with the OS-side login-item state in case the
    /// user toggled us off in System Settings → Login Items while OpenQuack
    /// wasn't running.
    func reconcileOnLaunch() {
        let desired = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        perform(
            action: reconcileLaunchAtLogin(
                desiredEnabled: desired,
                currentStatus: SMAppService.mainApp.status
            ),
            desiredEnabled: desired
        )
    }

    /// Called from the Settings toggle's `.onChange`. Performs
    /// register/unregister synchronously; rolls UserDefaults back to false
    /// and sets the hint on failure.
    func apply(desiredEnabled: Bool) {
        perform(
            action: reconcileLaunchAtLogin(
                desiredEnabled: desiredEnabled,
                currentStatus: SMAppService.mainApp.status
            ),
            desiredEnabled: desiredEnabled
        )
    }

    private func perform(action: LaunchAtLoginAction, desiredEnabled: Bool) {
        switch action {
        case .register:
            do {
                try SMAppService.mainApp.register()
                showsApprovalHint = false
            } catch {
                Self.logger.error("register failed: \(String(describing: error), privacy: .public)")
                UserDefaults.standard.set(false, forKey: Self.defaultsKey)
                showsApprovalHint = true
            }
        case .unregister:
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                Self.logger.error("unregister failed: \(String(describing: error), privacy: .public)")
            }
        case .resetToggleOff:
            UserDefaults.standard.set(false, forKey: Self.defaultsKey)
            showsApprovalHint = true
        case .noop:
            // If the user wanted us on and the OS already has us
            // registered, any previous register failure is no longer
            // relevant — clear the hint.
            if desiredEnabled {
                showsApprovalHint = false
            }
        }
    }
}
