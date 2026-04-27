import SwiftUI
import AppKit
import OpenQuackKit

/// The popover that appears when the user clicks the menu-bar icon. Reads
/// recording / transcription state from `AppState` and renders accordingly.
struct MenuBarContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            statusSection
            transcriptSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - sections

    private var header: some View {
        HStack(spacing: 10) {
            Text("🦆").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenQuack").font(.headline)
                Text("Speak. Have an agent do it. Privately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).font(.caption).foregroundStyle(.primary)
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LAST TRANSCRIPT")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)
                    Spacer()
                    if let dur = state.lastAudioSeconds, let wall = state.lastWallSeconds {
                        let rtf = dur > 0 ? wall / dur : 0
                        Text(String(format: "%.1f s · %.2f× rtf", dur, rtf))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(transcript)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if state.lastTranscript != nil {
                Button("Copy") { PasteService.copyToClipboard(state.lastTranscript ?? "") }
                    .buttonStyle(.borderless).font(.caption)
            }
            if let url = state.lastRecordingURL, FileManager.default.fileExists(atPath: url.path) {
                Button("Listen") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderless).font(.caption)
                    .help("Open the last recording — useful for diagnosing audio vs model issues.")
            }
            if !state.accessibilityTrusted {
                Button("Grant Paste…") {
                    _ = PasteService.isAccessibilityTrusted(prompt: true)
                    PasteService.openAccessibilitySettings()
                }
                .buttonStyle(.borderless).font(.caption)
                .help("Grant Accessibility permission so OpenQuack can paste at cursor automatically.")
            }
            Spacer()
            Button("Settings…") { SettingsWindowController.show() }
                .buttonStyle(.borderless).font(.caption)
                .keyboardShortcut(",", modifiers: .command)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless).font(.caption)
                .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - phase derivations

    private var statusColor: Color {
        switch state.phase {
        case .warming:                  return .yellow
        case .idle, .ready:             return .green
        case .starting, .recording:     return .red
        case .transcribing:             return .orange
        case .error:                    return .gray
        }
    }

    private var statusText: String {
        switch state.phase {
        case .warming(let m):           return "Warming \(m)…"
        case .idle:                     return "Idle — \(state.modelLabel)"
        case .starting:                 return "Starting…"
        case .recording:                return "Recording"
        case .transcribing:             return "Transcribing…"
        case .ready:
            return state.lastPasted ? "Pasted at cursor" : "Copied to clipboard (⌘V to paste)"
        case .error(let msg):           return "Error"
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
                return "Grant Accessibility to enable auto-paste, or press ⌘V to paste manually."
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

    // MARK: - about panel

    private func aboutPanel() {
        let credits = NSAttributedString(
            string: """
            Privacy-first local AI agent interface, accessed via voice.

            Voice never leaves your machine. Default agent does no network IO.
            See docs/VISION.md for the privacy contract.
            """,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 11),
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "OpenQuack",
            .applicationVersion: OpenQuackKit.version,
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
