import AppKit
import SwiftUI
import OpenQuackKit

/// SPEC-031 — floating window that surfaces a completed kickoff
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
        let frame = NSRect(x: 0, y: 0, width: 540, height: 420)
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
    @State private var continueError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                promptBlock
                Divider()
                responseBlock
                Spacer(minLength: 8)
                if let continueError {
                    Text(continueError)
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
            Image(systemName: result.succeeded ? "sparkles" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.succeeded ? .yellow : .red)
            Text(result.succeeded
                 ? "claude finished"
                 : "claude failed — exit \(result.exitCode)")
                .font(.headline)
            Spacer()
            Text(String(format: "%.1fs", result.durationSeconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
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
            Text(result.succeeded ? "Response:" : "Error output:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(result.succeeded ? result.response : result.stderr)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
            .frame(maxHeight: 220)
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    result.succeeded ? result.response : result.stderr,
                    forType: .string
                )
                copiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copiedFeedback = false
                }
            } label: {
                Label(copiedFeedback ? "Copied" : "Copy response",
                      systemImage: copiedFeedback ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {
                openInTerminal()
            } label: {
                Label("Continue in Terminal", systemImage: "terminal")
            }
            .buttonStyle(.bordered)
            .help("Open Terminal with `claude --resume \(result.sessionId.uuidString.lowercased().prefix(8))…` to keep working on this session.")

            Spacer()

            Button("Close") {
                // The window is owned by ResponseWindowController; the
                // simplest "close" is to ask the window the view is in.
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private func openInTerminal() {
        do {
            try AgentKickoffService.continueInTerminal(
                sessionID: result.sessionId,
                workspace: result.workspace
            )
            continueError = nil
        } catch {
            continueError = "Couldn't open Terminal: \(error)"
        }
    }
}
