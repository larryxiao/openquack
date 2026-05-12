import SwiftUI
import AppKit
import KeyboardShortcuts
import OpenQuackKit

// SPEC-003a — Recorder UI that captures fn / Globe key presses.
//
// KeyboardShortcuts.Recorder is backed by Carbon and silently ignores fn.
// This wrapper installs a local NSEvent monitor for .flagsChanged while the
// view is visible. On fn-down the monitor intercepts the event (returns nil
// so Carbon never sees it) and enters an "awaiting combo" state: if fn is
// released within 600 ms without another key, we commit bare fn; if a
// printable key is pressed while fn is held, we commit fn+key.
//
// Mutual exclusion: committing an FnShortcut clears the KeyboardShortcuts
// binding; picking a Carbon shortcut clears FnShortcut.stored.
//
// This view is added in PR-A (infrastructure) but not wired into the UI
// until PR-B replaces the bare KeyboardShortcuts.Recorder calls in
// OnboardingFlow.swift and SettingsView.swift.

struct FnAwareShortcutRecorder: View {

    // MARK: - Capture state

    enum CaptureState: Equatable {
        case idle
        /// fn is currently held; waiting for a key or release.
        case awaitingCombo(fnDownAt: Date)

        static func == (lhs: CaptureState, rhs: CaptureState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.awaitingCombo(let a), .awaitingCombo(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: - State

    @State private var fnShortcut: FnShortcut? = FnShortcut.stored
    @State private var captureState: CaptureState = .idle
    @State private var showCollisionHint = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Hotkey:")
                    .frame(width: 60, alignment: .trailing)

                switch captureState {
                case .awaitingCombo:
                    awaitingComboDisplay
                case .idle:
                    if let shortcut = fnShortcut {
                        fnShortcutDisplay(shortcut)
                    } else {
                        carbonRecorder
                    }
                }
            }

            if showCollisionHint {
                collisionHint
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showCollisionHint)
        .background(
            MonitorInstallerView(
                captureState: $captureState,
                fnShortcut: $fnShortcut,
                showCollisionHint: $showCollisionHint
            )
            .frame(width: 0, height: 0)
        )
    }

    // MARK: - Sub-views

    private func fnShortcutDisplay(_ shortcut: FnShortcut) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.caption2)
                if let kc = shortcut.keyCode {
                    Text("+ key \(kc)")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(shortcutChipBackground)

            Button {
                FnShortcut.clear()
                fnShortcut = nil
                showCollisionHint = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private var awaitingComboDisplay: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.caption2)
            Text("+ key… (press a key or release for bare fn)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var carbonRecorder: some View {
        KeyboardShortcuts.Recorder("", name: .toggleRecording)
            .onChange(of: KeyboardShortcuts.getShortcut(for: .toggleRecording)) { _ in
                FnShortcut.clear()
                fnShortcut = nil
                showCollisionHint = false
            }
    }

    private var collisionHint: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("macOS may also do something when you press 🌐 — check **System Settings → Keyboard → Press 🌐 to** and set it to *Do Nothing* if you see double behaviour.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                withAnimation { showCollisionHint = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 68)
    }

    private var shortcutChipBackground: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
    }
}

// MARK: - NSViewRepresentable monitor shim

/// Manages the local NSEvent monitor lifecycle alongside the SwiftUI view.
/// NSViewRepresentables are torn down when the view leaves the hierarchy,
/// making them a clean home for AppKit object lifecycles in SwiftUI.
private struct MonitorInstallerView: NSViewRepresentable {
    @Binding var captureState: FnAwareShortcutRecorder.CaptureState
    @Binding var fnShortcut: FnShortcut?
    @Binding var showCollisionHint: Bool

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            captureState: $captureState,
            fnShortcut: $fnShortcut,
            showCollisionHint: $showCollisionHint
        )
    }

    // MARK: - Coordinator

    final class Coordinator {
        private var monitor: Any?
        private let captureState: Binding<FnAwareShortcutRecorder.CaptureState>
        private let fnShortcut: Binding<FnShortcut?>
        private let showCollisionHint: Binding<Bool>

        init(
            captureState: Binding<FnAwareShortcutRecorder.CaptureState>,
            fnShortcut: Binding<FnShortcut?>,
            showCollisionHint: Binding<Bool>
        ) {
            self.captureState      = captureState
            self.fnShortcut        = fnShortcut
            self.showCollisionHint = showCollisionHint
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.flagsChanged, .keyDown]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func remove() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            switch event.type {
            case .flagsChanged: return handleFlagsChanged(event)
            case .keyDown:      return handleKeyDown(event)
            default:            return event
            }
        }

        private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
            let fnDown = event.modifierFlags.contains(.function)

            if fnDown {
                captureState.wrappedValue = .awaitingCombo(fnDownAt: Date())
                return nil
            }

            if case .awaitingCombo(let downAt) = captureState.wrappedValue {
                captureState.wrappedValue = .idle
                if Date().timeIntervalSince(downAt) < 0.6 {
                    commit(FnShortcut(keyCode: nil))
                }
                return nil
            }

            return event
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard case .awaitingCombo = captureState.wrappedValue else {
                return event
            }

            let kc = event.keyCode
            captureState.wrappedValue = .idle

            if !FnShortcut.fRowKeyCodes.contains(kc) {
                commit(FnShortcut(keyCode: kc))
            }
            return nil
        }

        private func commit(_ shortcut: FnShortcut) {
            shortcut.save()
            fnShortcut.wrappedValue = shortcut
            KeyboardShortcuts.reset(.toggleRecording)
            if shortcut.keyCode == nil {
                showCollisionHint.wrappedValue = true
            }
        }
    }
}
