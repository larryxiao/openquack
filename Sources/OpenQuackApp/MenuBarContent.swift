import SwiftUI
import AppKit
import OpenQuackKit

/// Popover that appears on left-click of the menu-bar duck.
///
/// Minimal hero by design: big quacking-duck mark on the left, live state
/// on the right (status text + level meter when recording + a hint row
/// with the dictation hotkey). Banners (update / accessibility) and the
/// last-transcript card layer in above and below the hero when relevant.
/// App-management actions (Show app, Quit) live in the right-click menu.
struct MenuBarContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s12) {
            updateBanner
            accessibilityBanner
            heroSection
            transcriptSection
        }
        .padding(Theme.s16)
        .frame(width: 340)
    }

    // MARK: - banners

    @ViewBuilder
    private var updateBanner: some View {
        if let update = state.availableUpdate {
            HStack(alignment: .top, spacing: Theme.s8) {
                bounceableArrow(versionKey: update.version)
                VStack(alignment: .leading, spacing: 2) {
                    Text("v\(update.version) is here").font(.caption.weight(.semibold))
                    Text(updateSubtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.s4)
                Button(updateButtonLabel, action: handleUpdateAction)
                    .buttonStyle(.oqPrimarySmall)
            }
            .oqBanner(tint: Theme.moss)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    /// `.symbolEffect(.bounce)` is macOS 14+. Static fallback on Ventura.
    @ViewBuilder
    private func bounceableArrow(versionKey: String) -> some View {
        let icon = Image(systemName: "arrow.down.circle")
            .font(.title3)
            .foregroundStyle(Theme.moss)
        if #available(macOS 14.0, *) {
            icon.symbolEffect(.bounce, value: versionKey)
        } else {
            icon
        }
    }

    private var updateSubtitle: String {
        switch state.installMethod {
        case .homebrew: return "Tap Upgrade — runs `brew upgrade --cask openquack` in Terminal."
        case .manual:   return "Tap Download for the new DMG."
        }
    }

    private var updateButtonLabel: String {
        state.installMethod.isBrew ? "Upgrade" : "Download"
    }

    private func handleUpdateAction() {
        guard let update = state.availableUpdate else { return }
        UpgradeAction.run(release: update, installMethod: state.installMethod)
    }

    @ViewBuilder
    private var accessibilityBanner: some View {
        if !state.accessibilityTrusted {
            HStack(alignment: .top, spacing: Theme.s8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-paste needs Accessibility")
                        .font(.caption.weight(.semibold))
                    Text("Without it, transcripts go to the clipboard and you press ⌘V manually.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.s4)
                Button("Grant") {
                    _ = PasteService.isAccessibilityTrusted(prompt: true)
                    PasteService.openAccessibilitySettings()
                }
                .buttonStyle(.oqPrimarySmall)
            }
            .oqBanner(tint: Theme.amber)
        }
    }

    // MARK: - hero (big duck + live state)

    private var heroSection: some View {
        HStack(alignment: .center, spacing: Theme.s16) {
            QuackingDuck(size: 72)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: Theme.s8) {
                // Status / phase title — fills the visual weight of "OpenQuack".
                HStack(spacing: 6) {
                    Text(statusTitle)
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 0)
                    if case .recording = state.phase {
                        Text(String(format: "%.1fs", state.elapsedSeconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                // State-dependent middle row: meter when recording, progress
                // when transcribing, otherwise nothing.
                stateContent

                Divider().opacity(0.4)

                // Bottom row: hint on left, hotkey glyphs on right.
                HStack(alignment: .center, spacing: Theme.s8) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.s8)
                    Text(HotkeyDisplay.current)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state.phase {
        case .recording:
            PopoverLevelMeter(history: state.levelHistory)
        case .transcribing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Audio stays on your Mac.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        case .warming:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Loading model…")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        default:
            // Idle / ready / starting / error → no extra row; keeps the
            // hero quiet when nothing is actively happening.
            EmptyView()
        }
    }

    // MARK: - transcript (kept below hero when there is one)

    @ViewBuilder
    private var transcriptSection: some View {
        if let transcript = state.lastTranscript, !transcript.isEmpty {
            VStack(alignment: .leading, spacing: Theme.s8) {
                HStack(spacing: Theme.s8) {
                    SectionHeader("Last transcript")
                    Spacer()
                    if let dur = state.lastAudioSeconds, let wall = state.lastWallSeconds {
                        let rtf = dur > 0 ? wall / dur : 0
                        Text(String(format: "%.1fs · %.2f×", dur, rtf))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    CopyTranscriptButton(text: transcript)
                }
                Text(transcript)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .oqCard(padding: Theme.s12)
            }
        }
    }

    // MARK: - phase derivations

    private var statusTitle: String {
        switch state.phase {
        case .warming:                  return "Getting ready"
        case .idle:                     return "Ready"
        case .starting:                 return "Starting…"
        case .recording:                return "Listening…"
        case .transcribing:             return "Thinking…"
        case .ready:
            return state.lastPasted ? "Pasted at cursor" : "On clipboard"
        case .error:                    return "Error"
        }
    }

    /// The hotkey is rendered separately on the right of the bottom row, so
    /// the hint copy never embeds the glyph — keeps the two halves of the
    /// row visually distinct (verb on the left, key on the right).
    private var hint: String {
        switch state.phase {
        case .warming:
            return "First launch downloads ~700 MB. Subsequent launches are offline."
        case .idle:
            return "Press to dictate."
        case .ready:
            if !state.accessibilityTrusted && !state.lastPasted {
                return "Grant Accessibility above to paste at cursor."
            }
            return "Press to dictate again."
        case .starting:
            return "Starting up the mic…"
        case .recording:
            return "Press to finish."
        case .transcribing:
            return "Wait a moment — transcribing locally."
        case .error(let msg):
            return msg
        }
    }
}

// MARK: - Level meter for the popover

/// Wider, ink-toned variant of the recording-overlay level meter so it
/// reads on the popover's translucent material. Same `[Float]` history as
/// the overlay; fade older bars subtly so the right edge feels live.
private struct PopoverLevelMeter: View {
    let history: [Float]

    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 4
    private let maxBarHeight: CGFloat = 22

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(Array(history.enumerated()), id: \.offset) { idx, level in
                Capsule()
                    .fill(Theme.ink.opacity(opacity(at: idx)))
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

    private func opacity(at index: Int) -> Double {
        let total = max(1, history.count - 1)
        let position = Double(index) / Double(total)
        return 0.45 + 0.45 * position
    }
}

// MARK: - Copy-to-clipboard button (SPEC-020)

/// One-click copy of the last transcript. Lives next to the dur·rtf metric
/// in the "Last transcript" section header. Label flips to "Copied" for
/// 1.5s after a tap; tapping again before that resets the timer cleanly.
private struct CopyTranscriptButton: View {
    let text: String
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button(action: handleTap) {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(copied ? "Transcript copied to clipboard" : "Copy transcript to clipboard")
    }

    private func handleTap() {
        PasteService.copyToClipboard(text)
        resetTask?.cancel()
        copied = true
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
