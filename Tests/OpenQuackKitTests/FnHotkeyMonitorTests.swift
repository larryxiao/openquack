import XCTest
@testable import OpenQuackKit

// Tests for FnHotkeyMonitor's pure dispatch logic.
//
// We test dispatchFlagsChanged / dispatchKeyDown directly rather than the
// NSEvent-facing entry point so the suite doesn't need a running app or
// real keyboard events.

final class FnHotkeyMonitorTests: XCTestCase {

    // MARK: - Bare fn shortcut

    func testBareFn_downThenUp_firesDownThenUp() {
        let monitor = FnHotkeyMonitor()
        monitor.setShortcut(FnShortcut(keyCode: nil))

        var events: [String] = []
        monitor.onKeyDown = { events.append("down") }
        monitor.onKeyUp   = { events.append("up") }

        monitor.dispatchFlagsChanged(nowDown: true)
        monitor.dispatchFlagsChanged(nowDown: false)

        XCTAssertEqual(events, ["down", "up"])
    }

    func testBareFn_doubleDown_firesOnlyOneDown() {
        let monitor = FnHotkeyMonitor()
        monitor.setShortcut(FnShortcut(keyCode: nil))

        var downCount = 0
        monitor.onKeyDown = { downCount += 1 }

        monitor.dispatchFlagsChanged(nowDown: true)
        monitor.dispatchFlagsChanged(nowDown: true)  // spurious repeat

        XCTAssertEqual(downCount, 1)
    }

    func testBareFn_upWithoutPriorDown_doesNotFire() {
        let monitor = FnHotkeyMonitor()
        monitor.setShortcut(FnShortcut(keyCode: nil))

        var upCount = 0
        monitor.onKeyUp = { upCount += 1 }

        monitor.dispatchFlagsChanged(nowDown: false)  // fn was never down

        XCTAssertEqual(upCount, 0)
    }

    // MARK: - fn+key shortcut

    func testFnPlusKey_correctCombo_firesDown() {
        let monitor = FnHotkeyMonitor()
        monitor.setShortcut(FnShortcut(keyCode: 0))  // fn+A (keyCode 0)

        var downCount = 0
        monitor.onKeyDown = { downCount += 1 }

        monitor.dispatchFlagsChanged(nowDown: true)   // fn held
        monitor.dispatchKeyDown(keyCode: 0)            // press A

        XCTAssertEqual(downCount, 1)
    }

    func testFnPlusKey_wrongKey_doesNotFire() {
        let monitor = FnHotkeyMonitor()
        monitor.setShortcut(FnShortcut(keyCode: 0))  // fn+A

        var downCount = 0
        monitor.onKeyDown = { downCount += 1 }

        monitor.dispatchFlagsChanged(nowDown: true)   // fn held
        monitor.dispatchKeyDown(keyCode: 1)            // press S instead

        XCTAssertEqual(downCount, 0)
    }

    func testFnPlusKey_keyWithoutFn_doesNotFire() {
        let monitor = FnHotkeyMonitor()
        monitor.setShortcut(FnShortcut(keyCode: 0))  // fn+A

        var downCount = 0
        monitor.onKeyDown = { downCount += 1 }

        monitor.dispatchKeyDown(keyCode: 0)  // A pressed but fn not held

        XCTAssertEqual(downCount, 0)
    }

    func testFnPlusKey_fnUpDoesNotFireKeyUp() {
        let monitor = FnHotkeyMonitor()
        monitor.setShortcut(FnShortcut(keyCode: 0))  // fn+A

        var upCount = 0
        monitor.onKeyUp = { upCount += 1 }

        monitor.dispatchFlagsChanged(nowDown: true)
        monitor.dispatchFlagsChanged(nowDown: false)

        XCTAssertEqual(upCount, 0)
    }

    // MARK: - No shortcut

    func testNoShortcut_doesNotFire() {
        let monitor = FnHotkeyMonitor()
        // no setShortcut call — shortcut is nil

        var eventCount = 0
        monitor.onKeyDown = { eventCount += 1 }
        monitor.onKeyUp   = { eventCount += 1 }

        monitor.dispatchFlagsChanged(nowDown: true)
        monitor.dispatchFlagsChanged(nowDown: false)
        monitor.dispatchKeyDown(keyCode: 0)

        XCTAssertEqual(eventCount, 0)
    }

    func testClearShortcut_stopsDispatching() {
        let monitor = FnHotkeyMonitor()
        monitor.setShortcut(FnShortcut(keyCode: nil))

        var downCount = 0
        monitor.onKeyDown = { downCount += 1 }

        monitor.dispatchFlagsChanged(nowDown: true)
        XCTAssertEqual(downCount, 1)

        monitor.setShortcut(nil)
        monitor.dispatchFlagsChanged(nowDown: false)
        monitor.dispatchFlagsChanged(nowDown: true)
        XCTAssertEqual(downCount, 1)  // no new events after clear
    }
}
