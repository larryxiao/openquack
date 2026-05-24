import AppKit
import SwiftUI
import OpenQuackKit

/// SPEC-031 v3 — floating window that surfaces a completed kickoff
/// result. Opened by the notification click handler (or, when
/// notifications are denied, by clicking the menu-bar duck).
@MainActor
final class ResponseWindowController {
    private var window: NSWindow?

    func show(result: KickoffResult) {
        if let existing = window {
            existing.contentView = NSHostingView(rootView: ResponseView(result: result))
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = ResponseView(result: result)
        let host = NSHostingView(rootView: view)
        let frame = NSRect(x: 0, y: 0, width: 560, height: 460)
        host.frame = frame

        let w = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.contentView = host
        w.title = "claude — kickoff result"
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}

private struct ResponseView: View {
    let result: KickoffResult

    @State private var copiedFeedback: Bool = false
    @State private var actionError: String?
    @State private var stopped: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                promptBlock
                Divider()
                responseBlock
                Spacer(minLength: 8)
                if let actionError {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                buttonRow
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerIcon)
                .foregroundStyle(headerTint)
            Text(headerTitle)
                .font(.headline)
            Spacer()
            Text("\(String(format: "%.1fs", result.durationSeconds)) · \(result.shortID)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var headerIcon: String {
        if stopped { return "stop.circle.fill" }
        switch result.state {
        case .done, .idle: return "sparkles"
        case .blocked:     return "questionmark.circle.fill"
        case .working:     return "ellipsis.circle"
        case .unknown:     return "exclamationmark.triangle"
        }
    }

    private var headerTint: Color {
        if stopped { return .secondary }
        switch result.state {
        case .done, .idle: return .yellow
        case .blocked:     return .orange
        case .working:     return .secondary
        case .unknown:     return .red
        }
    }

    private var headerTitle: String {
        if stopped { return "Session stopped" }
        switch result.state {
        case .done, .idle: return "claude finished"
        case .blocked:     return "claude needs input"
        case .working:     return "claude working…"
        case .unknown:     return "claude state unknown"
        }
    }

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You said:").font(.caption).foregroundStyle(.secondary)
            Text("\u{201C}\(result.prompt)\u{201D}")
                .font(.body)
                .italic()
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var responseBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(responseLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(responseBody)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
            .frame(maxHeight: 260)
        }
    }

    private var responseLabel: String {
        switch result.state {
        case .blocked: return "Agent needs:"
        case .done, .idle: return "Response:"
        default: return "Last update:"
        }
    }

    private var responseBody: String {
        if result.state == .blocked, let needs = result.needs, !needs.isEmpty {
            return needs
        }
        if let output = result.output, !output.isEmpty {
            return output
        }
        if let detail = result.detail, !detail.isEmpty {
            return detail
        }
        return "(no response captured)"
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(responseBody, forType: .string)
                copiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copiedFeedback = false
                }
            } label: {
                Label(copiedFeedback ? "Copied" : "Copy",
                      systemImage: copiedFeedback ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {
                attempt {
                    try AgentKickoffService.continueInTerminal(
                        shortID: result.shortID,
                        workspace: result.workspace
                    )
                }
            } label: {
                Label("Continue in Terminal", systemImage: "terminal")
            }
            .buttonStyle(.bordered)
            .help("Opens Terminal with `claude attach \(result.shortID)` — drops into the live daemon-owned session.")

            Button {
                attempt {
                    try AgentKickoffService.showAgentsTUI()
                }
            } label: {
                Label("All kickoffs", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.bordered)
            .help("Opens Terminal with `claude agents` — full TUI of every live background session.")

            if !stopped, result.state != .done, result.state != .idle {
                Button(role: .destructive) {
                    attempt {
                        try AgentKickoffService.stopSession(shortID: result.shortID)
                        stopped = true
                    }
                } label: {
                    Label("Stop", systemImage: "stop")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Close") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private func attempt(_ block: () throws -> Void) {
        do {
            try block()
            actionError = nil
        } catch {
            actionError = "\(error)"
        }
    }
}
