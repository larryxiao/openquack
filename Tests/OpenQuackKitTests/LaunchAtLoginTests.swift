import XCTest
import ServiceManagement
@testable import OpenQuackKit

// SPEC-023 — covers the full reconciliation table from §Reconciliation.

final class LaunchAtLoginTests: XCTestCase {

    func testDesiredTrue_enabled_noop() {
        XCTAssertEqual(reconcileLaunchAtLogin(desiredEnabled: true,  currentStatus: .enabled),        .noop)
    }

    func testDesiredTrue_notRegistered_register() {
        XCTAssertEqual(reconcileLaunchAtLogin(desiredEnabled: true,  currentStatus: .notRegistered),  .register)
    }

    func testDesiredTrue_requiresApproval_resetToggleOff() {
        XCTAssertEqual(reconcileLaunchAtLogin(desiredEnabled: true,  currentStatus: .requiresApproval), .resetToggleOff)
    }

    func testDesiredTrue_notFound_register() {
        XCTAssertEqual(reconcileLaunchAtLogin(desiredEnabled: true,  currentStatus: .notFound),       .register)
    }

    func testDesiredFalse_enabled_unregister() {
        XCTAssertEqual(reconcileLaunchAtLogin(desiredEnabled: false, currentStatus: .enabled),        .unregister)
    }

    func testDesiredFalse_notRegistered_noop() {
        XCTAssertEqual(reconcileLaunchAtLogin(desiredEnabled: false, currentStatus: .notRegistered),  .noop)
    }

    func testDesiredFalse_requiresApproval_noop() {
        XCTAssertEqual(reconcileLaunchAtLogin(desiredEnabled: false, currentStatus: .requiresApproval), .noop)
    }

    func testDesiredFalse_notFound_noop() {
        XCTAssertEqual(reconcileLaunchAtLogin(desiredEnabled: false, currentStatus: .notFound),       .noop)
    }
}
