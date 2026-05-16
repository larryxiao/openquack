import AppKit

// SPEC-003a — Fn/Globe key hotkey dispatch.
//
// Carbon's RegisterEventHotKey doesn't accept the fn key as a modifier or key
// code, so KeyboardShortcuts can't represent fn-based bindings. This module
// provides the parallel path: an NSEvent global monitor for .flagsChanged and
// .keyDown that fires the same onKeyDown/onKeyUp callbacks that HotkeyManager
// already exposes to callers.
//
// Permission requirement: addGlobalMonitorForEvents for keyboard events
// requires Accessibility trust — the same grant OpenQuack already requests
// for paste-at-cursor (SPEC-005). No Input Monitoring prompt, no new
// entitlement, no CGEventTap.
//
// Threading: all mutation is on the main thread by convention. NSEvent global
// monitors fire on the main thread (Apple docs), and callers (HotkeyManager,
// FnAwareShortcutRecorder) invoke setShortcut from @MainActor contexts.
// The class is @unchecked Sendable to avoid forcing @MainActor on every
// stored-property site in HotkeyManager.

// MARK: - FnShortcut

/// A hotkey binding that uses the fn/Globe key.
///
/// `keyCode == nil` means bare fn (press fn alone to fire).
/// `keyCode != nil` means fn + that printable key.
public struct FnShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16?

    public init(keyCode: UInt16? = nil) {
        self.keyCode = keyCode
    }
}

public extension FnShortcut {
    static let defaultsKey = "openquack.toggleRecording.fn"

    static var stored: FnShortcut? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let shortcut = try? JSONDecoder().decode(FnShortcut.self, from: data)
        else { return nil }
        return shortcut
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// Human-readable label for the recorder UI ("fn 🌐" or "fn 🌐 + A").
    var displayLabel: String {
        if let kc = keyCode {
            return "fn 🌐 + \(FnShortcut.keyLabel(for: kc))"
        }
        return "fn 🌐"
    }
}

// MARK: - Key code → label

private extension FnShortcut {
    static func keyLabel(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
             0: "A",  1: "S",  2: "D",  3: "F",  4: "H",  5: "G",  6: "Z",  7: "X",
             8: "C",  9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
            37: "L", 38: "J", 40: "K", 46: "M", 45: "N",
        ]
        return map[keyCode] ?? "key\(keyCode)"
    }
}

// MARK: - F-row key codes (F1–F19)

extension FnShortcut {
    /// Key codes for F1–F19. Binding fn+F-row would steal hardware controls
    /// (volume, brightness), so the recorder rejects these combos.
    public static let fRowKeyCodes: Set<UInt16> = [
        122, 120,  99, 118,  96,  97,  98, 100, 101, 109,
        103, 111, 105, 107, 113, 106,  64,  79,  80,
    ]
}

// MARK: - FnHotkeyMonitor

/// Dispatches `onKeyDown` / `onKeyUp` for fn-based shortcuts.
///
/// Install a shortcut via `setShortcut(_:)`; pass `nil` to tear down the monitor.
/// Requires Accessibility trust (same as paste-at-cursor, SPEC-005).
public final class FnHotkeyMonitor: @unchecked Sendable {
    /// Called on the main thread when the hotkey fires.
    public var onKeyDown: (() -> Void)?
    /// Called on the main thread when the hotkey is released. Used for PTT.
    public var onKeyUp:   (() -> Void)?

    private var globalMonitor: Any?
    private var currentShortcut: FnShortcut?

    // Mutable only on main thread.
    var fnIsDown = false

    public init() {}

    deinit { removeMonitor() }

    public func setShortcut(_ shortcut: FnShortcut?) {
        currentShortcut = shortcut
        if shortcut != nil { installMonitor() } else { removeMonitor() }
    }

    // MARK: - Monitor lifecycle

    private func installMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown]
        ) { [weak self] event in
            // Fires on main thread per Apple docs.
            self?.dispatch(event: event)
        }
    }

    private func removeMonitor() {
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
        fnIsDown = false
    }

    // MARK: - Dispatch (internal for testability)

    func dispatch(event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            dispatchFlagsChanged(nowDown: event.modifierFlags.contains(.function))
        case .keyDown:
            dispatchKeyDown(keyCode: event.keyCode)
        default:
            break
        }
    }

    /// Handles a flags-changed event. `nowDown` = whether fn is currently held.
    func dispatchFlagsChanged(nowDown: Bool) {
        guard let shortcut = currentShortcut else { return }

        if shortcut.keyCode == nil {
            if nowDown && !fnIsDown {
                fnIsDown = true
                onKeyDown?()
            } else if !nowDown && fnIsDown {
                fnIsDown = false
                onKeyUp?()
            }
        } else {
            fnIsDown = nowDown
        }
    }

    /// Handles a key-down event; fires when fn is held and the bound key is pressed.
    func dispatchKeyDown(keyCode: UInt16) {
        guard let shortcut = currentShortcut,
              let kc = shortcut.keyCode,
              fnIsDown,
              keyCode == kc
        else { return }
        onKeyDown?()
    }
}
