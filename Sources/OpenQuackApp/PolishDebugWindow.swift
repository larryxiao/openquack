import AppKit
import SwiftUI
import Combine

/// SPEC-007b — read-only polish debug panel. A movable, non-activating
/// floating window that shows the latest raw→polished pair while the
/// `polishDebug` toggle is on. Never steals focus; never gates paste.
@MainActor
final class PolishDebugWindow {
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    private let state: AppState

    init(state: AppState) {
        self.state = state
        cancellable = state.$lastPolishDebug
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncVisibility() }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Delivered on .main queue but not the @MainActor — hop onto it.
            Task { @MainActor in self?.syncVisibility() }
        }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    private var enabled: Bool { UserDefaults.standard.bool(forKey: "polishDebug") }

    private func syncVisibility() {
        if enabled {
            ensurePanel()
            panel?.orderFront(nil)
        } else {
            panel?.orderOut(nil)
        }
    }

    private func ensurePanel() {
        if panel != nil { return }
        let view = PolishDebugView(state: state)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 240)

        let panel = NSPanel(
            contentRect: host.frame,
            styleMask: [.titled, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Polish debug"
        panel.contentView = host
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - 380, y: v.maxY - 280))
        }
        self.panel = panel
    }
}

// MARK: - SwiftUI view

struct PolishDebugView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusLine)
                .font(.system(size: 11, weight: .medium).monospaced())
                .foregroundStyle(.secondary)
            Divider()
            if let d = state.lastPolishDebug {
                labelled("Raw", d.raw)
                labelled("Polished", d.polished)
            } else {
                Text("Dictate something to see raw vs. polished here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 360, height: 240, alignment: .topLeading)
    }

    @ViewBuilder
    private func labelled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView {
                Text(text).font(.system(size: 12)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 70)
        }
    }

    private var statusLine: String {
        guard let d = state.lastPolishDebug else { return "no polish yet" }
        if d.engineLabel == "off" { return "off · regex only" }
        let secs = d.llmMillis.map { String(format: "%.2fs", Double($0) / 1000) } ?? "?"
        if d.llmSucceeded {
            return "\(d.engineLabel) · LLM ran ✓ · \(secs)"
        }
        return "\(d.engineLabel) · fell back to regex (\(secs)) ⚠"
    }
}
