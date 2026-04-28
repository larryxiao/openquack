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
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 60)

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
                .frame(minWidth: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.oqHeadline)
                sublineView
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.s16)
        .padding(.vertical, Theme.s12)
        .frame(width: 320, height: 60)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rFloating, style: .continuous))
    }

    @ViewBuilder
    private var indicator: some View {
        switch state.phase {
        case .recording:
            VoiceLevel(history: state.levelHistory)
        case .transcribing:
            Image(systemName: "waveform.circle")
                .font(.body)
                .foregroundStyle(Theme.amber)
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

    @ViewBuilder
    private var sublineView: some View {
        switch state.phase {
        case .transcribing:
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: state.transcriptionProgress)
                    .progressViewStyle(.linear)
                    .tint(Theme.amber)
                    .animation(.easeOut(duration: 0.25), value: state.transcriptionProgress)
                Text(transcribingSubline)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        default:
            Text(plainSubline)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var headline: String {
        switch state.phase {
        case .recording:    return "Recording"
        case .transcribing: return "Thinking"
        case .ready:        return state.lastPasted ? "Pasted at cursor" : "Copied to clipboard"
        default:            return "OpenQuack"
        }
    }

    private var transcribingSubline: String {
        let pct = Int((state.transcriptionProgress * 100).rounded())
        // Clamp at 99% until we actually hit done (the observed Progress
        // sometimes lags one tick behind completion).
        let clamped = pct >= 100 ? 99 : pct
        return "\(clamped)% · \(state.modelLabel)"
    }

    private var plainSubline: String {
        switch state.phase {
        case .recording:
            let secs = String(format: "%.1f", state.elapsedSeconds)
            return "\(secs)s · \(HotkeyDisplay.current) to stop"
        case .ready:
            return state.lastTranscript.map { String($0.prefix(48)) } ?? ""
        default:
            return ""
        }
    }
}

/// Sliding-window waveform-style level meter. Each bar represents a slice
/// of recent audio (newest on the right), so the meter actually reads as
/// "voice activity over time" rather than all bars pulsing in lockstep.
/// Coral fill at full strength on the latest bar, fading slightly toward
/// the older edge for a sense of motion.
private struct VoiceLevel: View {
    let history: [Float]

    private let barWidth: CGFloat = 3.5
    private let barSpacing: CGFloat = 2.5
    private let maxBarHeight: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(Array(history.enumerated()), id: \.offset) { idx, level in
                Capsule()
                    .fill(Theme.coral.opacity(opacity(at: idx)))
                    .frame(width: barWidth, height: barHeight(level))
                    .animation(.easeOut(duration: 0.10), value: level)
            }
        }
        .frame(height: maxBarHeight)
    }

    private func barHeight(_ level: Float) -> CGFloat {
        let scaled = CGFloat(level) * maxBarHeight
        return max(3, min(maxBarHeight, scaled))
    }

    /// Fade older bars (left) slightly so the rightmost (newest) reads as the
    /// "live" edge of the waveform.
    private func opacity(at index: Int) -> Double {
        let total = max(1, history.count - 1)
        let position = Double(index) / Double(total)  // 0 = oldest, 1 = newest
        return 0.55 + 0.45 * position  // older bars at 0.55, newest at 1.0
    }
}
