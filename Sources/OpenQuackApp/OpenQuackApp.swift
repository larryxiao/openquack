import AppKit
import AVFoundation
import SwiftUI
import Combine
import os
import ServiceManagement
import Sparkle
import UserNotifications
import OpenQuackKit

// SPEC-010 — App shell + dictation lifecycle (SPEC-001 + SPEC-003 wired in).
//
// Pure AppKit entry. SwiftUI App protocol (Settings/WindowGroup) silently lost
// the menu-bar item on macOS 15 in our testing; NSApp.run() avoids the issue.

@main
struct OpenQuackApp {
    static func main() {
        // Must run before anything touches `Bundle.module` in SwiftPM
        // packages with resources. See BundleModuleFallback.swift.
        BundleModuleFallback.install()

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
        let raw = UserDefaults.standard.string(forKey: "language") ?? ""  // default: auto-detect (SPEC-035)
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
    // SPEC-014 — transcripts persisted by default (entry cap = 50);
    // audio opt-in (privacy posture). The Settings → History dropdown
    // sets `historyMaxEntries`; 0 means "None — stop saving".
    private var saveTranscripts: Bool {
        let raw = UserDefaults.standard.object(forKey: "historyMaxEntries") as? Int
        return (raw ?? 50) > 0
    }
    private var saveAudio: Bool {
        UserDefaults.standard.bool(forKey: "saveAudio")
    }

    private var lastVoiceAt: Date?
    private static let voiceThreshold: Float = 0.06
    private static let vadMinDuration: Double = 0.8

    private let appState = AppState()
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyManager()

    /// SPEC-031 — tracks live + completed agent-kickoff sessions and
    /// posts notifications. Created lazily on the main actor because
    /// AgentSessionManager is @MainActor.
    @MainActor lazy var agentSessions = AgentSessionManager()
    /// SPEC-031 — opens on notification click.
    @MainActor lazy var responseWindow = ResponseWindowController()
    /// SPEC-007 — long-lived owner of the polish-model download (survives the
    /// Settings sheet). Wired to `appState` + reconciled in didFinishLaunching.
    @MainActor lazy var polishDownload = PolishModelDownloadController()
    private var transcriber: WhisperKitEngine?
    private var streamer: StreamingTranscriber?   // SPEC-012; long-lived after warm
    // SPEC-007 — in-process polish engine kept warm across dictations: warmed on
    // record-start, idle-unloaded after polishIdleUnload of no dictation.
    private var polishEngine: LlamaCppPolishEngine?
    private var polishEngineModelPath: URL?
    private var polishIdleTimer: Timer?
    private var overlay: RecordingOverlay?
    private let updateChecker = UpdateChecker()
    let usageStats = UsageStats()        // SPEC-013
    let historyStore = HistoryStore()    // SPEC-014

    /// SPEC-026 — Sparkle updater. Optional + initialized inside
    /// `applicationDidFinishLaunching` (after `installMethod` detection)
    /// so we can configure `automaticallyChecksForUpdates` before the
    /// updater's first scheduled poll. Declared as `var` rather than
    /// `lazy` because `SPUStandardUpdaterController` is `@MainActor`
    /// isolated; a stored-property initializer would need to run on the
    /// main actor at AppDelegate-init time, which isn't guaranteed.
    /// Held for the app's lifetime so scheduled checks keep running and
    /// so PR-B's Settings toggle / "Check now" button have a stable
    /// handle. NOTE: SUPublicEDKey in the bundled Info.plist is still a
    /// placeholder; until the user runs `generate_keys` and swaps it,
    /// Sparkle will refuse to install any downloaded update.
    var sparkleUpdater: SPUStandardUpdaterController?

    /// SPEC-023 — set true when reconcile returns `.resetToggleOff` (user
    /// revoked us in System Settings → Login Items while we weren't
    /// running). Settings → General reads this on appear to surface the
    /// approval hint. Session-scoped; cleared on next successful register.
    @MainActor var showsLaunchAtLoginApprovalHint: Bool = false

    private static let launchAtLoginLogger = Logger(
        subsystem: "org.openquack.OpenQuack",
        category: "LaunchAtLogin"
    )

    /// SPEC-007b — live polish debug stream. Each run logs one JSON object
    /// (raw/polished/engine/llm/ms) at `.debug` level, so the stream is
    /// newline-delimited JSON and trivially parseable. Debug level is inert
    /// (not captured, not persisted) in normal use and costs nothing until a
    /// developer explicitly tails it with `bash scripts/debug-listen.sh polish`
    /// (which formats it) — or raw via:
    ///   log stream --level debug --style ndjson --predicate 'subsystem == "org.openquack.OpenQuack" AND category == "polish"'
    private static let polishLog = Logger(
        subsystem: "org.openquack.OpenQuack",
        category: "polish"
    )

    /// Persist the last recording so the user can verify capture quality
    /// independent of model output. `open ~/Library/Application Support/OpenQuack/last-recording.wav`.
    private lazy var lastRecordingURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenQuack", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("last-recording.wav")
    }()

    private var elapsedTimer: Timer?
    private var permissionPollTimer: Timer?

