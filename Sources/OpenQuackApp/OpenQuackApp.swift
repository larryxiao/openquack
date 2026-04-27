import AppKit
import SwiftUI
import Combine
import OpenQuackKit

// SPEC-010 — App shell + dictation lifecycle (SPEC-001 + SPEC-003 wired in).
//
// Pure AppKit entry. SwiftUI App protocol (Settings/WindowGroup) silently lost
// the menu-bar item on macOS 15 in our testing; NSApp.run() avoids the issue.

@main
struct OpenQuackApp {
    static func main() {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var monitor: Any?
    private var cancellables = Set<AnyCancellable>()

    // Defaults read from UserDefaults (Settings writes them via @AppStorage).
    private var defaultModel: String {
        UserDefaults.standard.string(forKey: "model") ?? "medium"
    }
    private var defaultLanguage: String? {
        let raw = UserDefaults.standard.string(forKey: "language") ?? "en"
        return raw.isEmpty ? nil : raw  // empty string = auto-detect
    }
    private var customWords: String? {
        UserDefaults.standard.string(forKey: "customWords")
    }
    private var soundsEnabled: Bool {
        UserDefaults.standard.object(forKey: "playSounds") as? Bool ?? true
    }
    private var vadEnabled: Bool {
        UserDefaults.standard.bool(forKey: "vadAutoStop")
    }
    private var vadSilenceSeconds: Double {
        let raw = UserDefaults.standard.double(forKey: "vadSilenceSeconds")
        return raw > 0 ? raw : 1.5
    }

    private var lastVoiceAt: Date?
    private static let voiceThreshold: Float = 0.06
    private static let vadMinDuration: Double = 0.8

    private let appState = AppState()
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyManager()
    private var transcriber: WhisperKitEngine?
    private var overlay: RecordingOverlay?

    /// Persist the last recording so the user can verify capture quality
    /// independent of model output. `open ~/Library/Application Support/OpenQuack/last-recording.wav`.
    private lazy var lastRecordingURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenQuack", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("last-recording.wav")
    }()

    private var elapsedTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        installPopover()
        installHotkey()
        observePhaseForIcon()
        overlay = RecordingOverlay(state: appState)

