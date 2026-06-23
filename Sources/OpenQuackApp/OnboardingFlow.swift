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
//
// Design system: see Theme.swift. Onboarding is a "reception" surface, so
// it uses CreamSurface as the background and the serif titles. Step icons
// are restrained regular-weight glyphs in cream-raised circles — one motif
// across all steps reads more designed than a parade of `.circle.fill`s.

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case accessibility
    case hotkey
    case install
    case demo
    case polish
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

    @Published var enablePolish: Bool = false

    /// Fires the moment the speech model finishes downloading. AppDelegate
    /// hooks this to warm the WhisperKit transcriber in parallel — without
    /// it the demo step has a downloaded model on disk but no in-memory
    /// engine, so the hotkey records audio that nothing can transcribe.
    var onModelReady: (() -> Void)?

    private let appState: AppState
    let polishDownload: PolishModelDownloadController
    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?

    init(appState: AppState, polishDownload: PolishModelDownloadController) {
        self.appState = appState
        self.polishDownload = polishDownload
        refreshPermissions()

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
        let oldMic = micStatus
        let oldAX = accessibilityTrusted
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityTrusted = AXIsProcessTrusted()

        // If a permission just flipped to granted while the user is on the
        // matching step, schedule an auto-advance so they don't have to
        // manually click Continue (especially relevant for AX, which the
        // user grants in System Settings — they may not return to OpenQuack).
        let micJustGranted = oldMic != .authorized && micStatus == .authorized
        let axJustGranted  = !oldAX && accessibilityTrusted
        if step == .microphone && micJustGranted {
            // Mic just granted — bring our window forward so the user sees the
            // device picker + test the mic step now shows. Deliberately do NOT
            // auto-advance: we want them to pick and verify a working mic here.
            NSApp.activate(ignoringOtherApps: true)
        } else if step == .accessibility && axJustGranted {
            // AX is granted in System Settings; the user may not return, so
            // auto-advance once it flips.
            NSApp.activate(ignoringOtherApps: true)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                if accessibilityTrusted { advance() }
            }
        }
    }

    /// Drive permission grant via Continue. Returns true if Continue should
    /// NOT also call advance() (because the grant flow is in progress and
    /// either the OS prompt or System Settings handoff will resolve it).
    func continueWillTriggerPermissionPrompt() -> Bool {
        switch step {
        case .microphone where micStatus == .notDetermined:
            Task { [weak self] in
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                await MainActor.run { self?.refreshPermissions() }
            }
            return true
        case .accessibility where !accessibilityTrusted:
            _ = PasteService.isAccessibilityTrusted(prompt: true)
            PasteService.openAccessibilitySettings()
            return true  // wait for System Settings → polling auto-advances
        default:
            return false
        }
    }

    func advance() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    func back() {
        if let prev = OnboardingStep(rawValue: step.rawValue - 1) {
            step = prev
        }
    }

    var canGoBack: Bool {
        step.rawValue > 0
    }

    /// Quietly advance past the current step if the relevant permission is
    /// already granted. Brief delay so the user sees the "Already granted"
    /// state before the step disappears — magical, not jarring.
    func autoAdvanceIfAlreadyGranted() async {
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard !Task.isCancelled else { return }
        switch step {
        // Microphone deliberately omitted — the mic step lets the user pick and
        // test a device, so we stay there even when permission is already granted.
        case .accessibility where accessibilityTrusted:
            advance()
        default:
            break
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
                    self?.onModelReady?()
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
        ZStack {
            CreamSurface().ignoresSafeArea()

            VStack(spacing: 0) {
                stepBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, Theme.s32)
                    .padding(.vertical, Theme.s24)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: state.step)

                Divider().opacity(0.4)
                footer
                    .padding(.horizontal, Theme.s24)
                    .padding(.vertical, Theme.s16)
            }
        }
        .frame(width: 580, height: 560)
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
        case .polish:         PolishStep(state: state)
        case .done:           DoneStep(polishHint: polishDoneHint)
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.s12) {
            stepIndicator
            modelChip
            Spacer()
            Button("Back") {
                state.back()
            }
            .buttonStyle(.bordered)
            .disabled(!state.canGoBack)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button(continueLabel) {
                if state.step == .done {
                    state.complete()
                    onClose()
                    return
                }
                if state.step == .polish {
                    // Off-by-default: only an explicit opt-in enables polish. If the
                    // model is already on disk, flip the engine on directly; otherwise
                    // the download commits the engine on verified success.
                    if state.enablePolish {
                        if PolishModelCatalog.isInstalled() {
                            UserDefaults.standard.set("llamaCpp", forKey: "polishEngine")
                        } else {
                            state.polishDownload.confirm()
                            state.polishDownload.detachToBackground()
                        }
                    }
                    state.advance()
                    return
                }
                let triggeredPrompt = state.continueWillTriggerPermissionPrompt()
                if !triggeredPrompt {
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
        case .microphone where state.micStatus == .notDetermined:
            return "Allow microphone"
        case .accessibility where !state.accessibilityTrusted:
            return "Open System Settings"
        case .install where !state.modelDownloaded:
            return "Waiting…"
        case .polish where state.enablePolish:
            return PolishModelCatalog.isInstalled() ? "Enable & continue" : "Download & continue"
        case .done:
            return "Done"
        default:
            return "Continue"
        }
    }

    /// The done-step polish line, derived from the real outcome rather than the
    /// opt-in flag: a download in flight, an engine just switched on, or nothing.
    private var polishDoneHint: String? {
        if case .downloading = state.polishDownload.phase {
            return "Local LLM polish is downloading in the background — we'll let you know when it's ready."
        }
        if UserDefaults.standard.string(forKey: "polishEngine") == "llamaCpp" {
            return "Local LLM polish is on."
        }
        return nil
    }

    private var continueDisabled: Bool {
        switch state.step {
        case .install: return !state.modelDownloaded && state.modelError == nil
        default:       return false
        }
    }

    private var stepIndicator: some View {
        SectionHeader("Step \(state.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    @ViewBuilder
    private var modelChip: some View {
        if !state.modelDownloaded && state.modelError == nil {
            HStack(spacing: Theme.s4) {
                ProgressView().controlSize(.mini)
                Text("Installing \(Int(state.modelProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else if state.modelDownloaded {
            HStack(spacing: Theme.s4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.moss)
                Text("Ready").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - shared step chrome

/// Restrained step icon: a regular-weight SF Symbol in a soft cream-raised
/// circle. One motif across every step.
private struct StepGlyph: View {
    let symbol: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.creamRaised)
                .frame(width: 96, height: 96)
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.ink.opacity(0.85))
        }
    }
}

// MARK: - steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: Theme.s16) {
            DuckMark(size: 96)
            Text("Welcome to OpenQuack")
                .font(.oqHeroSerif)
            Text("Speak. Send. Privately.")
                .font(.oqTaglineSerif)
                .foregroundStyle(.secondary)

            VStack(spacing: Theme.s8) {
                privacyRow(
                    icon: "lock.shield",
                    title: "Local-only by design",
                    body: "Audio never leaves your Mac. No cloud, no signup, no telemetry."
                )
                privacyRow(
                    icon: "bolt.fill",
                    title: "Fast and accurate",
                    body: "Transcribed in a fraction of the time you spent speaking, reliable on natural conversation. Backed by benchmarks."
                )
                privacyRow(
                    icon: "shield.checkered",
                    title: "Open source, MIT",
                    body: "Read every line. The same code runs your dictation."
                )
            }
            .padding(.top, Theme.s12)
            .frame(maxWidth: 460)

            Spacer()
        }
    }

    private func privacyRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Theme.s12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.ink.opacity(0.85))
                .frame(width: 26, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .oqCardOnCream(padding: Theme.s12)
    }
}

