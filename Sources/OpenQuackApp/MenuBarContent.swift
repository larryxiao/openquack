import SwiftUI
import AppKit
import OpenQuackKit

/// Popover that appears when the user clicks the menu-bar duck.
///
/// Composition (top → bottom): update banner → accessibility banner → hero
/// (duck + live status + hint) → transcript → footer. Header and status
/// are merged into a single hero block so the popover reads "what is the
/// duck doing right now" first, brand identity second.
struct MenuBarContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s16) {
            updateBanner
            accessibilityBanner
            heroSection
            transcriptSection
            footer
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

    /// Subtitle copy adapts to the install method — brew users get a
    /// shell command they can paste; manual users get a download note.
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

    // MARK: - hero (brand + live status + hint)

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: Theme.s8) {
            // Brand row: duck + name + tagline.
            HStack(alignment: .center, spacing: Theme.s12) {
                QuackingDuck(size: 36)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OpenQuack").font(.oqHeadline)
                    Text("Speak. Send. Privately.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Status row: dot + live phase text + (recording elapsed).
            HStack(spacing: 6) {
                StatusDot(phase: state.phase)
                Text(statusText)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                if case .recording = state.phase {
                    Text(String(format: "%.1fs", state.elapsedSeconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var transcriptSection: some View {
        if let transcript = state.lastTranscript, !transcript.isEmpty {
            VStack(alignment: .leading, spacing: Theme.s8) {
                HStack {
                    SectionHeader("Last transcript")
                    Spacer()
                    if let dur = state.lastAudioSeconds, let wall = state.lastWallSeconds {
                        let rtf = dur > 0 ? wall / dur : 0
                        Text(String(format: "%.1fs · %.2f×", dur, rtf))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(transcript)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .oqCard(padding: Theme.s12)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.s12) {
            if state.lastTranscript != nil {
                Button("Copy") { PasteService.copyToClipboard(state.lastTranscript ?? "") }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Spacer()
            Button {
                SettingsWindowController.show(appState: state)
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.medium))
            .keyboardShortcut(",", modifiers: .command)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - phase derivations

    private var statusText: String {
        switch state.phase {
        case .warming:                  return "Getting ready…"
        case .idle:                     return "Ready"
        case .starting:                 return "Starting…"
        case .recording:                return "Listening"
        case .transcribing:             return "Thinking…"
        case .ready:
            return state.lastPasted ? "Pasted at cursor" : "On clipboard — press ⌘V to paste"
        case .error:                    return "Error"
        }
    }

    private var hint: String {
        let hk = HotkeyDisplay.current
        switch state.phase {
        case .warming:
            return "First launch downloads about 700 MB. After that, every launch is offline and takes 5–10 s."
        case .idle:
            return "Press \(hk) to dictate."
        case .ready:
            if !state.accessibilityTrusted && !state.lastPasted {
                return "Grant Accessibility above to paste at cursor automatically."
            }
            return "Press \(hk) to dictate."
        case .starting:
            return "Starting up the mic…"
        case .recording:
            return "Press \(hk) to finish."
        case .transcribing:
            return "Thinking — your audio stays on your Mac."
        case .error(let msg):
            return msg
        }
    }
}