    /// SPEC-012: serial pump from the audio thread → StreamingTranscriber.
    /// Spawning a `Task` per buffer doesn't guarantee FIFO at the actor;
    /// the AsyncStream pump does (yield is ordered, the consumer awaits one
    /// frame at a time).
    private var framesContinuation: AsyncStream<(samples: [Float], rate: Double)>.Continuation?
    private var framesPumpTask: Task<Void, Never>?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.installMethod = InstallMethodDetector.detect()
        installSparkleUpdater()
        // SPEC-026 PR-B — seed the prerelease default once. The
        // delegate's `feedURLString(for:)` reads this key on every
        // check, so no explicit `feedURL` set is needed at launch.
        let persistedPrereleases = UserDefaults.standard.object(forKey: "receivePrereleases") as? Bool
        UserDefaults.standard.set(
            defaultReceivePrereleases(version: OpenQuackKit.version, persistedValue: persistedPrereleases),
            forKey: "receivePrereleases"
        )
        installStatusItem()
        installPopover()
        installHotkey()
        observePhaseForIcon()
        overlay = RecordingOverlay(state: appState)

        // SPEC-007 — wire the download controller to AppState (so progress
        // drives the menu-bar banner) and resume any interrupted download
        // from a previous launch.
        polishDownload.appState = appState
        polishDownload.reconcileOnLaunch()

        // SPEC-031 — kickoff notification plumbing. Set the delegate
        // BEFORE any notification is posted so first-press clicks are
        // routed correctly; register the category so the action
        // button shows in Notification Center.
        UNUserNotificationCenter.current().delegate = self
        AgentSessionManager.registerNotificationCategory()

        // Defensive: switching activation policy back to .accessory can hide
        // the menu-bar status item on macOS 15. Re-assert visibility on every
        // policy flip so the duck stays put after onboarding / Settings close.
        ActivationPolicy.afterChange = { [weak self] in
            self?.statusItem.isVisible = true
        }

        // Drive the overlay's level meter — pushes into a sliding window
        // so each bar represents a slice of recent audio rather than all
        // bars reacting to the same instantaneous RMS.
        recorder.levelHandler = { [weak self] level in
            Task { @MainActor in
                self?.appState.pushLevel(level)
            }
        }

