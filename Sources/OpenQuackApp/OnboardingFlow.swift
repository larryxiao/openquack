import SwiftUI
import AppKit
import AVFoundation
import Combine
import KeyboardShortcuts
import OpenQuackKit

// First-launch onboarding flow. Reflowed to lead with the privacy pitch, run
// the model download in the background so the user isn't staring at a static
// progress bar, and end with a live dictation demo that proves it all works.
//
// Sequence:
//   welcome → microphone → accessibility → hotkey → install → demo → done
//
// The model download starts as soon as the window opens, in parallel with the
// permission steps; by the time the user reaches `install`, it's typically
// already complete. AppDelegate defers its warmTranscriber call until
// onboarding closes so there's no concurrent re-download.

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case accessibility
    case hotkey
    case install
    case demo
    case done
}

@MainActor
final class OnboardingState: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published var micStatus: AVAuthorizationStatus = .notDetermined
    @Published var accessibilityTrusted: Bool = false
    @Published var modelProgress: Double = 0      // 0…1, real WhisperKit progress
    @Published var modelDownloaded: Bool = false
    @Published var modelError: String? = nil
    @Published var demoTranscript: String = ""

    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?

    init(appState: AppState) {
        self.appState = appState
        refreshPermissions()

        // Mirror the most recent transcript into the demo textbox so the user
        // sees their dictation appear even if the focused field is something
        // else when paste lands.
        appState.$lastTranscript
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                guard let self else { return }
                if case .demo = self.step {
                    self.demoTranscript = transcript
                }
            }
            .store(in: &cancellables)

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }

        startModelDownload()
    }

    deinit { permissionTimer?.invalidate() }

    func refreshPermissions() {
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

    private func startModelDownload() {
        let model = UserDefaults.standard.string(forKey: "model") ?? "medium"
        Task { [weak self] in
            do {
                try await WhisperKitEngine.ensureDownloaded(model: model) { fraction in
                    Task { @MainActor in self?.modelProgress = fraction }
                }
                await MainActor.run {
                    self?.modelProgress = 1.0
                    self?.modelDownloaded = true
                }
            } catch {
                await MainActor.run {
                    self?.modelError = "Download failed: \(error.localizedDescription)"
                }
            }
        }
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
                .animation(.easeInOut(duration: 0.18), value: state.step)

            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 580, height: 560)
        .background(WindowBackground())
    }

    @ViewBuilder
    private var stepBody: some View {
        switch state.step {
        case .welcome:        WelcomeStep()
        case .microphone:     MicrophoneStep(state: state)
        case .accessibility:  AccessibilityStep(state: state)
        case .hotkey:         HotkeyStep()
        case .install:        InstallStep(state: state)
        case .demo:           DemoStep(state: state)
        case .done:           DoneStep()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            stepIndicator
            modelChip  // global download status visible across every step
            Spacer()
            if state.step != .done {
                Button("Skip") {
                    state.complete()
                    onClose()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            Button(continueLabel) {
                if state.step == .done {
                    state.complete()
                    onClose()
                } else {
                    state.advance()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(continueDisabled)
        }
    }

    private var continueLabel: String {
        switch state.step {
        case .install where !state.modelDownloaded: return "Waiting…"
        case .done:                                  return "Done"
        default:                                     return "Continue"
        }
    }

    private var continueDisabled: Bool {
        switch state.step {
        case .install: return !state.modelDownloaded && state.modelError == nil
        default:       return false
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

    @ViewBuilder
    private var modelChip: some View {
        if !state.modelDownloaded && state.modelError == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Whisper \(Int(state.modelProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else if state.modelDownloaded {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Whisper ready").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("🦆").font(.system(size: 92))
            Text("Welcome to OpenQuack").font(.title.weight(.semibold))
            Text("Speak. Have your Mac do it. Privately.")
                .font(.title3).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                pillRow(
                    icon: "lock.shield.fill",
                    title: "Local-only by design",
                    body: "Audio never leaves your Mac. No cloud, no signup, no telemetry."
                )
                pillRow(
                    icon: "scalemass.fill",
                    title: "Slim",
                    body: "A 3 MB menu-bar app. The Whisper model is the only thing we download."
                )
                pillRow(
                    icon: "shield.checkered",
                    title: "Open source, MIT",
                    body: "Read every line. The same code runs your dictation."
                )
            }
            .padding(.top, 14)
            .frame(maxWidth: 440)

            Spacer()
        }
    }

    private func pillRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(body).font(.callout).foregroundStyle(.secondary)
            }
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
                    state.refreshPermissions()
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

private struct InstallStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: state.modelDownloaded ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(state.modelDownloaded ? Color.green : Color.accentColor)
                .animation(.easeInOut(duration: 0.25), value: state.modelDownloaded)

            Text(state.modelDownloaded ? "Whisper installed" : "Installing Whisper")
                .font(.title.weight(.semibold))

            Text(detailText)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 16)

            if let err = state.modelError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 380)
                    .multilineTextAlignment(.center)
            } else if !state.modelDownloaded {
                VStack(spacing: 10) {
                    ProgressView(value: state.modelProgress)
                        .frame(maxWidth: 320)
                    Text("\(Int(state.modelProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private var detailText: String {
        if state.modelDownloaded {
            return "About 700 MB on disk. After this, you can run fully offline — OpenQuack will never make another network call."
        }
        return "Downloading the medium WhisperKit model (~700 MB). This is the only network call OpenQuack makes, and only on first launch."
    }
}

private struct DemoStep: View {
    @ObservedObject var state: OnboardingState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 44)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Try it").font(.title.weight(.semibold))
                    Text("Press your hotkey, say a sentence, press again. Or hold it (push-to-talk).")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("YOUR TRANSCRIPT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
                .padding(.top, 8)

            ZStack(alignment: .topLeading) {
                if state.demoTranscript.isEmpty {
                    Text("Your spoken text will appear here.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $state.demoTranscript)
                    .font(.body)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 140, maxHeight: 200)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Looking for the recording overlay? Top-centre of your screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { focused = true }
    }
}

private struct DoneStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72)).foregroundStyle(.green)
            Text("You're all set").font(.title.weight(.semibold))
            Text("Press your hotkey anywhere to start dictating. Click the duck in your menu bar for Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            Spacer().frame(height: 12)
            VStack(alignment: .leading, spacing: 10) {
                tipRow(symbol: "command",
                       text: "Smart formatting, custom dictionary, push-to-talk, and VAD live in Settings.")
                tipRow(symbol: "lock.shield",
                       text: "Audio never leaves your Mac. The default agent does no network IO.")
            }
            .frame(maxWidth: 420)
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
    let state: OnboardingState
    private let onComplete: () -> Void

    /// Show on first launch only. AppDelegate provides its `appState` (so the
    /// demo step can observe transcripts) and an `onComplete` callback used to
    /// kick off WhisperKit warming once the user finishes.
    static func showIfFirstLaunch(appState: AppState, onComplete: @escaping () -> Void) {
        let done = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !done { show(appState: appState, onComplete: onComplete) }
    }

    static func show(appState: AppState, onComplete: @escaping () -> Void) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = OnboardingWindowController(appState: appState, onComplete: onComplete)
        shared = controller
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(appState: AppState, onComplete: @escaping () -> Void) {
        self.state = OnboardingState(appState: appState)
        self.onComplete = onComplete

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let view = OnboardingView(state: state) { [weak self] in
            self?.close()
        }
        window.contentViewController = NSHostingController(rootView: view)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func windowWillClose(_ notification: Notification) {
        state.complete()
        let cb = onComplete
        Self.shared = nil
        cb()
    }
}
