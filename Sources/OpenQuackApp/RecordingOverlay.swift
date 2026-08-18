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
        case .recording, .transcribing, .polishing:
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
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - panel.frame.width / 2
        let y = visible.maxY - panel.frame.height - Theme.s24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func showAnimated() {
        guard let panel else { return }
        if panel.isVisible && panel.alphaValue > 0.95 { return }
        positionTopCentre(panel: panel)
        // `orderFrontRegardless` (not `orderFront`): we're a background accessory
        // app, so this surfaces the pill onto the currently active Space —
        // including another app's fullscreen Space — without stealing focus.
        panel.orderFrontRegardless()
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
            // Both chips can coexist: a kickoff recording with a remote
            // backend uploads audio *and* routes the transcript to claude —
            // each network hop gets disclosed.
            if state.recordingMode == .agentKickoff,
               case .recording = state.phase {
                modeChip
            }
            if showsRemoteChip {
                remoteChip
            }
        }
        .padding(.horizontal, Theme.s16)
        .padding(.vertical, Theme.s12)
        .frame(width: 320, height: 60)
        .background {
            // Thinking-phase progress is rendered as a quiet amber wash
            // filling left → right behind the material, instead of a
            // labelled bar with percentages. Reads as ambient motion, not
            // a counter. Other phases just show the material.
            ZStack(alignment: .leading) {
                Rectangle().fill(.ultraThinMaterial)
                if case .transcribing = state.phase {
                    Rectangle()
                        .fill(Theme.amber.opacity(0.22))
                        .frame(width: 320 * CGFloat(state.transcriptionProgress))
                        .animation(.easeOut(duration: 0.20), value: state.transcriptionProgress)
                }
            }
        }
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
        case .polishing:
            PolishingIndicator()
        case .ready:
            if state.recordingMode == .agentKickoff {
                Image(systemName: state.lastKickoffSucceeded
                      ? "sparkles"
                      : "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(state.lastKickoffSucceeded
                                     ? Theme.amber
                                     : Theme.coral)
            } else {
                Image(systemName: state.lastPasted ? "checkmark.circle.fill" : "doc.on.clipboard")
                    .font(.body)
                    .foregroundStyle(Theme.moss)
            }
        default:
            Image(systemName: "mic")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    /// SPEC-031 mode chip — shown only during a kickoff-mode recording.
    /// Doubles as the privacy contract's required network indicator
    /// (the globe icon).
    private var modeChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.caption2)
            Text("claude")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.amber.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Theme.amber.opacity(0.35), lineWidth: 1)
                )
        )
    }

    /// SPEC-044 — the privacy contract's network indicator for remote
    /// transcription: visible the whole time audio destined for the wire is
    /// being captured or sent.
    private var showsRemoteChip: Bool {
        guard state.remoteHost != nil else { return false }
        switch state.phase {
        case .recording, .transcribing: return true
        default: return false
        }
    }

    private var remoteChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.caption2)
            Text("remote")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.amber.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Theme.amber.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var sublineView: some View {
        Text(plainSubline)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private var headline: String {
        switch state.phase {
        case .recording:
            return state.recordingMode == .agentKickoff ? "Listening (kickoff)" : "Listening"
        case .transcribing: return "Thinking"
        case .polishing:    return "Polishing"
        case .ready:
            if state.recordingMode == .agentKickoff {
                return state.lastKickoffSucceeded ? "Launched claude" : "Kickoff failed"
            }
            return state.lastPasted ? "Pasted at cursor" : "Copied to clipboard"
        default:            return "OpenQuack"
        }
    }

    private var plainSubline: String {
        switch state.phase {
        case .recording:
            let secs = String(format: "%.1f", state.elapsedSeconds)
            return "\(secs)s · press to stop"
        case .transcribing:
            // SPEC-044 — never claim "On your Mac" when audio is being sent
            // to a configured remote endpoint.
            if let host = state.remoteHost { return "via \(host)" }
            return "On your Mac"
        case .polishing:
            return "On your Mac"
        case .ready:
            // SPEC-036 — surface an interruption notice over the usual subline.
            if let notice = state.lastNotice { return notice }
            if state.recordingMode == .agentKickoff, !state.lastKickoffSucceeded {
                return state.lastKickoffError ?? "Transcript copied to clipboard"
            }
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

/// A gently pulsing amber wand — the "Polishing" overlay indicator.
/// `sparkles` is intentionally avoided (it marks kickoff success).
private struct PolishingIndicator: View {
    @State private var pulse = false
    var body: some View {
        Image(systemName: "wand.and.rays")
            .font(.body)
            .foregroundStyle(Theme.amber)
            .opacity(pulse ? 1.0 : 0.4)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