        // Drive the overlay's level meter.
        recorder.levelHandler = { [weak self] level in
            self?.appState.currentLevel = level
        }

        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if hasOnboarded {
            // Seasoned user — warm the model in the background.
            Task { await warmTranscriber() }
        } else {
            // First launch. Defer warming to onboarding completion so the
            // onboarding's progress-bar download isn't fighting a concurrent
            // WhisperKit init in the background.
            OnboardingWindowController.showIfFirstLaunch(appState: appState) { [weak self] in
                Task { await self?.warmTranscriber() }
            }
        }
    }

    // MARK: - status item + popover

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
        statusItem.button?.title = "🦆"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func installPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 320)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContent(state: appState)
        )
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            stopMonitoringClicksOutside()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            monitorClicksOutside()
        }
    }

    private func monitorClicksOutside() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
            self?.stopMonitoringClicksOutside()
        }
    }

    private func stopMonitoringClicksOutside() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    // MARK: - icon ↔ phase

    private func observePhaseForIcon() {
        appState.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in self?.updateIcon(for: phase) }
            .store(in: &cancellables)
    }

    private func updateIcon(for phase: AppState.Phase) {
        let glyph: String
        switch phase {
        case .warming: glyph = "🟡"
        case .idle, .ready: glyph = "🦆"
        case .starting, .recording: glyph = "🔴"
        case .transcribing: glyph = "⌛"
        case .error: glyph = "❌"
        }
        statusItem.button?.title = glyph
    }

    // MARK: - hotkey

    private func installHotkey() {
        hotkey.register(
            onKeyDown: { [weak self] in self?.handleKeyDown() },
            onKeyUp:   { [weak self] in self?.handleKeyUp() }
        )
    }

    private var hotkeyMode: HotkeyMode {
        let raw = UserDefaults.standard.string(forKey: "hotkeyMode") ?? HotkeyMode.toggle.rawValue
        return HotkeyMode(rawValue: raw) ?? .toggle
    }

    @MainActor
    private func handleKeyDown() {
        switch hotkeyMode {
        case .toggle:
            toggleRecording()
        case .pushToTalk:
            // Start on key-down; stop on key-up. Ignore key repeats.
            if case .recording = appState.phase { return }
            startRecording()
        }
    }

    @MainActor
    private func handleKeyUp() {
        switch hotkeyMode {
        case .toggle:
            return
        case .pushToTalk:
            if case .recording = appState.phase {
                stopAndTranscribe()
            }
        }
    }

    @MainActor
    private func toggleRecording() {
        switch appState.phase {
        case .idle, .ready, .error:
            startRecording()
        case .recording:
            stopAndTranscribe()
        case .warming, .starting, .transcribing:
            // Ignore — the user gets a hotkey-tap during a transition; we just drop it.
            NSSound.beep()
        }
    }

    // MARK: - record → transcribe pipeline

    private func startRecording() {
        Task {
            guard await AudioRecorder.requestPermission() else {
                await MainActor.run {
                    appState.phase = .error("Microphone permission denied. Enable in System Settings → Privacy & Security → Microphone.")
                }
                return
            }
            await MainActor.run { appState.phase = .starting }

            do {
                _ = try recorder.start(outputURL: lastRecordingURL)
                await MainActor.run {
                    appState.phase = .recording
                    appState.elapsedSeconds = 0
                    lastVoiceAt = nil
                    startElapsedTimer()
                    playSound("Tink")
                }
            } catch {
                await MainActor.run {
                    appState.phase = .error("Recording failed: \(error)")
                }
            }
        }
    }

    private func stopAndTranscribe() {
        stopElapsedTimer()
        guard let url = recorder.stop() else { return }
        Task {
            await MainActor.run { appState.phase = .transcribing }

            guard let engine = transcriber else {
                await MainActor.run {
                    appState.phase = .error("Whisper model still warming. Try again in a moment.")
                }
                try? FileManager.default.removeItem(at: url)
                return
            }

            do {
                let result = try await engine.transcribe(
                    audioFile: url,
                    language: defaultLanguage,
                    customWords: customWords
                )

                // Smart formatting on raw Whisper output (capitalisation,
                // end-punctuation, fillers). Toggle: Settings → General.
                let polishEnabled = UserDefaults.standard.object(forKey: "polishText") as? Bool ?? true
                let polished = polishEnabled
                    ? TextPolisher.polish(result.text)
                    : result.text

                // SPEC-005: paste at cursor by default; pasteboard-only fallback.
                let autoPasteEnabled = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
                let pasted: Bool
                if autoPasteEnabled {
                    pasted = PasteService.paste(polished)
                } else {
                    PasteService.copyToClipboard(polished)
                    pasted = false
                }

                await MainActor.run {
                    appState.lastTranscript = polished
                    appState.lastAudioSeconds = result.audioSeconds
                    appState.lastWallSeconds = result.wallSeconds
                    appState.lastRecordingURL = url
                    appState.lastPasted = pasted
                    appState.accessibilityTrusted = PasteService.isAccessibilityTrusted()
                    appState.phase = .ready
                    playSound("Pop")
                }
            } catch {
                await MainActor.run {
                    appState.phase = .error("Transcription failed: \(error)")
                }
            }
            // Recording is kept for inspection — we let the next start() overwrite it.
        }
    }

    private func warmTranscriber() async {
        await MainActor.run { appState.phase = .warming(modelLabel: defaultModel) }
        do {
            let engine = try await WhisperKitEngine(model: defaultModel)
            self.transcriber = engine
            await MainActor.run {
                appState.phase = .idle
                appState.modelLabel = "whisperkit \(defaultModel) · \(defaultLanguage ?? "auto")"
            }
        } catch {
            await MainActor.run {
                appState.phase = .error("Failed to load Whisper: \(error)")
            }
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = self.recorder.elapsedSeconds
            self.appState.elapsedSeconds = elapsed

            // VAD auto-stop (toggle mode only — push-to-talk is user-controlled).
            guard self.hotkeyMode == .toggle, self.vadEnabled,
                  case .recording = self.appState.phase
            else { return }

            if self.appState.currentLevel > Self.voiceThreshold {
                self.lastVoiceAt = Date()
            }
            if let lastVoice = self.lastVoiceAt,
               elapsed >= Self.vadMinDuration,
               Date().timeIntervalSince(lastVoice) >= self.vadSilenceSeconds {
                self.stopAndTranscribe()
            }
        }
    }

    private func playSound(_ name: String) {
        guard soundsEnabled else { return }
        NSSound(named: name)?.play()
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

}
