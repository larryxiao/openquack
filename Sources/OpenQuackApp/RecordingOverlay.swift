import AppKit
import SwiftUI
import Combine
import OpenQuackKit

/// SPEC-004 — floating recording overlay.
///
/// A small pill near the top of the screen that surfaces recording / transcribing
/// state independently of the menu-bar icon. Click-through (mouse events pass
/// through to whatever app the user is dictating into).
///
/// Lifecycle is driven entirely by `AppState.phase` via Combine; we never call
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
            // Brief lingering "done" state, then hide.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
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
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 52)

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
        // Sit just below the menu bar (~24 pt gap).
        let y = visible.maxY - panel.frame.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func showAnimated() {
        guard let panel else { return }
        if panel.isVisible && panel.alphaValue > 0.95 { return }
        positionTopCentre(panel: panel)  // re-anchor in case display config changed
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
        HStack(spacing: 12) {
            indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 13, weight: .semibold))
                Text(subline).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 240, height: 52)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        switch state.phase {
        case .recording:
            VoiceLevel(level: state.currentLevel)
        case .transcribing:
            ProgressView().controlSize(.small)
        default:
            Image(systemName: "mic").font(.system(size: 14))
        }
    }

    private var headline: String {
        switch state.phase {
        case .recording:    return "Recording"
        case .transcribing: return "Transcribing"
        case .ready:        return state.lastPasted ? "Pasted" : "Copied"
        default:            return "OpenQuack"
        }
    }

    private var subline: String {
        switch state.phase {
        case .recording:    return String(format: "%.1fs · ⌃⇧Space to stop", state.elapsedSeconds)
        case .transcribing: return state.modelLabel
        case .ready:        return state.lastTranscript.map { String($0.prefix(40)) } ?? ""
        default:            return ""
        }
    }
}

private struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .scaleEffect(pulse ? 1.15 : 0.85)
            .opacity(pulse ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

/// 5-bar equaliser-style level meter. Bars centred around tallest in the middle,
/// height scales with the live level. Cheap and reads as "voice activity".
private struct VoiceLevel: View {
    let level: Float
    private let multipliers: [CGFloat] = [0.45, 0.75, 1.0, 0.75, 0.45]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Color.red.opacity(0.85))
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
