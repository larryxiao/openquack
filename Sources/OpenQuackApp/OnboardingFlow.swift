import SwiftUI
import AppKit
import AVFoundation
import Combine
import KeyboardShortcuts
import OpenQuackKit

// First-launch onboarding flow. Five steps, one polled state model, dismisses
// itself once the user finishes (or hits Skip). Persisted via UserDefaults
// so subsequent launches go straight to the menu bar.

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case accessibility
    case hotkey
    case done
}

@MainActor
final class OnboardingState: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published var micStatus: AVAuthorizationStatus = .notDetermined
    @Published var accessibilityTrusted: Bool = false

    private var timer: Timer?

    init() {
        refresh()
        // Poll because AVAuthorizationStatus and AXIsProcessTrusted don't push notifications.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityTrusted = AXIsProcessTrusted()
    }

    func advance() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    func complete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}

// MARK: - root view

struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .padding(.vertical, 32)
                .transition(.opacity)

            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 540, height: 500)
        .background(WindowBackground())
    }

    @ViewBuilder
    private var stepBody: some View {
        switch state.step {
        case .welcome:        WelcomeStep()
        case .microphone:     MicrophoneStep(state: state)
        case .accessibility:  AccessibilityStep(state: state)
        case .hotkey:         HotkeyStep()
        case .done:           DoneStep()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            stepIndicator
            Spacer()
            if state.step != .done {
                Button("Skip") {
                    state.complete()
                    onClose()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            Button(state.step == .done ? "Done" : "Continue") {
                if state.step == .done {
                    state.complete()
                    onClose()
                } else {
                    state.advance()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= state.step.rawValue
                          ? Color.primary.opacity(0.85)
                          : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("🦆").font(.system(size: 96))
            Text("Welcome to OpenQuack").font(.title.weight(.semibold))
            Text("Speak. Have an agent do it. Privately.")
                .font(.title3).foregroundStyle(.secondary)
            Spacer().frame(height: 16)
            Text("OpenQuack runs Whisper locally on your Mac. Your voice never leaves the machine. We'll grant two permissions next, pick a hotkey, and you'll be dictating in under a minute.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Spacer()
        }
    }
}

private struct MicrophoneStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 72)).foregroundStyle(.tint)
            Text("Microphone").font(.title.weight(.semibold))
            Text("OpenQuack needs to listen to your microphone to transcribe what you say. Audio stays on your Mac — we don't send it anywhere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Spacer().frame(height: 16)
            statusBlock
            Spacer()
        }
    }

    @ViewBuilder
    private var statusBlock: some View {
        switch state.micStatus {
        case .authorized:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(.green)
        case .denied, .restricted:
            VStack(spacing: 8) {
                Label("Denied — change in System Settings", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    )!)
                }
            }
        case .notDetermined:
            Button("Grant microphone access") {
                Task {
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                    state.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
        @unknown default:
            EmptyView()
        }
    }
}

private struct AccessibilityStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "command.circle.fill")
                .font(.system(size: 72)).foregroundStyle(.tint)
            Text("Auto-paste").font(.title.weight(.semibold))
            Text("To paste your transcript at the cursor, OpenQuack simulates ⌘V. macOS calls this Accessibility access — without it the text still goes to your clipboard, you just press ⌘V manually.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            Spacer().frame(height: 16)

            if state.accessibilityTrusted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                VStack(spacing: 6) {
                    Button("Grant Accessibility access") {
                        _ = PasteService.isAccessibilityTrusted(prompt: true)
                        PasteService.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    Text("You can skip this — it's reversible from Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

private struct HotkeyStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 72)).foregroundStyle(.tint)
            Text("Pick your hotkey").font(.title.weight(.semibold))
            Text("Press it once to start dictating, again to stop. The default ⌃⇧Space works almost everywhere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Spacer().frame(height: 16)
            KeyboardShortcuts.Recorder("Toggle dictation:", name: .toggleRecording)
            Spacer()
        }
    }
}

private struct DoneStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72)).foregroundStyle(.green)
            Text("You're all set").font(.title.weight(.semibold))
            Text("Try it now: press your hotkey, say something, press it again. The transcript will paste at your cursor.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            Spacer().frame(height: 12)
            VStack(alignment: .leading, spacing: 10) {
                tipRow(symbol: "command",
                       text: "Click the duck in your menu bar to view the last transcript or open Settings.")
                tipRow(symbol: "lock.shield",
                       text: "Audio never leaves your Mac. The default backend does no network IO.")
            }
            .frame(maxWidth: 400)
            Spacer()
        }
    }

    private func tipRow(symbol: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

// MARK: - window background

private struct WindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - window controller

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: OnboardingWindowController?
    private let state = OnboardingState()

    /// Show the onboarding window only if the user hasn't completed it before.
    /// Hooked from AppDelegate.applicationDidFinishLaunching.
    static func showIfFirstLaunch() {
        let done = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !done { show() }
    }

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = OnboardingWindowController()
        shared = controller
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        // Build view + window first, then super.init.
        let stateRef = OnboardingState()  // placeholder — replaced via assignment below
        let host = NSHostingController(rootView: OnboardingView(state: stateRef, onClose: {}))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentViewController = host
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        // Now wire the view to *this* controller's state and a real onClose.
        let view = OnboardingView(state: self.state) { [weak self] in
            self?.close()
        }
        host.rootView = view
        _ = stateRef  // silence unused warning; placeholder discarded
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func windowWillClose(_ notification: Notification) {
        state.complete()  // hitting the close button counts as completing
        Self.shared = nil
    }
}