private struct MicrophoneStep: View {
    @ObservedObject var state: OnboardingState
    @AppStorage("inputDeviceUID") private var inputDeviceUID: String = ""
    @StateObject private var micTest = MicTestModel()
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        VStack(spacing: Theme.s16) {
            StepGlyph(symbol: glyph)
            Text("Microphone").font(.oqTitleSerif)
            Text(bodyCopy)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            Spacer().frame(height: Theme.s8)

            if state.micStatus == .authorized {
                deviceChooser
            } else {
                statusBadge
            }
            Spacer()
        }
        .onAppear { devices = AudioInputDevices.list() }
        .onDisappear { micTest.stop() }
    }

    /// Picker + Test so the user confirms a working mic on day one — this is
    /// where the "silent default device → 'You.'" bug bites hardest.
    private var deviceChooser: some View {
        VStack(spacing: Theme.s12) {
            Picker("Microphone", selection: $inputDeviceUID) {
                Text("System default").tag("")
                ForEach(devices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .frame(maxWidth: 360)
            .onChange(of: inputDeviceUID) { _ in
                if micTest.isTesting { micTest.start(deviceUID: inputDeviceUID) }
            }

            HStack(spacing: Theme.s8) {
                Button(micTest.isTesting ? "Stop" : "Test mic") {
                    micTest.toggle(deviceUID: inputDeviceUID)
                }
                .buttonStyle(.bordered)
                if micTest.isTesting {
                    MicLevelMeter(levels: micTest.levels)
                }
            }

            Group {
                if let err = micTest.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.amber)
                        .multilineTextAlignment(.center)
                } else if micTest.sawSignal {
                    Label("Sounds good — that mic is picking you up.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.moss)
                } else if micTest.isTesting {
                    Text("Speak — the bars should move.").foregroundStyle(.secondary)
                } else {
                    Text("Pick your mic and hit Test to make sure it hears you.").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: 400)
    }

    private var glyph: String {
        switch state.micStatus {
        case .authorized: return "checkmark"
        case .denied, .restricted: return "exclamationmark.triangle"
        default: return "mic"
        }
    }

    private var bodyCopy: String {
        switch state.micStatus {
        case .authorized:
            return "Pick the microphone OpenQuack should listen to, then test it."
        case .denied, .restricted:
            return "Microphone access was denied. Open System Settings → Privacy & Security → Microphone to enable it."
        case .notDetermined:
            return "OpenQuack transcribes locally — audio never leaves your Mac. Click Allow microphone to grant access."
        @unknown default:
            return ""
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch state.micStatus {
        case .denied, .restricted:
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                )!)
            }
            .buttonStyle(.bordered)
        default:
            EmptyView()  // Continue button drives the prompt
        }
    }
}

