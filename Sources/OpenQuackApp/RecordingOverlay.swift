import AppKit
import SwiftUI
import Combine
import OpenQuackKit

/// SPEC-004 — floating recording overlay.
///
/// A small pill near the top of the screen surfacing recording / transcribing
/// state independently of the menu-bar icon. Click-through; never steals focus.
/// Lifecycle is driven by `AppState.phase` via Combine — we never call
/// show/hide directly from the orchestrator.
@MainActor
final class RecordingOverlay {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayPill>?
    private var cancellable: AnyCancellable?
    private let state: AppState

    init(state: AppState) {
        self.state = state
        cancellable = state.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.handle(phase: phase)
            }
    }

    private func handle(phase: AppState.Phase) {
        switch phase {
        case .recording, .transcribing:
            ensurePanel()
            showAnimated()
        case .ready:
            // Linger briefly so the user sees the "Pasted" / "Copied" state.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                if case .ready = self?.state.phase {
                    self?.hideAnimated()
                }
            }
        case .idle, .warming, .starting, .error:
            hideAnimated()
        }
    }

    private func ensurePanel() {
        if panel != nil { return }

        let pill = OverlayPill(state: state)
        let host = NSHostingView(rootView: pill)
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 56)

        let panel = NSPanel(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        positionTopCentre(panel: panel)

        self.panel = panel
        self.hostingView = host
    }

    private func positionTopCentre(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - panel.frame.width / 2
        let y = visible.maxY - panel.frame.height - Theme.s24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func showAnimated() {
        guard let panel else { return }
        if panel.isVisible && panel.alphaValue > 0.95 { return }
        positionTopCentre(panel: panel)
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hideAnimated() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }
}

// MARK: - SwiftUI pill

struct OverlayPill: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: Theme.s12) {
            indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.oqHeadline)
                Text(subline).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.s16)
        .padding(.vertical, Theme.s12)
        .frame(width: 280, height: 56)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rFloating, style: .continuous))
    }

    @ViewBuilder
    private var indicator: some View {
        switch state.phase {
        case .recording:
            VoiceLevel(level: state.currentLevel)
        case .transcribing:
            ProgressView().controlSize(.small)
        case .ready:
            Image(systemName: state.lastPasted ? "checkmark.circle.fill" : "doc.on.clipboard")
                .font(.body)
                .foregroundStyle(Theme.moss)
        default:
            Image(systemName: "mic")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var headline: String {
        switch state.phase {
        case .recording:    return "Recording"
        case .transcribing: return "Transcribing"
        case .ready:        return state.lastPasted ? "Pasted at cursor" : "Copied to clipboard"
        default:            return "OpenQuack"
        }
    }

    private var subline: String {
        switch state.phase {
        case .recording:
            let secs = String(format: "%.1f", state.elapsedSeconds)
            return "\(secs)s · ⌃⇧Space to stop"
        case .transcribing:
            return state.modelLabel
        case .ready:
            return state.lastTranscript.map { String($0.prefix(48)) } ?? ""
        default:
            return ""
        }
    }
}

/// 5-bar equaliser-style level meter. Outer bars at 0.6×, centre at 1.0× —
/// reads as friendly "voice activity" rather than alarm chrome. Coral fill
/// (Theme.coral) instead of saturated red.
private struct VoiceLevel: View {
    let level: Float
    private let multipliers: [CGFloat] = [0.45, 0.75, 1.0, 0.75, 0.45]
    private let opacities: [Double]    = [0.6, 0.85, 1.0, 0.85, 0.6]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Theme.coral.opacity(opacities[i]))
                    .frame(width: 3, height: barHeight(i))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(width: 24, height: 22)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let scaled = max(2, CGFloat(level) * 22 * multipliers[i])
        return min(22, scaled)
    }
}
