import SwiftUI
import AppKit
import OpenQuackKit

/// Popover that appears when the user clicks the menu-bar 🦆.
///
/// Composition (top → bottom): update banner → accessibility banner → header
/// → STATUS section → TRANSCRIPT section → footer. Banners hide when not
/// applicable so the cold-open looks calm.
struct MenuBarContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s16) {
            updateBanner
            accessibilityBanner
            header
            statusSection
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
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.moss)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update available — v\(update.version)")
                        .font(.caption.weight(.semibold))
                    Text("Click to download from GitHub Releases.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.s4)
                Button("Get") {
                    NSWorkspace.shared.open(update.dmgURL ?? update.pageURL)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .oqBanner(tint: Theme.moss)
        }
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
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .oqBanner(tint: Theme.amber)
        }
    }

    // MARK: - sections

    private var header: some View {
        HStack(spacing: Theme.s12) {
            Text("🦆").font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenQuack").font(.oqHeadline)
                Text("Speak. Have your Mac do it. Privately.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Theme.s8) {
            SectionHeader("Status")
            HStack(spacing: Theme.s8) {
                StatusDot(phase: state.phase)
                Text(statusText).font(.caption)
                Spacer()
                if case .recording = state.phase {
                    Text(String(format: "%.1f s", state.elapsedSeconds))
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
                    .buttonStyle(.borderless).font(.caption)
            }
            if let url = state.lastRecordingURL, FileManager.default.fileExists(atPath: url.path) {
                Button("Listen") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderless).font(.caption)
                    .help("Open the last recording — useful for diagnosing audio vs model issues.")
            }
            Spacer()
            Button {
                SettingsWindowController.show()
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
        case .warming(let m):           return "Warming \(m)…"
        case .idle:                     return "Idle — \(state.modelLabel)"
        case .starting:                 return "Starting…"
        case .recording:                return "Recording"
        case .transcribing:             return "Transcribing…"
        case .ready:
            return state.lastPasted ? "Pasted at cursor" : "Copied to clipboard (⌘V to paste)"
        case .error:                    return "Error"
        }
    }

    private var hint: String {
        switch state.phase {
        case .warming:
            return "Loading the Whisper model. The first launch downloads ~700 MB; subsequent launches are 5–10 s."
        case .idle:
            return "Press ⌃⇧Space to dictate. Press again to stop."
        case .ready:
            if !state.accessibilityTrusted && !state.lastPasted {
                return "Grant Accessibility (banner above) to enable auto-paste."
            }
            return "Press ⌃⇧Space to dictate. Press again to stop."
        case .starting:
            return "Mic is engaging…"
        case .recording:
            return "Press ⌃⇧Space again to stop and transcribe."
        case .transcribing:
            return "Whisper is processing your audio."
        case .error(let msg):
            return msg
        }
    }
}