private struct AccessibilityStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(spacing: Theme.s16) {
            StepGlyph(symbol: state.accessibilityTrusted ? "checkmark" : "command")
            Text("Auto-paste").font(.oqTitleSerif)
            Text(bodyCopy)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Spacer().frame(height: Theme.s8)

            if state.accessibilityTrusted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.moss)
            } else {
                Text("Click Open System Settings, then turn on OpenQuack. We'll detect the change automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            Spacer()
        }
        .task {
            await state.autoAdvanceIfAlreadyGranted()
        }
    }

    private var bodyCopy: String {
        if state.accessibilityTrusted {
            return "Accessibility access is already granted — moving on."
        }
        return "OpenQuack pastes your transcript at the cursor by simulating ⌘V. macOS calls this Accessibility access. You'll grant it once in System Settings — without it, transcripts go to your clipboard and you press ⌘V manually."
    }
}

private struct HotkeyStep: View {
    var body: some View {
        VStack(spacing: Theme.s16) {
            StepGlyph(symbol: "keyboard")
            Text("Pick your hotkey").font(.oqTitleSerif)
            Text("Press once to start dictating, again to stop. ⌃⇧Space is set as the default — change it below if you'd like.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            Spacer().frame(height: Theme.s8)
            FnAwareShortcutRecorder()
            Spacer()
        }
    }
}

private struct InstallStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(spacing: Theme.s16) {
            StepGlyph(symbol: state.modelDownloaded ? "checkmark" : "arrow.down.circle")
                .animation(.easeInOut(duration: 0.25), value: state.modelDownloaded)

            Text(state.modelDownloaded ? "Speech model ready" : "Installing the speech model")
                .font(.oqTitleSerif)

            Text(detailText)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: Theme.s8)

            if let err = state.modelError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.amber)
                    .frame(maxWidth: 380)
                    .multilineTextAlignment(.center)
            } else if !state.modelDownloaded {
                VStack(spacing: Theme.s8) {
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
            return "All set — about 700 MB on disk. Dictation is fully offline from here."
        }
        return "OpenQuack downloads a small speech model (about 700 MB). One-time only — after this, dictation runs offline."
    }
}