        // Refresh permission state on launch and every 5 s while running so
        // the popover banner reflects reality even if the user grants AX
        // through System Settings without coming back to the app first.
        refreshPermissions()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }

        let hasOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if hasOnboarded {
            // Seasoned user — warm the model in the background.
            Task { await warmTranscriber() }
        } else {
            // First launch. Warm the transcriber the moment the onboarding's
            // model download finishes, not when the window closes — the demo
            // step lives inside that window and needs a live engine to
            // transcribe what the user dictates. onComplete is the safety net
            // for users who close the window before the install step.
            OnboardingWindowController.showIfFirstLaunch(
                appState: appState,
                onModelReady: { [weak self] in
                    Task { await self?.warmTranscriber() }
                },
                onComplete: { [weak self] in
                    Task { await self?.warmTranscriber() }
                }
            )
        }

        // Light, opportunistic update poll. Once per launch, no faster than
        // once per 24h; quietly skips on network failure.
        Task { await pollForUpdate() }

        // SPEC-014 — sweep retention + offer crash-recovery on launch.
        let history = historyStore
        Task { @MainActor in
            await history.enforceRetention()
            await self.offerRecoveryIfNeeded()
        }

        // SPEC-023 — align the persisted launchAtLogin toggle with the OS
        // state. Catches the case where the user revoked us in System
        // Settings → Login Items while OpenQuack wasn't running.
        reconcileLaunchAtLoginOnLaunch()
    }

    /// SPEC-023 §Reconciliation — synchronous on the main actor, runs once
    /// at launch. `SMAppService` calls are cheap; no Task wrapper needed.
    @MainActor
    private func reconcileLaunchAtLoginOnLaunch() {
        let desired = UserDefaults.standard.bool(forKey: "launchAtLogin")
        let action = reconcileLaunchAtLogin(
            desiredEnabled: desired,
            currentStatus: SMAppService.mainApp.status
        )
        switch action {
        case .noop:
            return
        case .register:
            do {
                try SMAppService.mainApp.register()
            } catch {
                // register can throw on `.requiresApproval`; reverting matches
                // the SPEC-023 toggle-write contract.
                UserDefaults.standard.set(false, forKey: "launchAtLogin")
                showsLaunchAtLoginApprovalHint = true
                Self.launchAtLoginLogger.error("register() failed on launch: \(error.localizedDescription, privacy: .public)")
            }
        case .unregister:
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                Self.launchAtLoginLogger.error("unregister() failed on launch: \(error.localizedDescription, privacy: .public)")
            }
        case .resetToggleOff:
            UserDefaults.standard.set(false, forKey: "launchAtLogin")
            showsLaunchAtLoginApprovalHint = true
        }
    }

    /// macOS calls this when the user double-clicks the .app while it's
    /// already running. We're a menu-bar app with no main window, so the
    /// default behaviour is "nothing visible happens" — which makes users
    /// think the app is broken. Pop the menu so they can see we're alive.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        DispatchQueue.main.async { [weak self] in
            guard let self, let popover = self.popover, !popover.isShown else { return }
            self.togglePopover(nil)
        }
        return true
    }

    /// Forces the onboarding flow to re-appear. Called from Settings → About.
    @MainActor
    @objc func replayOnboarding() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        OnboardingWindowController.show(
            appState: appState,
            onModelReady: { [weak self] in
                Task { await self?.warmTranscriber() }
            },
            onComplete: { [weak self] in
                Task { await self?.warmTranscriber() }
            }
        )
    }

    /// Manual update check, called from Settings → About → "Check for updates".
    @MainActor
    @objc func checkForUpdatesManually() {
        Task { await pollForUpdate(force: true) }
    }

    /// SPEC-026 — Brew-cask coexistence is the hard rule: two installers
    /// must never fight over the same `.app` bundle. Sparkle is registered
    /// for everyone so PR-B's channel toggle keeps working if the user
    /// later switches install methods, but for `.homebrew` we disable
    /// scheduled checks so it polls nothing and shows nothing on its own.
    /// The popover banner (driven by `UpdateChecker` → `pollForUpdate`)
    /// stays the primary CTA; for brew users it remains the *only* update
    /// surface. Until the user fills `SUPublicEDKey` in the bundled
    /// Info.plist, Sparkle will fetch the appcast but refuse to install
    /// any downloaded update — the wiring is intentionally a no-op in
    /// PR-A's shipped binary.
    @MainActor
    private func installSparkleUpdater() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        switch appState.installMethod {
        case .homebrew:
            // Brew owns the bundle. Sparkle stays registered (so PR-B's
            // channel toggle and "Check now" button still resolve) but
            // its scheduler is muted.
            controller.updater.automaticallyChecksForUpdates = false
        case .manual:
            // DMG / drag-installed. Let Sparkle's daily scheduler run;
            // the interval is governed by `SUScheduledCheckInterval` in
            // the bundled Info.plist.
            controller.updater.automaticallyChecksForUpdates = true
        }
        sparkleUpdater = controller
    }

    private func pollForUpdate(force: Bool = false) async {
        if !force, let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        await MainActor.run { appState.updateStatus = .checking }
        do {
            let release = try await updateChecker.checkForUpdate(currentVersion: OpenQuackKit.version)
            let now = Date()
            await MainActor.run {
                if let release {
                    appState.updateStatus = .available(release)
                } else {
                    appState.updateStatus = .upToDate(version: OpenQuackKit.version, at: now)
                }
            }
            UserDefaults.standard.set(now, forKey: "lastUpdateCheck")
        } catch UpdateChecker.Error.noReleases {
            // Repo has no releases at all — uncommon, but treat as
            // up-to-date rather than an error so manual checks don't
            // surface a scary message during pre-release windows.
            await MainActor.run {
                appState.updateStatus = .upToDate(version: OpenQuackKit.version, at: Date())
            }
        } catch {
            await MainActor.run { appState.updateStatus = .failed("\(error)") }
        }
    }

    // MARK: - status item + popover

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Phase-driven NSImage is set in `updateIcon`; seed with the idle duck
        // so the status item renders something on first paint before phase
        // observation kicks in.
        if let idle = Self.menuIcon(for: .idle) {
            statusItem.button?.image = idle
            statusItem.button?.imagePosition = .imageOnly
        } else {
            statusItem.button?.title = "🦆"
        }
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

    @MainActor
    @objc func togglePopover(_ sender: AnyObject?) {
        // Route right-click to a small context menu (Show app, Quit). Left
        // click toggles the popover with live state.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.type == .rightMouseDown {
            showStatusItemMenu()
            return
        }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            stopMonitoringClicksOutside()
        } else {
            // Refresh now so the AX banner reflects the latest state immediately
            // when the popover opens.
            refreshPermissions()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            monitorClicksOutside()
        }
    }

    /// Right-click context menu — Show app, Send feedback, Quit. Settings
    /// is still reachable via the popover; `showApp` opens it directly so
    /// power users can skip the popover entirely. SPEC-018 adds "Send
    /// feedback" to give users a one-click path to file issues without
    /// navigating to GitHub manually.
    @MainActor
    private func showStatusItemMenu() {
        let menu = NSMenu()

        let show = NSMenuItem(title: "Show app", action: #selector(menuShowApp), keyEquivalent: ",")
        show.target = self
        menu.addItem(show)

        let feedback = NSMenuItem(title: "Send feedback…", action: #selector(menuSendFeedback), keyEquivalent: "")
        feedback.target = self
        menu.addItem(feedback)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit OpenQuack", action: #selector(menuQuitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Attach the menu, fire a synthetic click so AppKit shows it
        // anchored to the status-item button, then detach so the next
        // click routes back to `togglePopover`.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @MainActor
    @objc private func menuShowApp() {
        SettingsWindowController.show(appState: appState)
    }

    @MainActor
    @objc private func menuSendFeedback() {
        // SPEC-018. Opens the GitHub issue chooser; user picks bug report
        // or feature request from there. No app-side network IO.
        guard let url = URL(string: "https://github.com/larryxiao/openquack/issues/new/choose") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    @objc private func menuQuitApp() {
        NSApplication.shared.terminate(nil)
    }

    @MainActor
    private func refreshPermissions() {
        let trusted = PasteService.isAccessibilityTrusted()
        if appState.accessibilityTrusted != trusted {
            appState.accessibilityTrusted = trusted
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
        // Icon depends on phase + whether an update is available, so observe
        // both. CombineLatest republishes whenever either side changes.
        appState.$phase
            .combineLatest(appState.$updateStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase, status in
                self?.updateIcon(for: phase, hasUpdate: status.hasAvailableUpdate)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for phase: AppState.Phase, hasUpdate: Bool) {
        guard let button = statusItem.button else { return }
        if let image = Self.menuIcon(for: phase) {
            button.image = image
            button.title = hasUpdate ? "⬆" : ""
            button.imagePosition = hasUpdate ? .imageLeading : .imageOnly
        } else {
            // No icon for this phase yet (error). Fall back to a glyph so the
            // user still sees something distinctive.
            button.image = nil
            button.title = "❌"
            button.imagePosition = .noImage
        }
    }

    /// Cached template NSImages for each phase. Loaded once from the SwiftPM
    /// resource bundle; nil means "no icon, use the fallback glyph."
    private static let menuIconCache: [String: NSImage] = {
        var cache: [String: NSImage] = [:]
        for name in ["idle", "recording", "warming", "transcribing", "ready"] {
            if let img = loadMenuTemplateIcon(named: "duck-\(name)") {
                cache[name] = img
            }
        }
        return cache
    }()

    private static func menuIcon(for phase: AppState.Phase) -> NSImage? {
        switch phase {
        case .warming:              return menuIconCache["warming"]
        case .idle:                 return menuIconCache["idle"]
        case .ready:                return menuIconCache["ready"]
        case .starting, .recording: return menuIconCache["recording"]
        case .transcribing, .polishing: return menuIconCache["transcribing"]
        case .error:                return nil
        }
    }

    /// Load an `@1x` PNG from the resource bundle and attach the matching
    /// `@2x` rep so retina displays render the icon at native resolution.
    /// `isTemplate = true` lets macOS auto-tint to the menu-bar text colour
    /// (black in light mode, white in dark mode).
    private static func loadMenuTemplateIcon(named name: String) -> NSImage? {
        let bundle = Bundle.module
        // SPM `.process(...)` flattens directory structure, so resources land
        // at the bundle root regardless of source folder layout.
        guard let url1x = bundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url1x) else { return nil }
        let logicalSize = image.size
        if let url2x = bundle.url(forResource: "\(name)@2x", withExtension: "png"),
           let img2x = NSImage(contentsOf: url2x),
           let rep2x = img2x.representations.first {
            rep2x.size = logicalSize
            image.addRepresentation(rep2x)
        }
        image.isTemplate = true
        return image
    }

    // MARK: - hotkey

    private func installHotkey() {
        hotkey.registerToggle { [weak self] in self?.toggleRecording() }
        // SPEC-031 — second binding for agent kickoff. registerKickoff runs
        // AFTER registerToggle since the dictation register clears all
        // handlers.
        hotkey.registerKickoff { [weak self] in self?.toggleKickoff() }
    }

    @MainActor
    private func toggleRecording() {
        switch appState.phase {
        case .idle, .ready, .error:
            appState.recordingMode = .dictation
            startRecording()
        case .recording:
            stopAndTranscribe()
        case .warming, .starting, .transcribing, .polishing:
            // Ignore — the user gets a hotkey-tap during a transition; we just drop it.
            NSSound.beep()
        }
    }

    /// SPEC-031 — agent-kickoff hotkey. Press to start a recording whose
    /// transcript will be handed to a fresh Claude Code session (instead
    /// of pasting at the focused app's cursor). The first press on a
    /// fresh install shows a consent prompt naming Anthropic; declining
    /// is a no-op (the recording never starts).
    @MainActor
    private func toggleKickoff() {
        switch appState.phase {
        case .idle, .ready, .error:
            guard ensureKickoffConsent() else { return }
            appState.recordingMode = .agentKickoff
            startRecording()
        case .recording:
            // Same hotkey or the dictation hotkey both stop; recordingMode
            // was set when recording began, so the dispatch path is fixed.
            stopAndTranscribe()
        case .warming, .starting, .transcribing, .polishing:
            NSSound.beep()
        }
    }

    /// SPEC-031 privacy gate — runs once per install. The kickoff hotkey
    /// adds an Anthropic network hop on a path that was previously
    /// fully local; the user must consent explicitly with a modal that
    /// names the destination. Stored as a UserDefaults flag, revocable
    /// from Settings → Shortcut (clear the binding).
    @MainActor
    private func ensureKickoffConsent() -> Bool {
        let key = "agentKickoffConsented"
        if UserDefaults.standard.bool(forKey: key) { return true }

        let alert = NSAlert()
        alert.messageText = "Enable voice-launched agent?"
        alert.informativeText = """
        This hotkey sends your dictated request to Claude Code (Anthropic), \
        then the agent runs UNATTENDED with full permission bypass:

        • Runs any shell command on your Mac
        • Reads, writes, or deletes any file you can — not just the \
          workspace directory
        • Controls apps, changes settings, opens browser tabs, makes \
          network requests
        • Does all of this WITHOUT asking you first

        The default workspace is ~/OpenQuackAgent/ but the agent isn't \
        sandboxed there — its blast radius is everything bash can reach \
        as your user. Don't enable this if that's a worry.

        When the task finishes, you get a macOS notification. You can \
        attach to the live session in Terminal to continue, or stop it.

        First time: a one-time disclaimer from claude opens in Terminal — \
        accept it once, then kickoffs work straight through.

        Your normal dictation hotkey is unaffected. Revoke by clearing \
        this hotkey in Settings → Shortcut.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            UserDefaults.standard.set(true, forKey: key)
            return true
        }
        return false
    }

    // MARK: - record → transcribe pipeline

    /// The polish engine configured for the current dictation. Single source
    /// for both engine construction and the live overlay's "will it polish?"
    /// decision.
    private var polishEngineKind: PolishEngineKind {
        PolishEngineKind(rawValue: UserDefaults.standard.string(forKey: "polishEngine") ?? "off") ?? .off
    }

    /// Runs the optional LLM polish + regex pipeline on a script-normalised
    /// transcript, reading the current polish settings. Shared by the live
    /// dictation path and the crash-recovery path. Drives no UI — the caller
    /// owns the `.polishing` overlay phase.
    private func polishedTranscript(from scripted: String) async -> PolishResult {
        let polishEnabled = UserDefaults.standard.object(forKey: "polishText") as? Bool ?? true
        let engineKind = polishEngineKind
        let engine: TextPolishEngine?
        switch engineKind {
        case .off:
            engine = nil
        case .llamaCpp:
            engine = await MainActor.run { self.retainedLlamaEngine(path: PolishModelCatalog.localURL) }
        }
        let result = await PolishPipeline.polish(
            scripted,
            engine: engine,
            regexEnabled: polishEnabled,
            context: PolishContext(language: defaultLanguage, timestamp: Date())
        )
        var record: [String: Any] = [
            "raw": scripted,
            "polished": result.text,
            "engine": engineKind.rawValue,
            "llm": result.llmSucceeded,
        ]
        if let ms = result.llmMillis { record["ms"] = ms }
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            Self.polishLog.debug("\(json, privacy: .public)")
        }
        return result
    }

    private func startRecording() {
        Task {
            guard await AudioRecorder.requestPermission() else {
                await MainActor.run {
                    appState.phase = .error("Microphone permission denied. Enable in System Settings → Privacy & Security → Microphone.")
                }
                return
            }
            await MainActor.run {
                appState.phase = .starting
                cancelPolishIdleUnload()
                warmPolishEngineIfNeeded()
            }

            // SPEC-012: wire the streamer before start() so we don't miss the
            // first tap buffer. We always wire even for short utterances —
            // stopAndTranscribe decides whether to use the streamed result or
            // cancel the streamer and use the offline path. If the engine
            // isn't warm yet, framesHandler stays nil and we pay nothing.
            let language = defaultLanguage
            let words = customWords
            await tearDownFramesPump()
            if let streamer {
                // Pump pattern: the audio thread `yield`s into an unbounded
                // AsyncStream; a single Task drains it serially into the
                // actor. This preserves FIFO order — `Task { await ... }` per
                // buffer would race because actor reentry isn't queued in
                // submission order.
                //
                // `.unbounded` is safe: the pump consumer just hops into the
                // actor (sub-ms) per buffer, and producer rate is ~50/s of
                // ~10 ms buffers. The actor itself only retains samples until
                // the next emitChunksIfReady cut, so steady-state memory is
                // bounded by maxChunkSeconds, not stream backlog.
                let (stream, continuation) = AsyncStream<(samples: [Float], rate: Double)>.makeStream(
                    bufferingPolicy: .unbounded
                )
                self.framesContinuation = continuation
                recorder.framesHandler = { samples, rate in
                    continuation.yield((samples, rate))
                }
                self.framesPumpTask = Task { [weak streamer] in
                    for await frame in stream {
                        await streamer?.appendFrames(frame.samples, sampleRate: frame.rate)
                    }
                }
                await streamer.begin(language: language, customWords: words)
            } else {
                recorder.framesHandler = nil
            }

            do {
                let inputUID = UserDefaults.standard.string(forKey: "inputDeviceUID")
                _ = try recorder.start(outputURL: lastRecordingURL, inputDeviceUID: inputUID)
                await MainActor.run {
                    appState.phase = .recording
                    appState.elapsedSeconds = 0
                    appState.resetLevels()
                    lastVoiceAt = nil
                    startElapsedTimer()
                    playSound("Tink")
                }
            } catch {
                await tearDownFramesPump()
                if let streamer { await streamer.cancel() }
                await MainActor.run {
                    appState.phase = .error("Recording failed: \(error)")
                    schedulePolishIdleUnload()
                }
            }
        }
    }

    /// Hold the transcribing phase for at least this long. Short utterances
    /// otherwise transcribe in <300 ms — the progress bar flashes 0→100→done
    /// faster than the eye can register, which defeats the point of having
    /// progress UI in the first place.
    private static let minTranscribeDwell: TimeInterval = 0.6
    private static let polishIdleUnload: TimeInterval = 300   // 5 min
    /// SPEC-031 — map an AgentKickoffService error to a one-line user-
    /// facing label for the overlay's "ready" state.
    static func kickoffErrorLabel(_ error: Swift.Error) -> String {
        guard let kErr = error as? AgentKickoffService.Error else {
            return "Couldn't launch agent — \(error.localizedDescription)"
        }
        switch kErr {
        case .claudeCLIMissing:
            return "Claude Code not installed — transcript on clipboard"
        case .emptyPrompt:
            return "Nothing to send — say something first"
        case .invalidPrompt:
            return "Transcript contains an invalid character"
        case .workspaceUnavailable:
            return "Couldn't access ~/OpenQuackAgent/"
        case .launchFailed:
            return "Couldn't start claude — transcript on clipboard"
        case .disclaimerNotAccepted:
            // Should be caught upstream and surfaced with a clearer
            // message; fallback here.
            return "claude needs one-time setup — transcript on clipboard"
        case .bannerParseFailed:
            return "claude --bg ran but no session ID seen — transcript on clipboard"
        case .scriptWriteFailed:
            return "Couldn't write launch script — transcript on clipboard"
        case .terminalDispatchFailed:
            return "Terminal didn't launch — transcript on clipboard"
        }
    }

    /// SPEC-012: utterances at or above this duration take the streaming
    /// path; shorter ones stay on the offline path (faster end-to-end on
    /// short audio). Mirrors `StreamingTranscriber.Config.streamingThreshold`.
    private static let streamingThreshold: TimeInterval = 30

    private func stopAndTranscribe() {
        stopElapsedTimer()
        let audioDuration = recorder.elapsedSeconds
        // Captured peak level, read before stop() tears the recorder down.
        // A silent capture (dead/muted mic, or a virtual input device that
        // emits silence) otherwise gets transcribed into a Whisper
        // hallucination like "You." — warn the user instead.
        let capturePeakRMS = recorder.peakRMS
        guard let url = recorder.stop() else { return }

        if capturePeakRMS < AudioRecorder.silenceRMSThreshold {
            Task {
                await tearDownFramesPump()
                if let streamer { await streamer.cancel() }
                await MainActor.run {
                    appState.phase = .error("No sound detected. Check your microphone in System Settings → Sound → Input, and that OpenQuack has mic permission.")
                    schedulePolishIdleUnload()
                }
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        Task {
            let phaseStart = Date()
            await MainActor.run {
                appState.phase = .transcribing
                appState.transcriptionProgress = 0
            }

            guard let engine = transcriber else {
                await MainActor.run {
                    appState.phase = .error("Still getting ready — try again in a moment.")
                }
                try? FileManager.default.removeItem(at: url)
                return
            }

            // Drive the progress bar from a linear ramp tied to audio length
            // rather than WhisperKit's own Progress object. The KVO progress
            // reports unevenly — slow start then a snap to 100% at the end —
            // which felt broken to the user. A smooth ramp from 0 → ~95% over
            // the expected wall-clock (audio × 0.25, conservative for medium
            // on M-series) reads as real progress; we snap to 100% on actual
            // completion below.
            let estimatedTranscribe = max(0.4, audioDuration * 0.25)
            let progressTask = Task<Void, Never> { [weak self] in
                let start = Date()
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(start)
                    let frac = min(0.95, elapsed / estimatedTranscribe)
                    await MainActor.run { self?.appState.transcriptionProgress = frac }
                    if frac >= 0.95 { break }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
            defer { progressTask.cancel() }

            do {
                // SPEC-012: streaming path on long audio, offline on short.
                // Streaming reuses chunks transcribed during recording, so the
                // post-stop wait stays roughly flat as utterance length grows.
                // Teardown drains the audio-thread pump first so finish()
                // sees every frame; cancel() is fine to call after teardown
                // (any frames still queued become a no-op once cancelled).
                let result: EngineTranscription
                if audioDuration >= Self.streamingThreshold, let streamer {
                    await tearDownFramesPump()
                    let r = try await streamer.finish()
                    result = EngineTranscription(
                        text: r.text,
                        detectedLanguage: r.detectedLanguage,
                        audioSeconds: r.audioSeconds > 0 ? r.audioSeconds : audioDuration,
                        wallSeconds: r.wallSeconds,
                        timeToFirstToken: nil
                    )
                } else {
                    await tearDownFramesPump()
                    if let streamer { await streamer.cancel() }
                    result = try await engine.transcribe(
                        audioFile: url,
                        language: defaultLanguage,
                        customWords: customWords
                    )
                }

                // Whisper's `zh` output mixes Hant/Hans; normalise detected
                // Chinese to the system-language script before any other text
                // shaping. Gated on `zh` so Japanese/Korean Han is untouched
                // (SPEC-035).
                let scripted = ChineseScriptConverter.normalize(
                    result.text,
                    language: result.detectedLanguage,
                    preferredLanguages: Locale.preferredLanguages
                )

                if polishEngineKind != .off {
                    await MainActor.run { appState.phase = .polishing }
                }
                let polished = (await polishedTranscript(from: scripted)).text

                // Hold the progress bar at full briefly so the user sees the
                // transition land instead of jumping straight to "Pasted".
                await MainActor.run {
                    appState.transcriptionProgress = 1.0
                }
                let elapsed = Date().timeIntervalSince(phaseStart)
                if elapsed < Self.minTranscribeDwell {
                    let remaining = Self.minTranscribeDwell - elapsed
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }

                // SPEC-005 / SPEC-031: branch the output path on
                // recordingMode. Dictation pastes at the focused app's
                // cursor; agent kickoff hands the transcript to a fresh
                // Claude Code session and never writes to the focused
                // app at all.
                let recordingMode = await MainActor.run { appState.recordingMode }
                let pasted: Bool
                let kickoffSucceeded: Bool
                let kickoffErrorMessage: String?
                switch recordingMode {
                case .dictation:
                    let autoPasteEnabled = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
                    if autoPasteEnabled {
                        pasted = PasteService.paste(polished)
                    } else {
                        PasteService.copyToClipboard(polished)
                        pasted = false
                    }
                    kickoffSucceeded = false
                    kickoffErrorMessage = nil
                case .agentKickoff:
                    // The dictated text becomes the agent's seed prompt.
                    // Never paste at the user's cursor in this mode.
                    do {
                        let session = try AgentKickoffService.startClaudeKickoff(prompt: polished)
                        await MainActor.run { [agentSessions] in
                            agentSessions.track(session)
                        }
                        kickoffSucceeded = true
                        kickoffErrorMessage = nil
                        pasted = false
                    } catch AgentKickoffService.Error.disclaimerNotAccepted {
                        // First-use: open Terminal with the one-time
                        // claude-side disclaimer and stash the
                        // transcript so the user doesn't lose what
                        // they said. They re-press kickoff after
                        // accepting.
                        try? AgentKickoffService.openDisclaimerTerminal()
                        PasteService.copyToClipboard(polished)
                        kickoffSucceeded = false
                        kickoffErrorMessage = "Accept the claude disclaimer in Terminal, then re-press kickoff. Transcript on clipboard."
                        pasted = false
                    } catch {
                        // Fallback: stash on the clipboard so the user
                        // doesn't lose what they said. Surfaced in the
                        // overlay's "ready" state as an error message.
                        PasteService.copyToClipboard(polished)
                        kickoffSucceeded = false
                        kickoffErrorMessage = Self.kickoffErrorLabel(error)
                        pasted = false
                    }
                }

                await MainActor.run {
                    appState.lastTranscript = polished
                    appState.lastAudioSeconds = result.audioSeconds
                    appState.lastWallSeconds = result.wallSeconds
                    appState.lastRecordingURL = url
                    appState.lastPasted = pasted
                    appState.lastKickoffSucceeded = kickoffSucceeded
                    appState.lastKickoffError = kickoffErrorMessage
                    appState.accessibilityTrusted = PasteService.isAccessibilityTrusted()
                    appState.phase = .ready
                    playSound("Pop")
                    schedulePolishIdleUnload()
                }

                // SPEC-013/014 — record stats and persist history. Best-effort:
                // failures must not block paste (which already happened above).
                let detectedLanguage = result.detectedLanguage
                let modelLabel = self.defaultModel
                let audioDuration = result.audioSeconds
                let saveTranscriptsFlag = self.saveTranscripts
                let saveAudioFlag = self.saveAudio
                let stats = self.usageStats
                let history = self.historyStore
                Task {
                    await stats.record(transcript: polished, audioSeconds: audioDuration)
                    if saveTranscriptsFlag {
                        let audio = saveAudioFlag ? Self.loadAudioSamples(from: url) : nil
                        _ = try? await history.save(
                            audio: audio?.samples,
                            audioSampleRate: audio?.sampleRate ?? 16_000,
                            transcript: polished,
                            language: detectedLanguage,
                            modelID: modelLabel,
                            durationSeconds: audioDuration
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    appState.phase = .error("Transcription failed: \(error)")
                    schedulePolishIdleUnload()
                }
            }
            // Recording is kept for inspection — we let the next start() overwrite it.
        }
    }

    private func warmTranscriber() async {
        // Idempotent — the onboarding flow can call this twice (once when the
        // model download completes, once on window close); a re-init would
        // pointlessly drop and reload the engine.
        if self.transcriber != nil { return }
        await MainActor.run { appState.phase = .warming(modelLabel: defaultModel) }
        do {
            let engine = try await WhisperKitEngine(model: defaultModel)
            self.transcriber = engine
            self.streamer = engine.makeStreamingTranscriber()  // SPEC-012
            await MainActor.run {
                appState.phase = .idle
                appState.modelLabel = defaultModel
            }
            // Active model is loaded — drop sibling variants so the disk
            // footprint stays at one model. Bench leftovers and the previous
            // model after a switch both get cleaned up here.
            let active = defaultModel
            Task.detached(priority: .background) {
                _ = WhisperKitEngine.cleanupOtherModels(keeping: active)
            }
            Task.detached(priority: .background) {
                await WhisperKitEngine.refreshModelInBackground(model: active)
            }
        } catch {
            await MainActor.run {
                appState.phase = .error("Failed to load Whisper: \(error)")
            }
        }
    }

    // MARK: - SPEC-007 polish engine warmup / keep-warm / idle-unload

    /// Retained engine for the configured path; rebuilds if absent or path changed.
    @MainActor
    private func retainedLlamaEngine(path: URL) -> LlamaCppPolishEngine {
        if let engine = polishEngine, polishEngineModelPath == path {
            return engine
        }
        unloadPolishEngine()
        let engine = LlamaCppPolishEngine(modelPath: path)
        polishEngine = engine
        polishEngineModelPath = path
        return engine
    }

    /// Record-start hook: drop the engine if the user switched away from llamaCpp,
    /// else retain one and load it in the background so the ~3 GB load hides behind
    /// the record+transcribe window.
    @MainActor
    private func warmPolishEngineIfNeeded() {
        guard polishEngineKind == .llamaCpp else {
            unloadPolishEngine()
            return
        }
        let engine = retainedLlamaEngine(path: PolishModelCatalog.localURL)
        Task { try? await engine.warm() }
    }

    @MainActor
    private func unloadPolishEngine() {
        guard let engine = polishEngine else { return }
        polishEngine = nil
        polishEngineModelPath = nil
        Task.detached { await engine.unload() }
    }

    /// SPEC-007 — reclaim the ~2.9 GB GGUF. Sets the engine off, unloads any
    /// warm instance, then removes the file. `use_mmap=false` means a loaded
    /// engine keeps working until unload; we unload first so RAM is freed too.
    @MainActor
    func deletePolishModel() {
        UserDefaults.standard.set("off", forKey: "polishEngine")
        unloadPolishEngine()
        try? FileManager.default.removeItem(at: PolishModelCatalog.localURL)
    }

    /// Arm the debounce: unload the warm model after polishIdleUnload with no new
    /// dictation. Called when a dictation completes; cancelled at record-start.
    @MainActor
    private func schedulePolishIdleUnload() {
        polishIdleTimer?.invalidate()
        polishIdleTimer = Timer.scheduledTimer(withTimeInterval: Self.polishIdleUnload,
                                               repeats: false) { [weak self] _ in
            self?.unloadPolishEngine()
        }
    }

    @MainActor
    private func cancelPolishIdleUnload() {
        polishIdleTimer?.invalidate()
        polishIdleTimer = nil
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = self.recorder.elapsedSeconds
            self.appState.elapsedSeconds = elapsed

            // VAD auto-stop while recording.
            guard self.vadEnabled,
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

    /// SPEC-012: close the audio-thread → streamer pump. Awaits the pump
    /// task so any frames buffered in the AsyncStream actually land on
    /// `StreamingTranscriber.appendFrames` before the caller proceeds —
    /// load-bearing for `streamer.finish()` returning a complete transcript.
    /// Safe to call when nothing is wired (no-op).
    private func tearDownFramesPump() async {
        recorder.framesHandler = nil
        framesContinuation?.finish()
        framesContinuation = nil
        if let task = framesPumpTask {
            framesPumpTask = nil
            await task.value
        }
    }

    // MARK: - SPEC-014 crash recovery

    /// Read the recorder's WAV back as float samples. Used to feed history
    /// when the user has audio storage enabled. The recorder writes at the
    /// input device's native rate; we preserve that and let HistoryStore
    /// encode at whatever rate it received.
    static func loadAudioSamples(from url: URL) -> (samples: [Float], sampleRate: Double)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        return (samples, format.sampleRate)
    }

    /// On launch, surface any recordings that didn't complete transcription.
    /// Spec calls for a non-modal popover anchored to the menu-bar icon;
    /// alpha.5 ships an NSAlert as the simpler MVP. Replace in a follow-up.
    @MainActor
    private func offerRecoveryIfNeeded() async {
        let entries = await historyStore.recoverable()
        guard !entries.isEmpty else { return }

        let alert = NSAlert()
        if entries.count == 1 {
            let mins = max(1, Int(Date().timeIntervalSince(entries[0].recordedAt) / 60))
            alert.messageText = "We found a recording from \(mins) min ago that didn't finish."
            alert.informativeText = "Recover transcribes the audio and pastes the result. Discard deletes the recording."
            alert.addButton(withTitle: "Recover")
            alert.addButton(withTitle: "Discard")
        } else {
            alert.messageText = "\(entries.count) recordings to recover."
            alert.informativeText = "Recover all transcribes each one and pastes the results. Discard all deletes them."
            alert.addButton(withTitle: "Recover all")
            alert.addButton(withTitle: "Discard all")
        }

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for entry in entries { await recoverEntry(entry) }
        case .alertSecondButtonReturn:
            for entry in entries { try? await historyStore.delete(entry.id) }
        default: break
        }
    }

    @MainActor
    private func recoverEntry(_ entry: HistoryEntry) async {
        guard let audioURL = entry.audioURL else { return }
        // Engine may not be warm yet at this stage; warm if needed before
        // attempting recovery so the user-facing flow doesn't error out.
        if transcriber == nil { await warmTranscriber() }
        guard let engine = transcriber else { return }
        do {
            let result = try await engine.transcribe(
                audioFile: audioURL,
                language: entry.language,
                customWords: customWords
            )
            let scripted = ChineseScriptConverter.normalize(
                result.text,
                language: result.detectedLanguage,
                preferredLanguages: Locale.preferredLanguages
            )
            let polished = (await polishedTranscript(from: scripted)).text
            let autoPasteEnabled = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
            if autoPasteEnabled {
                _ = PasteService.paste(polished)
            } else {
                PasteService.copyToClipboard(polished)
            }
            schedulePolishIdleUnload()
            try? await historyStore.markTranscribed(entry.id, transcript: polished)
            await usageStats.record(transcript: polished, audioSeconds: result.audioSeconds)
        } catch {
            // Best-effort — leave the entry recoverable for next launch.
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // SPEC-031 v3 — kickoff sessions are owned by the claude
        // daemon and survive OpenQuack quitting (that's the whole
        // point of --bg). Stop our state-file watchers but DON'T
        // kill the sessions; user can re-enter them via `claude
        // agents` or `claude attach <id>` next time they want to.
        agentSessions.stopTrackingAll()
    }
}

// MARK: - SPEC-031: notification delegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show kickoff-result banners even while OpenQuack is foreground
    /// (e.g. user opened Settings) — otherwise macOS suppresses them.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Click handler — opens the response window for the result whose
    /// shortID is carried in userInfo.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard
            let shortID = response.notification.request.content.userInfo["shortID"] as? String
        else { return }
        Task { @MainActor in
            guard let result = agentSessions.result(for: shortID) else { return }
            responseWindow.show(result: result)
        }
    }
}