private struct DemoStep: View {
    @ObservedObject var state: OnboardingState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s12) {
            HStack(spacing: Theme.s12) {
                StepGlyph(symbol: "waveform.badge.mic")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Try it").font(.oqTitleSerif)
                    Text("Click the box, press your hotkey, and say something.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }

            SectionHeader("Your transcript")
                .padding(.top, Theme.s8)

            PlaceholderTextEditor(
                text: $state.demoTranscript,
                prompt: "Your spoken text will appear here.",
                minHeight: 140,
                idealHeight: 180
            )
            .focused($focused)

            HStack(spacing: Theme.s8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("A small pill at the top of your screen shows when it's listening.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, Theme.s4)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { focused = true }
    }
}

private struct PolishStep: View {
    @ObservedObject var state: OnboardingState
    @AppStorage("polishEngine") private var polishEngine: String = "off"

    var body: some View {
        // "Enabled" is the engine setting, not mere file presence — the model
        // can be on disk while polish is switched off.
        let installed = PolishModelCatalog.isInstalled()
        VStack(spacing: Theme.s16) {
            StepGlyph(symbol: "sparkles")
            Text("Polish your dictation").font(.oqTitleSerif)
            Text("An optional on-device model cleans up filler words, grammar, and punctuation before your text is pasted. Experimental.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Spacer().frame(height: Theme.s8)

            if polishEngine == "llamaCpp" {
                Label("Already enabled — ready to use.", systemImage: "checkmark.circle.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.moss)
            } else {
                VStack(spacing: Theme.s8) {
                    Toggle("Enable local LLM polish", isOn: $state.enablePolish)
                        .frame(maxWidth: 360)
                    Text(installed
                         ? "The model is already on your Mac — no download needed."
                         : "One-time \(PolishModelCatalog.sizeLabel) download · stays on your Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Model license", destination: PolishModelCatalog.licenseURL)
                        .font(.caption)
                }
                .frame(maxWidth: 400)
            }
            Spacer()
        }
    }
}

private struct DoneStep: View {
    let polishHint: String?

    var body: some View {
        VStack(spacing: Theme.s16) {
            StepGlyph(symbol: "checkmark")
            Text("You're all set").font(.oqTitleSerif)
            Text("Press your hotkey anywhere to dictate. The duck in your menu bar opens Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Spacer().frame(height: Theme.s8)
            VStack(alignment: .leading, spacing: Theme.s8) {
                if let polishHint {
                    tipRow(symbol: "wand.and.stars", text: polishHint)
                }
                tipRow(symbol: "slider.horizontal.3",
                       text: "Push-to-talk, custom dictionary, and auto-stop live in Settings.")
                tipRow(symbol: "lock.shield",
                       text: "Audio stays on your Mac. Dictation makes no network calls.")
                tipRow(symbol: "sparkles",
                       text: "🦆 has more tricks up its feathers. Stay tuned.")
            }
            .frame(maxWidth: 440)
            Spacer()
        }
    }

    private func tipRow(symbol: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.s8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

// MARK: - window controller

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: OnboardingWindowController?
    let state: OnboardingState
    private let onComplete: () -> Void

    static func showIfFirstLaunch(
        appState: AppState,
        polishDownload: PolishModelDownloadController,
        onModelReady: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        let done = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !done { show(appState: appState, polishDownload: polishDownload, onModelReady: onModelReady, onComplete: onComplete) }
    }

    static func show(
        appState: AppState,
        polishDownload: PolishModelDownloadController,
        onModelReady: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Switch to .regular so the user gets a Dock icon — System Settings
        // can hide the onboarding window when granting permissions, and the
        // Dock icon is the lifeline back. Reverted on close.
        NSApp.setActivationPolicy(.regular)
        let controller = OnboardingWindowController(
            appState: appState,
            polishDownload: polishDownload,
            onModelReady: onModelReady,
            onComplete: onComplete
        )
        shared = controller
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(appState: AppState, polishDownload: PolishModelDownloadController, onModelReady: @escaping () -> Void, onComplete: @escaping () -> Void) {
        let state = OnboardingState(appState: appState, polishDownload: polishDownload)
        state.onModelReady = onModelReady
        self.state = state
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
        // Revert to .accessory only if no other titled window is left visible.
        DispatchQueue.main.async {
            ActivationPolicy.refresh()
        }
        cb()
    }
}

/// Centralised activation policy: .regular when any titled window is visible,
/// .accessory when only the menu-bar status item + transient panels remain.
@MainActor
enum ActivationPolicy {
    /// Hook invoked after the policy switches. AppDelegate uses this to
    /// re-assert `statusItem.isVisible = true` — switching .regular →
    /// .accessory on macOS 15 can hide the status item.
    static var afterChange: (() -> Void)?

    static func refresh() {
        let hasTitledWindow = NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled)
        }
        NSApp.setActivationPolicy(hasTitledWindow ? .regular : .accessory)
        afterChange?()
    }
}
