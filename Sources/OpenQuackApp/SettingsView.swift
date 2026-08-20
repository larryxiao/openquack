import SwiftUI
import AppKit
import KeyboardShortcuts
import os
import ServiceManagement
import OpenQuackKit
import OpenQuackPlatform

// Settings scene. SwiftUI TabView in an NSWindow (managed by
// SettingsWindowController). Storage via @AppStorage on UserDefaults.
//
// Per the design critique, the Models tab collapsed into General — it was
// a single picker hidden behind a tab. Section headers across every Form
// use the small-caps SectionHeader from Theme.swift. About is the only
// "reception" pane and uses CreamSurface + serif titles.

struct SettingsView: View {
    enum Tab: Hashable { case general, shortcut, stats, history, about }
    @State private var selection: Tab = .general
    @ObservedObject var appState: AppState
    @ObservedObject private var polishDownload = (NSApp.delegate as! AppDelegate).polishDownload
    @ObservedObject private var speechDownload = (NSApp.delegate as! AppDelegate).speechDownload

    var body: some View {
        TabView(selection: $selection) {
            GeneralPane(appState: appState)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            ShortcutPane()
                .tabItem { Label("Shortcut", systemImage: "command") }
                .tag(Tab.shortcut)
            StatsPane(appState: appState)
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(Tab.stats)
            HistoryPane()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
            AboutPane(appState: appState)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(minWidth: 580, idealWidth: 580, minHeight: 500, idealHeight: 500)
        // Download sheets live at the window root, not inside General, so the
        // menu-bar "Show" affordance can surface them whatever tab is open.
        .sheet(isPresented: $speechDownload.isPresented,
               onDismiss: { speechDownload.detachToBackground() }) {
            SpeechModelDownloadSheet(model: speechDownload)
        }
        .sheet(isPresented: $polishDownload.isPresented,
               onDismiss: { polishDownload.detachToBackground() }) {
            PolishModelDownloadSheet(model: polishDownload)
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var appState: AppState
    @AppStorage("autoPaste")           private var autoPaste: Bool = true
    @AppStorage("polishText")          private var polishText: Bool = true
    @AppStorage("polishEngine")        private var polishEngine: String = "off"
    @AppStorage("polishSystemPrompt")  private var polishSystemPrompt: String = PolishPrompt.defaultInstructions
    @ObservedObject private var modelDownload = (NSApp.delegate as! AppDelegate).polishDownload
    @ObservedObject private var speechDownload = (NSApp.delegate as! AppDelegate).speechDownload
    @AppStorage("language")            private var language: String = ""   // "" = auto-detect (SPEC-035)
    @AppStorage("playSounds")          private var playSounds: Bool = true
    @AppStorage("vadAutoStop")         private var vadAutoStop: Bool = false
    @AppStorage("vadSilenceSeconds")   private var vadSilenceSeconds: Double = 1.5
    @AppStorage("customWords")         private var customWords: String = ""
    @AppStorage("model")               private var model: String = "medium"
    // SPEC-044 — remote transcription backend. The API key itself never
    // touches UserDefaults: it lives in the Keychain, keyed by endpoint host.
    @AppStorage("transcriptionBackend") private var transcriptionBackend: String = "local"
    @AppStorage("remoteEndpoint")       private var remoteEndpoint: String = ""
    @AppStorage("remoteModel")          private var remoteModel: String = "whisper-1"
    @AppStorage("remoteAuthMethod")     private var remoteAuthMethod: String = "bearer"
    @AppStorage("remoteAuthHeaderName") private var remoteAuthHeaderName: String = ""
    @AppStorage("remoteUserAgent")      private var remoteUserAgent: String = ""
    @State private var remoteSecret: String = ""
    /// Draft mirror of `remoteEndpoint` — the field binds here so a pasted
    /// `user:pass@` URL is sanitised *before* anything reaches UserDefaults.
    @State private var remoteEndpointDraft: String = ""
    // SPEC-045 — Cloudflare Access sign-in state machine.
    private enum CFAccessUIState: Equatable {
        case checking
        case missingCloudflared
        case signedOut
        case signingIn
        case signedIn(expires: Date)
        case expired
        case failed(String)
    }
    @State private var cfState: CFAccessUIState = .checking
    /// Bumped on every sign-in, cancel, and refresh; async completions compare
    /// against it and discard themselves when stale — Cancel really cancels,
    /// and out-of-order keystroke probes can't clobber newer state.
    @State private var cfGeneration = 0
    @AppStorage("inputDeviceUID")      private var inputDeviceUID: String = ""  // "" = system default
    @AppStorage("launchAtLogin")       private var launchAtLogin: Bool = false

    /// Input devices for the Microphone picker; loaded `.onAppear` and
    /// refreshed when the picker is interacted with.
    @State private var inputDevices: [AudioInputDevice] = []
    /// Drives the "Test" button's live level meter.
    @StateObject private var micTest = MicTestModel()

    // SPEC-026 PR-B — Updates section state.
    @AppStorage("receivePrereleases") private var receivePrereleases: Bool = false
    /// Mirror of `SPUUpdater.automaticallyChecksForUpdates`. Sparkle is
    /// the source of truth (it persists to UserDefaults `SUEnableAutomaticChecks`);
    /// the mirror seeds `.onAppear` and writes back through the public
    /// setter on `.onChange` so Sparkle's internal `resetUpdateCycle`
    /// fires. A direct `@AppStorage` on `SUEnableAutomaticChecks` would
    /// bypass that setter.
    @State private var sparkleAutoChecks: Bool = false
    /// Snapshot of `SPUUpdater.lastUpdateCheckDate`, refreshed `.onAppear`
    /// and 1.5 s after a Check-now tap. `nil` means "never checked";
    /// the "Last checked" line is suppressed in that case.
    @State private var lastChecked: Date?

    // SPEC-023 — session-only hint, seeded from AppDelegate so reconcile
    // results from app launch propagate the first time Settings opens.
    @State private var showsApprovalHint: Bool = false
    // Suppresses the .onChange-triggered SMAppService call when the toggle
    // is reverted programmatically after a failed register().
    @State private var isRevertingToggle: Bool = false

    private static let logger = Logger(
        subsystem: "org.openquack.OpenQuack",
        category: "LaunchAtLogin"
    )

    /// Mirror of `@AppStorage("model")` that the Picker binds to. A plain
    /// rejecting binding leaves the Picker showing a rejected value, so we drive
    /// it through `@State` and reconcile in `.onChange`: a not-yet-downloaded
    /// model opens the download sheet and the visual selection snaps back; a
    /// successful download flows the committed `model` back into the Picker.
    @State private var pickerModel: String = ""

    /// Variants whose weights are on disk — drives the "Downloaded models"
    /// table. Recomputed on appear, when a download settles, and after a delete
    /// (disk state isn't observable, so we refresh it explicitly).
    @State private var downloadedModels: [String] = []

    private func refreshDownloadedModels() {
        // Exclude the model currently downloading: WhisperKit writes weight
        // bundles to their final path mid-transfer, so `hasModelWeights` flips
        // true before the download finishes — without this it would show (and
        // be deletable) while still downloading.
        var downloading: String?
        if case .downloading(let m, _) = appState.speechDownload { downloading = m }
        downloadedModels = SpeechModelCatalog.all.filter {
            $0 != downloading && WhisperKitEngine.hasModelWeights(for: $0)
        }
    }

    @ViewBuilder
    private var downloadedModelsTable: some View {
        if !downloadedModels.isEmpty {
            VStack(alignment: .leading, spacing: Theme.s8) {
                Text("Downloaded models")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(downloadedModels, id: \.self) { variant in
                    // "Active" = the model actually loaded right now (hot-swap
                    // updates it). `model` is the selection; they differ only
                    // briefly when a swap is deferred behind an in-progress dictation.
                    let isLoaded = (variant == appState.modelLabel)
                    let isProtected = isLoaded || (variant == model)
                    HStack(spacing: Theme.s8) {
                        Text(SpeechModelCatalog.displayName(for: variant))
                        Text(SpeechModelCatalog.sizeLabel(for: variant))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if isLoaded {
                            Text("Active").font(.caption.weight(.semibold)).foregroundStyle(Theme.moss)
                        }
                        Button("Delete") { confirmDeleteSpeechModel(variant) }
                            .font(.caption)
                            .disabled(isProtected)
                            .help(isProtected
                                  ? "This model is in use. Switch to another model first, then delete it."
                                  : "Remove this model from disk to free space.")
                    }
                }
            }
        }
    }

    private func confirmDeleteSpeechModel(_ variant: String) {
        let alert = NSAlert()
        alert.messageText = "Delete \(SpeechModelCatalog.displayName(for: variant))?"
        alert.informativeText = "Frees \(SpeechModelCatalog.sizeLabel(for: variant)) of disk. You can re-download it any time from the Speech model menu."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        WhisperKitEngine.deleteModel(variant)
        refreshDownloadedModels()
    }

    /// Inline progress row shown under the picker while a download runs in the
    /// background (sheet dismissed). Extracted to keep the Form body light for
    /// the SwiftUI type-checker.
    @ViewBuilder
    private var speechDownloadRow: some View {
        switch speechDownload.phase {
        case .downloading(let fraction) where !speechDownload.isPresented:
            let caption = "\(SpeechModelCatalog.displayName(for: speechDownload.target)) · \(SpeechModelDownloadSheet.percentLabel(fraction))"
            HStack(spacing: Theme.s8) {
                ProgressView(value: fraction).frame(maxWidth: 160)
                Text(caption)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Show") { speechDownload.resurface() }
                    .font(.caption)
            }
        case .failed(let message) where !speechDownload.isPresented:
            // A background download (sheet dismissed) that failed has no other
            // surface, so show it here with a retry.
            HStack(spacing: Theme.s8) {
                Text(message)
                    .font(.caption).foregroundStyle(.red)
                Spacer()
                Button("Retry") { speechDownload.retry() }.font(.caption)
                Button("Dismiss") { speechDownload.cancel() }.font(.caption)
            }
        default:
            EmptyView()
        }
    }

    /// Reconcile a picker selection: a downloaded model switches immediately; a
    /// not-yet-downloaded one opens the download sheet and the visual pick reverts.
    private func selectSpeechModel(_ target: String) {
        guard target != model else { return }
        var warmingNow = false
        if case .downloading = appState.speechDownload, !speechDownload.canResurface { warmingNow = true }
        if !warmingNow, !WhisperKitEngine.hasModelWeights(for: target) {
            // App is warm but the model isn't downloaded → confirm + download;
            // the controller hot-swaps the engine once it lands.
            speechDownload.begin(target: target)
            pickerModel = model
        } else {
            // Downloaded (hot-swap now) or mid warm-up (retarget) — commit and let
            // AppDelegate apply it: immediately, or after the current dictation.
            model = target
            (NSApp.delegate as? AppDelegate)?.swapModel()
        }
    }

    private var speechModelPicker: some View {
        Picker("Speech model", selection: $pickerModel) {
            Text("tiny — fastest, lowest accuracy (~150 MB)").tag("tiny")
            Text("base — fast, modest accuracy (~290 MB)").tag("base")
            Text("small — balanced (~480 MB)").tag("small")
            Text("medium — best balance, default (~1.5 GB)").tag("medium")
            Text("large-v3 — highest accuracy (~3 GB)").tag("large-v3")
        }
        .onAppear { pickerModel = model; refreshDownloadedModels() }
        .onChange(of: model) { pickerModel = $0; refreshDownloadedModels() }
        .onChange(of: pickerModel) { selectSpeechModel($0) }
        .onChange(of: appState.speechDownload) { _ in refreshDownloadedModels() }
    }

    // MARK: SPEC-044 — remote transcription backend

    private var remoteSecretHost: String? {
        URL(string: remoteEndpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host
    }

    private func reloadRemoteSecret() {
        remoteSecret = remoteSecretHost.flatMap { KeychainCredentialStore().secret(forHost: $0) } ?? ""
    }

    private func commitRemoteEndpoint(_ raw: String) {
        var value = raw
        if var comps = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           comps.user != nil || comps.password != nil {
            comps.user = nil
            comps.password = nil
            value = comps.string ?? ""
            remoteEndpointDraft = value   // reflect the strip in the field
        }
        remoteEndpoint = value
        reloadRemoteSecret()
        // Changing the endpoint mid-sign-in supersedes that flow — the row
        // must not keep claiming a sign-in for a host no longer configured.
        if cfState == .signingIn {
            cancelCFSignIn()
        } else {
            refreshCFAccessState()
        }
    }

    // MARK: SPEC-045 — Cloudflare Access sign-in

    /// The Access "app URL": the endpoint's origin (scheme + host + port).
    private var remoteEndpointOrigin: URL? {
        guard var comps = URLComponents(string: remoteEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              comps.host != nil
        else { return nil }
        comps.path = ""
        comps.query = nil
        comps.fragment = nil
        return comps.url
    }

    /// `force` lets the sign-in flow's own completions repaint the row; every
    /// other caller yields to an in-flight sign-in.
    private func refreshCFAccessState(force: Bool = false) {
        guard remoteAuthMethod == "cloudflareAccess" else { return }
        if !force, cfState == .signingIn { return }   // an in-flight sign-in owns the row
        cfGeneration += 1
        let generation = cfGeneration
        cfState = .checking
        let host = remoteSecretHost
        // Keychain read off the UI thread; path detection is a fast stat() scan.
        Task.detached(priority: .userInitiated) {
            let installed = CloudflareAccessClient.cloudflaredPath() != nil
            let jwt = host.flatMap {
                CloudflareAccessClient.accessToken(forHost: $0, in: KeychainCredentialStore())
            }
            await MainActor.run {
                guard generation == cfGeneration, remoteAuthMethod == "cloudflareAccess" else { return }
                if !installed {
                    cfState = .missingCloudflared
                } else if let jwt, !jwt.isEmpty, let exp = CloudflareAccessClient.expiry(of: jwt) {
                    // Same freshness rule as the send path (single source of truth).
                    cfState = CloudflareAccessClient.isUsable(jwt) ? .signedIn(expires: exp) : .expired
                } else {
                    cfState = .signedOut
                }
            }
        }
    }

    private func signInCloudflare() {
        guard let origin = remoteEndpointOrigin, let host = origin.host else {
            cfState = .failed("Enter a valid endpoint URL first.")
            return
        }
        cfGeneration += 1
        let generation = cfGeneration
        cfState = .signingIn
        Task {
            do {
                try await CloudflareAccessClient.login(appURL: origin)
                let jwt = try await CloudflareAccessClient.fetchToken(appURL: origin)
                await MainActor.run {
                    // Cancelled or superseded → discard; store nothing.
                    guard generation == cfGeneration else { return }
                    CloudflareAccessClient.setAccessToken(jwt, forHost: host, in: KeychainCredentialStore())
                    refreshCFAccessState(force: true)
                }
            } catch {
                let firstLine = "\(error)".components(separatedBy: "\n")[0]
                await MainActor.run {
                    guard generation == cfGeneration else { return }
                    cfState = .failed(firstLine)
                }
            }
        }
    }

    private func cancelCFSignIn() {
        cfGeneration += 1   // orphans the in-flight Task's completion
        CloudflareAccessClient.cancelActiveLogin()   // and kills the cloudflared child
        refreshCFAccessState(force: true)
    }

    private func signOutCloudflare() {
        if let host = remoteSecretHost {
            CloudflareAccessClient.setAccessToken(nil, forHost: host, in: KeychainCredentialStore())
        }
        refreshCFAccessState()
    }

    @ViewBuilder
    private var cloudflareAccessRow: some View {
        switch cfState {
        case .checking:
            HStack(spacing: Theme.s8) {
                ProgressView().controlSize(.small)
                Text("Checking for cloudflared…").font(.caption).foregroundStyle(.secondary)
            }
        case .missingCloudflared:
            Text("Requires cloudflared: install with `brew install cloudflared`, then reopen this pane. Your company's IdP handles the actual login — OpenQuack never sees your password.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .signedOut:
            Button("Sign in with your browser…") { signInCloudflare() }
                .help("Opens your browser to sign in through your organisation's identity provider. The resulting token is stored in your Keychain, tied to this host.")
        case .signingIn:
            HStack(spacing: Theme.s8) {
                ProgressView().controlSize(.small)
                Text("Finish signing in in your browser…").font(.caption).foregroundStyle(.secondary)
                Button("Cancel") { cancelCFSignIn() }.font(.caption)
            }
        case .signedIn(let expires):
            // TimelineView re-evaluates periodically so an expiry that passes
            // while Settings sits open flips the row without a manual refresh.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if expires.timeIntervalSince(context.date) <= CloudflareAccessClient.expiryLeeway {
                    expiredRow
                } else {
                    HStack(spacing: Theme.s8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.moss)
                        Text("Signed in · expires \(expires.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                        Spacer()
                        Button("Sign out") { signOutCloudflare() }.font(.caption)
                    }
                }
            }
        case .expired:
            expiredRow
        case .failed(let message):
            HStack(spacing: Theme.s8) {
                Text(message).font(.caption).foregroundStyle(.red)
                Button("Try again") { signInCloudflare() }.font(.caption)
            }
        }
    }

    private var expiredRow: some View {
        HStack(spacing: Theme.s8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text("Session expired").font(.caption)
            Button("Sign in again") { signInCloudflare() }.font(.caption)
        }
    }

    private func saveRemoteSecret(_ value: String) {
        guard let host = remoteSecretHost else { return }
        KeychainCredentialStore().setSecret(value.isEmpty ? nil : value, forHost: host)
    }

    @ViewBuilder
    private var remoteBackendRows: some View {
        TextField("Endpoint URL", text: $remoteEndpointDraft, prompt: Text("https://api.openai.com/v1"))
            .autocorrectionDisabled()
            .onAppear { remoteEndpointDraft = remoteEndpoint }
            .onChange(of: remoteEndpointDraft) { commitRemoteEndpoint($0) }
        TextField("Model", text: $remoteModel, prompt: Text("whisper-1"))
            .autocorrectionDisabled()
        TextField("User agent", text: $remoteUserAgent, prompt: Text(RemoteProfile.defaultUserAgent))
            .autocorrectionDisabled()
        Picker("Authentication", selection: $remoteAuthMethod) {
            Text("None").tag("none")
            Text("API key (Bearer)").tag("bearer")
            Text("Custom header").tag("header")
            Text("Company SSO (Cloudflare Access)").tag("cloudflareAccess")
        }
        .onChange(of: remoteAuthMethod) { _ in refreshCFAccessState() }
        if remoteAuthMethod == "header" {
            TextField("Header name", text: $remoteAuthHeaderName, prompt: Text("X-Api-Key"))
                .autocorrectionDisabled()
        }
        if remoteAuthMethod == "bearer" || remoteAuthMethod == "header" {
            SecureField("API key", text: $remoteSecret)
                .onChange(of: remoteSecret) { saveRemoteSecret($0) }
        }
        if remoteAuthMethod == "cloudflareAccess" {
            cloudflareAccessRow
                .onAppear { refreshCFAccessState() }
        }
        Text("Recordings are sent to this OpenAI-compatible endpoint (POST /audio/transcriptions) while this is on. The key is stored in your Keychain, tied to this exact host — change the host and you'll enter it again. Requests identify themselves only by the user agent above (a neutral default when empty), never by the app's name.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    var body: some View {
        Form {
            Section {
                Picker("Transcription", selection: $transcriptionBackend) {
                    Text("On this Mac").tag("local")
                    Text("Remote endpoint (experimental)").tag("remote")
                }
                .help("Remote sends each recording to the server you configure below. Local is the default; nothing leaves your Mac unless you switch.")
                .onChange(of: transcriptionBackend) { _ in
                    (NSApp.delegate as? AppDelegate)?.transcriptionBackendChanged()
                }
                if transcriptionBackend == "remote" {
                    remoteBackendRows
                }
                speechModelPicker
                    .disabled(transcriptionBackend == "remote")
                speechDownloadRow
                Text("Switches right away (downloads first if the model isn't on your Mac). A switch during dictation applies once it finishes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                downloadedModelsTable
            } header: {
                SectionHeader("Speech-to-text")
            }
            .onAppear { reloadRemoteSecret() }

            Section {
                Picker("Microphone", selection: $inputDeviceUID) {
                    Text("System default").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                    // Keep the saved choice visible even if the device is gone,
                    // so the picker doesn't silently blank out.
                    if !inputDeviceUID.isEmpty,
                       !inputDevices.contains(where: { $0.uid == inputDeviceUID }) {
                        Text("Selected device (disconnected)").tag(inputDeviceUID)
                    }
                }
                .onAppear { inputDevices = AudioInputDevices.list() }
                .onChange(of: inputDeviceUID) { _ in
                    if micTest.isTesting { micTest.start(deviceUID: inputDeviceUID) }  // re-point test
                }

                HStack(spacing: Theme.s8) {
                    Button(micTest.isTesting ? "Stop" : "Test") {
                        micTest.toggle(deviceUID: inputDeviceUID)
                    }
                    if micTest.isTesting {
                        MicLevelMeter(levels: micTest.levels)
                        if micTest.sawSignal {
                            Label("Sounds good", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(Theme.moss)
                        } else {
                            Text("Speak — bars should move.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                if let err = micTest.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("The mic OpenQuack records from. \"System default\" follows macOS. If recordings come back blank or as \"You.\", pick your real mic here and hit Test. Takes effect on the next recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("Microphone")
            }

            Section {
                Toggle("Paste at cursor automatically", isOn: $autoPaste)
                    .help("After transcription, OpenQuack simulates ⌘V to paste into whatever app you're in. Requires Accessibility access. If off, the transcript still goes to your clipboard and you press ⌘V yourself.")
                Toggle("Smart formatting", isOn: $polishText)
                    .help("Capitalise sentences, add a period at the end, strip filler words (um, uh) before paste. Off = paste exactly what Whisper heard.")
                Picker("Local LLM polish (experimental)", selection: Binding(
                    get: { polishEngine },
                    set: { selection in
                        if selection == "llamaCpp", !PolishModelCatalog.isInstalled() {
                            modelDownload.begin()   // don't commit; sheet decides
                        } else {
                            polishEngine = selection
                        }
                    }
                )) {
                    Text("Off").tag("off")
                    Text("Local LLM (llama.cpp)").tag("llamaCpp")
                }
                .help("Runs an extra local LLM cleanup pass before paste, using an in-process model on your Mac. If the model isn't available, falls back to your Smart formatting setting (or raw text if that's off). Nothing leaves your Mac.")
                if case .downloading(let stats) = modelDownload.phase, !modelDownload.isPresented {
                    HStack(spacing: Theme.s8) {
                        ProgressView(value: stats.fraction).frame(maxWidth: 160)
                        Text(PolishModelDownloadSheet.progressCaption(stats))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Show") { modelDownload.resurface() }
                            .font(.caption)
                    }
                }
                if PolishModelCatalog.isInstalled() {
                    Button("Delete model (\(PolishModelCatalog.sizeLabel))…", role: .destructive) {
                        confirmDeletePolishModel()
                    }
                    .help("Remove the downloaded Local LLM model to reclaim disk space. Re-selecting Local LLM will download it again.")
                }
                if polishEngine == "llamaCpp" {
                    VStack(alignment: .leading, spacing: Theme.s4) {
                        HStack {
                            Text("LLM polish instructions")
                            Spacer()
                            Button("Reset to default") {
                                polishSystemPrompt = PolishPrompt.defaultInstructions
                            }
                            .font(.caption)
                            .disabled(polishSystemPrompt == PolishPrompt.defaultInstructions)
                        }
                        PlaceholderTextEditor(
                            text: $polishSystemPrompt,
                            prompt: PolishPrompt.defaultInstructions,
                            monospaced: true,
                            minHeight: 120,
                            idealHeight: 160
                        )
                        Text("The system prompt sent to the Local LLM. Takes effect on your next dictation — no restart needed. Leave blank to use the default. The transcript delimiter is added automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Play sounds when recording starts / stops", isOn: $playSounds)
                    .help("Subtle system sounds. Useful if the menu-bar icon or overlay isn't visible.")
            } header: {
                SectionHeader("Behaviour")
            }

            Section {
                Picker("Transcription language", selection: $language) {
                    Text("Auto-detect").tag("")
                    Divider()
                    Text("English (en)").tag("en")
                    Text("Chinese (zh)").tag("zh")
                    Text("Japanese (ja)").tag("ja")
                    Text("Korean (ko)").tag("ko")
                    Text("Spanish (es)").tag("es")
                    Text("French (fr)").tag("fr")
                    Text("German (de)").tag("de")
                    Text("Italian (it)").tag("it")
                    Text("Portuguese (pt)").tag("pt")
                }
                Text("Auto-detect identifies the spoken language for each recording. Pick a specific language only if you always dictate in the same one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("Language")
            }

            Section {
                Toggle("Auto-stop after silence", isOn: $vadAutoStop)
                    .help("When you stop speaking, OpenQuack finishes the recording automatically.")
                if vadAutoStop {
                    HStack {
                        Text("Silence threshold")
                        Slider(value: $vadSilenceSeconds, in: 0.8...4.0, step: 0.1)
                        Text(String(format: "%.1f s", vadSilenceSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                SectionHeader("Auto-stop")
            }

            Section {
                PlaceholderTextEditor(
                    text: $customWords,
                    prompt: "e.g.\nOpenQuack\nWhisperKit\nClaude Code",
                    monospaced: true,
                    minHeight: 90,
                    idealHeight: 110
                )
                Text("One word or phrase per line. Whisper uses these as a hint when deciding between similar-sounding words — useful for proper nouns, jargon, and project names.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("Custom dictionary")
            }

            // SPEC-023 — Launch at login.
            Section {
                Toggle("Launch OpenQuack at login", isOn: $launchAtLogin)
                    .help("Start OpenQuack automatically when you sign in to your Mac, so the menu-bar icon and global hotkey are ready without launching the app manually.")
                if showsApprovalHint {
                    Text("macOS blocked OpenQuack from auto-starting. Enable it in System Settings → General → Login Items, then toggle this on again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SectionHeader("Startup")
            }

            // SPEC-026 PR-B — Updates (Sparkle controls; brew-aware).
            //
            // brew install: every Sparkle-side control is functionally a
            // no-op. Surface that honestly with a single line telling
            // brew users exactly how to update, with the command typeset
            // monospaced.
            Section {
                if appState.installMethod.isBrew {
                    Text(brewUpdateInstructions)
                        .font(.callout)
                } else {
                    Toggle("Check for updates automatically", isOn: $sparkleAutoChecks)
                        .help("Let OpenQuack check for new versions in the background.")

                    if let date = lastChecked {
                        Text("Last checked: \(date.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Include pre-release builds (alpha/beta)", isOn: $receivePrereleases)
                        .help("Receive alpha and beta builds in addition to stable releases. Useful if you want fixes before they reach the stable channel.")

                    Button("Check now") {
                        handleCheckNowTap()
                    }
                }
            } header: {
                SectionHeader("Updates")
            }
        }
        .formStyle(.grouped)
        .padding()
        .creamSettingsBackground()
        .onAppear {
            // Pick up the session-flag if reconcile flipped the toggle at
            // launch (user revoked us in System Settings while away).
            if let delegate = NSApp.delegate as? AppDelegate,
               delegate.showsLaunchAtLoginApprovalHint {
                showsApprovalHint = true
            }
            // SPEC-026 PR-B — seed Sparkle state mirrors.
            if let updater = (NSApp.delegate as? AppDelegate)?.sparkleUpdater?.updater {
                sparkleAutoChecks = updater.automaticallyChecksForUpdates
                lastChecked = updater.lastUpdateCheckDate
            }
        }
        .onChange(of: launchAtLogin) { newValue in
            handleLaunchAtLoginChange(newValue)
        }
        // SPEC-026 PR-B — write the auto-check toggle through Sparkle's
        // setter so `resetUpdateCycle` fires.
        .onChange(of: sparkleAutoChecks) { newValue in
            (NSApp.delegate as? AppDelegate)?.sparkleUpdater?.updater
                .automaticallyChecksForUpdates = newValue
        }
        // SPEC-026 PR-B — flipping the prerelease toggle re-runs a check
        // immediately so the user sees the result of the new channel
        // without waiting for the next scheduled one. `@AppStorage`
        // already persisted the value; the delegate's `feedURLString(for:)`
        // reads it on the next check and routes to the right appcast.
        // Goes through `handleCheckNowTap()` (same path as the "Check now"
        // button) so "Last checked" stays in sync.
        .onChange(of: receivePrereleases) { _ in
            handleCheckNowTap()
        }
    }

    /// SPEC-026 PR-B — brew-mode hint with the upgrade command typeset
    /// as monospaced primary text inline.
    private var brewUpdateInstructions: AttributedString {
        var s = AttributedString()
        var prefix = AttributedString("OpenQuack is managed by Homebrew on this Mac. Run ")
        prefix.foregroundColor = .secondary
        s += prefix
        var cmd = AttributedString("brew upgrade --cask openquack")
        cmd.font = .system(.body, design: .monospaced)
        cmd.foregroundColor = .primary
        s += cmd
        var suffix = AttributedString(" to update.")
        suffix.foregroundColor = .secondary
        s += suffix
        return s
    }

    /// SPEC-026 PR-B — `Check now` button action. Triggers Sparkle's
    /// own check + dialog flow; we re-snapshot `lastUpdateCheckDate`
    /// after a short delay because the check is async.
    @MainActor
    private func handleCheckNowTap() {
        guard let controller = (NSApp.delegate as? AppDelegate)?.sparkleUpdater else { return }
        controller.checkForUpdates(nil)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 s
            lastChecked = controller.updater.lastUpdateCheckDate
        }
    }

    @MainActor
    private func confirmDeletePolishModel() {
        let alert = NSAlert()
        alert.messageText = "Delete the Local LLM model?"
        alert.informativeText = "This frees ~2.9 GB. Local LLM polish turns off; re-selecting it downloads the model again."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        (NSApp.delegate as? AppDelegate)?.deletePolishModel()
        polishEngine = "off"     // reflect immediately in the picker binding
    }

    /// SPEC-023 §Toggle write path. Synchronous SMAppService IO on the
    /// main actor; on register-throw we revert the toggle and show the hint.
    @MainActor
    private func handleLaunchAtLoginChange(_ newValue: Bool) {
        if isRevertingToggle {
            isRevertingToggle = false
            return
        }
        if newValue {
            do {
                try SMAppService.mainApp.register()
                showsApprovalHint = false
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.showsLaunchAtLoginApprovalHint = false
                }
            } catch {
                // register can throw on `.requiresApproval`; reverting matches
                // the SPEC-023 toggle-write contract.
                isRevertingToggle = true
                launchAtLogin = false
                showsApprovalHint = true
                Self.logger.error("register() failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                Self.logger.error("unregister() failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Shortcut

private struct ShortcutPane: View {
    var body: some View {
        Form {
            Section {
                FnAwareShortcutRecorder()
                Text("Press once to start dictating, again to stop. ⌃⇧Space is the default and works in most apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("Global hotkey")
            }

            Section {
                KeyboardShortcuts.Recorder("Kickoff:", name: .agentKickoff)
                Text("Voice → fresh background Claude Code session. Press the hotkey, dictate a task, release; the agent runs unattended with **full permission bypass** (any shell command, any file, any app) and you get a macOS notification when it's done. Default ⌃Space; first press shows a consent prompt that spells out what the agent can do — until you accept it, nothing leaves your Mac. Routes through Anthropic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ClaudeCodeStatusRow()
            } header: {
                SectionHeader("Agent kickoff")
            }
        }
        .formStyle(.grouped)
        .padding()
        .creamSettingsBackground()
    }
}

// MARK: - Claude Code preflight (SPEC-031)

private struct ClaudeCodeStatusRow: View {
    @State private var status: AgentKickoffService.ClaudeCodeStatus?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
                .frame(width: 14, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.caption)
                if let helpLine {
                    Text(helpLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                cta
            }
            Spacer(minLength: 0)
            Button("Re-check") {
                refresh()
            }
            .buttonStyle(.borderless)
            .font(.caption2)
        }
        .task { refresh() }
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .needsUpdate, .unparseableVersion:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .notInstalled:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .none:
            ProgressView().controlSize(.mini)
        }
    }

    private var statusTitle: String {
        switch status {
        case .ok(let v): return "Claude Code: ✓ v\(v) detected"
        case .needsUpdate(let installed, let required):
            return "Claude Code: ⚠ v\(installed) — needs v\(required)+ for --bg"
        case .unparseableVersion(let raw):
            return "Claude Code: ⚠ couldn't parse version (\(raw))"
        case .notInstalled: return "Claude Code: ✗ not detected on PATH"
        case .none: return "Checking Claude Code…"
        }
    }

    private var helpLine: String? {
        switch status {
        case .ok: return nil
        case .needsUpdate:
            return "Run `claude update` in Terminal to upgrade."
        case .unparseableVersion:
            return "Try `claude update`, or reinstall from claude.com/claude-code."
        case .notInstalled:
            return "OpenQuack will fall back to clipboard when kickoff fires without claude."
        case .none: return nil
        }
    }

    @ViewBuilder
    private var cta: some View {
        switch status {
        case .notInstalled:
            Link("Install Claude Code →",
                 destination: URL(string: "https://claude.com/claude-code")!)
                .font(.caption2)
        case .needsUpdate, .unparseableVersion:
            Link("Update instructions →",
                 destination: URL(string: "https://claude.com/claude-code")!)
                .font(.caption2)
        case .ok, .none:
            EmptyView()
        }
    }

    private func refresh() {
        // Synchronous: claude --version is fast (~50ms). Off-main
        // briefly via Task so we don't block the Settings sheet
        // appearing.
        Task {
            let s = AgentKickoffService.claudeCodeStatus()
            await MainActor.run { self.status = s }
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    @ObservedObject var appState: AppState

    private static let faqs: [(q: String, a: String)] = [
        (q: "Why is the first launch slower?",
         a: "OpenQuack downloads a small speech model on first run (about 700 MB for the default size). After that it lives on disk and dictation runs entirely offline. Loading the model into memory takes a few seconds at the start of each session, then dictations are instant."),
        (q: "Why does macOS keep asking for permission after I update?",
         a: "macOS ties Accessibility and microphone grants to the app's signature. Pre-notarised builds ask again whenever the signature changes. Builds signed with a stable identity keep the grant across upgrades — that lands once Apple Developer ID is set up."),
        (q: "Where do the speech-model files live on disk?",
         a: "~/Library/Application Support/OpenQuack/WhisperKit/. Uninstalling via Homebrew with --zap clears them; manually deleting the folder is safe too."),
        (q: "Can I use a different speech model?",
         a: "Yes — Settings → Speech-to-text. Larger models are more accurate but use more disk and load more slowly. The default (medium) hits a good balance for most speech.")
    ]

    var body: some View {
        ZStack {
            CreamSurface().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.s24) {
                    hero
                    linksRow
                    faqSection
                    footer
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.s32)
                .padding(.top, Theme.s32)
                .padding(.bottom, Theme.s16)
            }
        }
        // Auto-poll on appear — `.unknown`/`.failed` fire a fresh check so
        // the user sees "Up to date" or "vX.Y ready" without clicking. The
        // poll itself respects the 24h cache for non-forced calls.
        .task {
            switch appState.updateStatus {
            case .unknown, .failed:
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.checkForUpdatesManually()
                }
            default:
                break
            }
        }
    }

    // MARK: hero — mark, wordmark, tagline, version+status line

    private var hero: some View {
        VStack(spacing: Theme.s8) {
            DuckMark(size: 88)
            Text("OpenQuack").font(.oqTitleSerif)
            Text("Speak. Send. Privately.")
                .font(.oqTaglineSerif)
                .foregroundStyle(.secondary)
            versionLine
                .padding(.top, Theme.s4)
        }
    }

    /// Single inline row: `v2.0.0-alpha.7 · ✓ Up to date` / `· vX.Y ready`.
    /// Replaces the old status card + button pair — auto-check on appear
    /// keeps it fresh without the user clicking anything.
    private var versionLine: some View {
        HStack(spacing: Theme.s8) {
            Text("v\(OpenQuackKit.version)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            updateStatusChip
        }
    }

    @ViewBuilder
    private var updateStatusChip: some View {
        switch appState.updateStatus {
        case .unknown:
            EmptyView()
        case .checking:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Checking…").font(.caption).foregroundStyle(.tertiary)
            }
        case .upToDate:
            HStack(spacing: 4) {
                Text("·").foregroundStyle(.tertiary)
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(Theme.moss)
            }
        case .available(let release):
            HStack(spacing: 4) {
                Text("·").foregroundStyle(.tertiary)
                Button {
                    UpgradeAction.run(release: release, installMethod: appState.installMethod, appState: appState)
                } label: {
                    Label("v\(release.version) ready", systemImage: "arrow.down.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.moss)
            }
        case .upgrading:
            HStack(spacing: 4) {
                Text("·").foregroundStyle(.tertiary)
                ProgressView().controlSize(.mini)
                Text("Installing…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        case .failed:
            EmptyView()
        }
    }

    // MARK: links — Tutorial replays onboarding instead of opening a URL.

    private var linksRow: some View {
        HStack(spacing: Theme.s12) {
            Link("Source",     destination: URL(string: "https://github.com/larryxiao/openquack")!)
            Text("·").foregroundStyle(.tertiary)
            Link("Vision",     destination: URL(string: "https://github.com/larryxiao/openquack/blob/main/docs/VISION.md")!)
            Text("·").foregroundStyle(.tertiary)
            Link("Benchmarks", destination: URL(string: "https://github.com/larryxiao/openquack/blob/main/docs/BENCHMARKS.md")!)
            Text("·").foregroundStyle(.tertiary)
            Button("Tutorial") {
                (NSApp.delegate as? AppDelegate)?.replayOnboarding()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .font(.callout)
    }

    // MARK: faq — collapsible rows (whole row is the hit-target, not just the chevron)

    @State private var expandedFAQs: Set<Int> = []

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: Theme.s8) {
            SectionHeader("FAQ")
                .padding(.bottom, Theme.s4)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.faqs.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 { Divider().opacity(0.25) }
                    let isOpen = expandedFAQs.contains(idx)
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isOpen { expandedFAQs.remove(idx) } else { expandedFAQs.insert(idx) }
                            }
                        } label: {
                            HStack {
                                Text(item.q)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(Theme.ink.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: Theme.s8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                            }
                            .padding(.vertical, Theme.s8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isOpen {
                            Text(item.a)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, Theme.s8)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.s12)
            .background(
                RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Text("Open source · MIT licensed · github.com/larryxiao")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, Theme.s8)
    }
}

// MARK: - Stats (SPEC-013)

private struct StatsPane: View {
    @ObservedObject var appState: AppState
    @AppStorage("showUsageStats")  private var showUsageStats: Bool = false
    @AppStorage("trackUsageStats") private var trackUsageStats: Bool = true
    @AppStorage("typingWPM")       private var typingWPM: Int = 50
    // SPEC-041 — money-saved comparison choice + custom rate.
    @AppStorage("moneySavedBaselineID")     private var moneySavedBaselineID: String = "openai-4o-transcribe"
    @AppStorage("moneySavedCustomRate")     private var moneySavedCustomRate: Double = 0.006
    @AppStorage("moneySavedCustomPerMonth") private var moneySavedCustomPerMonth: Bool = false
    private static let customBaselineID = "custom"
    @State private var snapshot: UsageStatsSnapshot?
    // SPEC-028 — recomputed when the pane appears or `showUsageStats` flips.
    // Not persisted; recomputing over ≤50 entries is microseconds.
    @State private var performance: PerformanceSummary?

    var body: some View {
        Form {
            Section {
                Toggle("Show usage statistics", isOn: $showUsageStats)
                Text("Stats are tracked locally — toggle on to reveal the numbers. Nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                SectionHeader("Display")
            }

            if showUsageStats {
                Section {
                    if let snap = snapshot {
                        statRow("Words dictated",        value: snap.wordsDictated.formatted())
                        statRow("Audio processed",       value: Self.formatDuration(snap.audioSeconds))
                        statRow("Dictations",            value: snap.dictationCount.formatted())
                        // SPEC-028 — personal performance rows. Render between
                        // "Audio processed" and "Time saved vs. typing" so the
                        // headline-friendly numbers sit with the rest of the
                        // aggregates rather than orphaned below.
                        longestDictationRow
                        processingSpeedRow
                        statRow("Time saved vs. typing", value: Self.formatDuration(snap.timeSaved(typingWordsPerMinute: typingWPM)))
                        if let since = snap.firstRecordedAt {
                            statRow("Since", value: since.formatted(date: .abbreviated, time: .omitted))
                        }
                    } else {
                        Text("Loading…").font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    SectionHeader("This Mac")
                }

                // SPEC-041 — what this much on-device dictation would have cost
                // on a paid cloud alternative. Local-only; prices baked in.
                moneySavedSection

                // SPEC-028 — length distribution. Only rendered when there's
                // at least one bucketed entry so an empty pane stays quiet.
                if let perf = performance, Self.totalBucketCount(perf) > 0 {
                    Section {
                        durationHistogram(perf)
                    } header: {
                        SectionHeader("Sessions by length")
                    }
                }

                // SPEC-036 — local-only recording-health diagnostics. Same
                // privacy stance as the rest of this pane: gathered on this Mac,
                // nothing leaves it. Gated behind the existing display toggle.
                recordingHealthSection
            }

            Section {
                Stepper("Typing speed: \(typingWPM) WPM", value: $typingWPM, in: 20...150)
                Text("Default is 50 WPM (typical desktop typist, Dhakal et al. 2018). Adjust to match yours for an honest comparison.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Track usage statistics", isOn: $trackUsageStats)
                    .onChange(of: trackUsageStats) { newValue in
                        Task { await Self.stats?.setTrackingEnabled(newValue) }
                    }
                Text("When off, OpenQuack stops counting new dictations; existing totals stay until you reset.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                SectionHeader("Tracking")
            }

            Section {
                HStack {
                    Button("Export…") { exportSnapshot() }
                        .buttonStyle(.oqNeutral)
                    Spacer()
                    Button("Reset…") { confirmReset() }
                        .buttonStyle(.oqDestructive)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .creamSettingsBackground()
        .task { await refresh() }
        .onChange(of: showUsageStats) { _ in
            Task { await refresh() }
        }
    }

    // MARK: - SPEC-041 money saved

    /// Local-only estimate of what this much on-device dictation would have cost
    /// on a paid cloud alternative. Shown only once there's audio to compare.
    @ViewBuilder
    private var moneySavedSection: some View {
        if let snap = snapshot, snap.audioSeconds > 0 {
            let basis = currentBasis
            let saved = MoneySaved.savedUSD(
                audioSeconds: snap.audioSeconds,
                firstRecordedAt: snap.firstRecordedAt,
                now: Date(),
                basis: basis
            )
            Section {
                Picker("Compared to", selection: $moneySavedBaselineID) {
                    ForEach(MoneySaved.builtIns) { b in
                        Text("\(b.label) — \(b.priceNote)").tag(b.id)
                    }
                    Text("Custom rate…").tag(Self.customBaselineID)
                }
                if moneySavedBaselineID == Self.customBaselineID {
                    HStack {
                        Text("$")
                        TextField("rate", value: $moneySavedCustomRate, format: .number)
                            .frame(width: 64)
                            .multilineTextAlignment(.trailing)
                        Picker("", selection: $moneySavedCustomPerMonth) {
                            Text("per min").tag(false)
                            Text("per month").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                    }
                }
                statRow("Money saved", value: Self.formatUSD(saved))
                Text(moneySavedMath(snap: snap, basis: basis))
                    .font(.caption).foregroundStyle(.secondary)
                Text("Estimate vs a paid alternative — OpenQuack runs on your Mac for free. Prices as of June 2026; nothing leaves your Mac.")
                    .font(.caption2).foregroundStyle(.secondary)
            } header: {
                SectionHeader("Money saved")
            }
        }
    }

    private var currentBasis: MoneySaved.Basis {
        if moneySavedBaselineID == Self.customBaselineID {
            return moneySavedCustomPerMonth
                ? .perMonth(usd: moneySavedCustomRate)
                : .perAudioMinute(usd: moneySavedCustomRate)
        }
        return MoneySaved.builtIns.first { $0.id == moneySavedBaselineID }?.basis
            ?? MoneySaved.builtIns[0].basis
    }

    private func moneySavedMath(snap: UsageStatsSnapshot, basis: MoneySaved.Basis) -> String {
        switch basis {
        case .perAudioMinute(let usd):
            let mins = snap.audioSeconds / 60.0
            return "\(Self.formatMinutes(mins)) transcribed × \(Self.formatRate(usd))/min"
        case .perMonth(let usd):
            if let months = MoneySaved.monthsActive(firstRecordedAt: snap.firstRecordedAt, now: Date()) {
                return "\(String(format: "%.1f", months)) months × \(Self.formatRate(usd))/mo"
            }
            return "\(Self.formatRate(usd))/mo"
        }
    }

    private static func formatUSD(_ usd: Double) -> String {
        usd >= 100 ? String(format: "$%.0f", usd) : String(format: "$%.2f", usd)
    }

    /// "$0.006", "$15", "$9.99" — drop trailing zeros for whole / 2dp rates.
    private static func formatRate(_ usd: Double) -> String {
        if usd == usd.rounded() { return String(format: "$%.0f", usd) }
        if (usd * 100).rounded() == usd * 100 { return String(format: "$%.2f", usd) }
        return String(format: "$%.3f", usd)
    }

    private static func formatMinutes(_ mins: Double) -> String {
        mins >= 60 ? String(format: "%.1f hours", mins / 60.0)
                   : String(format: "%.0f min", mins.rounded())
    }

    private static var stats: UsageStats? {
        (NSApp.delegate as? AppDelegate)?.usageStats
    }

    /// SPEC-028 — mirror the `stats` accessor so the pane reads from the
    /// same singleton the rest of the app uses.
    private static var history: HistoryStore? {
        (NSApp.delegate as? AppDelegate)?.historyStore
    }

    private func refresh() async {
        snapshot = await Self.stats?.snapshot()
        // SPEC-028 — pull the same 50-entry window the History pane shows
        // (also the SPEC-014 default retention cap) and recompute. No
        // caching: the summariser is pure and microseconds.
        let entries = await Self.history?.list(limit: 50) ?? []
        performance = PerformanceSummariser.summarise(entries)
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    /// SPEC-028 — duration formatter for the Longest-dictation row.
    /// Matches the spec's "6 min 12 s" / "45 s" / "1h 30m" shape (the
    /// 6 min form uses "m " + "s" to read like prose; the existing
    /// `formatDuration` writes "6m 12s" for terse aggregate rows).
    private static func formatLongestDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if total >= 60 { return "\(m) min \(s) s" }
        return "\(s) s"
    }

    /// SPEC-028 — one-decimal seconds, e.g. "3.4 s".
    private static func formatProcessSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.1f s", seconds)
    }

    /// SPEC-028 — "3.4×" under 10, "110×" at or above. Integer-round at
    /// the high end so the headline number reads cleanly.
    private static func formatRealtimeMultiple(_ rtm: Double) -> String {
        if rtm >= 10 { return "\(Int(rtm.rounded()))×" }
        return String(format: "%.1f×", rtm)
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).font(.body.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    // MARK: - SPEC-028 rows + histogram

    /// "Longest dictation  6 min 12 s · processed in 3.4 s · 110× realtime".
    /// Renders an em-dash when there is no eligible entry. The process-time
    /// tail is appended only when `processSeconds != nil`, so a mid-transcribe
    /// or recovery-flow entry still shows its duration honestly.
    private var longestDictationRow: some View {
        statRow("Longest dictation", value: longestDictationValue)
    }

    private var longestDictationValue: String {
        guard let longest = performance?.longestEntry else { return "—" }
        var pieces: [String] = [Self.formatLongestDuration(longest.durationSeconds)]
        if let proc = longest.processSeconds {
            pieces.append("processed in \(Self.formatProcessSeconds(proc))")
        }
        if let rtm = longest.realtimeMultiple {
            pieces.append("\(Self.formatRealtimeMultiple(rtm)) realtime")
        }
        return pieces.joined(separator: " · ")
    }

    /// "Processing speed  avg 47× realtime". Em-dash when no entries
    /// have a non-nil RTM yet.
    private var processingSpeedRow: some View {
        statRow("Processing speed", value: processingSpeedValue)
    }

    private var processingSpeedValue: String {
        guard let avg = performance?.averageRealtimeMultiple else { return "—" }
        return "avg \(Self.formatRealtimeMultiple(avg)) realtime"
    }

    private static func totalBucketCount(_ perf: PerformanceSummary) -> Int {
        perf.bucketCounts.values.reduce(0, +)
    }

    /// SPEC-028 — bar chart bucketed by `DurationBucket`. A fixed
    /// `maxBarWidth` (220 pt) avoids `GeometryReader` overhead inside the
    /// `Form` and keeps the bar lengths visually consistent with the rest
    /// of the pane. Zero-count rows render a 1pt-floor capsule so the row
    /// alignment stays stable even when a bucket is empty.
    private func durationHistogram(_ perf: PerformanceSummary) -> some View {
        let maxCount = max(1, perf.bucketCounts.values.max() ?? 1)
        let maxBarWidth: CGFloat = 220
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(DurationBucket.allCases, id: \.self) { bucket in
                let count = perf.bucketCounts[bucket] ?? 0
                let proportion = CGFloat(count) / CGFloat(maxCount)
                let width = max(1, maxBarWidth * proportion)
                HStack(spacing: Theme.s8) {
                    Text(bucket.rawValue)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                    Capsule()
                        .fill(Theme.amber.opacity(0.6))
                        .frame(width: width, height: 8)
                    Spacer(minLength: Theme.s8)
                    Text(count.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - SPEC-036 recording health

    /// Local-only recording-health subsection: a session incomplete-capture
    /// count, the newest recordings (wall / captured / RTF / path / lang with a
    /// warning marker when the tap stopped early), an optional compact list of
    /// warn/error diagnostic events, and a button into the existing reveal flow.
    @ViewBuilder
    private var recordingHealthSection: some View {
        Section {
            if appState.recentRecordings.isEmpty {
                Text("No recordings yet this session.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                let incomplete = appState.incompleteCaptureCount
                if incomplete > 0 {
                    HStack(spacing: Theme.s8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(incomplete) of \(appState.recentRecordings.count) recording\(appState.recentRecordings.count == 1 ? "" : "s") this session ended early (capture stopped mid-recording).")
                            .font(.caption)
                    }
                } else {
                    Text("All \(appState.recentRecordings.count) recording\(appState.recentRecordings.count == 1 ? "" : "s") this session captured cleanly.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                ForEach(appState.recentRecordings.indices, id: \.self) { i in
                    recordingHealthRow(appState.recentRecordings[i])
                }
            }

            let warnings = Self.recentWarnings()
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings.indices, id: \.self) { i in
                        let e = warnings[i]
                        Text("\(e.level.marker) [\(e.category.rawValue)] \(e.message)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            HStack {
                Button("Reveal diagnostics file") {
                    (NSApp.delegate as? AppDelegate)?.writeDiagnosticsFileAndReveal()
                }
                .buttonStyle(.oqNeutral)
                Spacer()
            }
            Text("Recording health is gathered on this Mac — durations, counts, and a detected-language code, never your transcript. Nothing leaves your Mac.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            SectionHeader("Recording health")
        }
    }

    /// One recording row: "wall / captured · RTF · path · lang", warning-marked
    /// when capture fell short.
    private func recordingHealthRow(_ r: DiagnosticsReport.LastRecording) -> some View {
        let incomplete = r.health.isIncomplete
        var tail: [String] = []
        if let rtf = DiagnosticsReport.rtf(transcribe: r.transcribeWallSeconds, audio: r.audioSeconds) {
            tail.append(String(format: "RTF %.2f", rtf))
        }
        tail.append(r.path)
        if let lang = r.detectedLanguage { tail.append("lang=\(lang)") }
        return HStack(alignment: .firstTextBaseline, spacing: Theme.s8) {
            Image(systemName: incomplete ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .foregroundStyle(incomplete ? Color.orange : .secondary)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "wall %.1fs / captured %.1fs", r.wallSeconds, r.capturedSeconds))
                    .font(.caption.monospacedDigit())
                Text(tail.joined(separator: " · "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    /// Compact warn/error tail from the diagnostics ring (newest-first, capped).
    /// `recentEvents()` returns oldest-first.
    private static func recentWarnings(limit: Int = 5) -> [DiagEvent] {
        Diagnostics.shared.recentEvents()
            .filter { $0.level == .warn || $0.level == .error }
            .suffix(limit)
            .reversed()
    }

    private func exportSnapshot() {
        Task {
            guard let stats = Self.stats else { return }
            guard let data = try? await stats.exportJSON() else { return }
            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "openquack-stats.json"
                panel.allowedContentTypes = [.json]
                if panel.runModal() == .OK, let url = panel.url {
                    try? data.write(to: url)
                }
            }
        }
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset all usage statistics?"
        alert.informativeText = "This can't be undone."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await Self.stats?.reset()
            await refresh()
        }
    }
}

// MARK: - History (SPEC-014)

private struct HistoryPane: View {
    @AppStorage("saveAudio")         private var saveAudio: Bool = false
    @AppStorage(HistorySettings.maxEntriesKey) private var maxEntries: Int = HistorySettings.defaultMaxEntries
    @State private var entries: [HistoryEntry] = []

    /// Sentinel for the "Unlimited" picker option. `RetentionPolicy` reads
    /// this verbatim — `Int.max` never triggers eviction.
    private static let unlimited = Int.max

    var body: some View {
        Form {
            Section {
                Picker("Keep transcripts", selection: $maxEntries) {
                    Text("None").tag(0)
                    Text("10 entries").tag(10)
                    Text("20 entries").tag(20)
                    Text("30 entries").tag(30)
                    Text("50 entries").tag(50)
                    Text("100 entries").tag(100)
                    Text("Unlimited").tag(Self.unlimited)
                }
                .pickerStyle(.menu)
                .onChange(of: maxEntries) { _ in
                    Task {
                        await syncPolicy()
                        await refresh()
                    }
                }
                Text(retentionFootnote)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Save audio (enables crash recovery)", isOn: $saveAudio)
                if saveAudio {
                    Text("Audio is stored locally on this Mac. Voice carries biometrics — keep this off if you share this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SectionHeader("What to save")
            }

            Section {
                if entries.isEmpty {
                    Text("No recordings yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        historyRow(entry)
                    }
                }
            } header: {
                SectionHeader("Recent")
            }

            Section {
                Button("Delete all history…") { confirmPurge() }
                    .buttonStyle(.oqDestructive)
            }
        }
        .formStyle(.grouped)
        .padding()
        .creamSettingsBackground()
        .task {
            await refresh()
            await syncPolicy()
        }
    }

    private var retentionFootnote: String {
        switch maxEntries {
        case 0:           return "Transcripts won't be saved. Crash-recovery is unaffected if Save audio is on."
        case Self.unlimited: return "Every transcript is kept until you Delete all history."
        default:          return "Older transcripts are deleted oldest-first when the count is exceeded."
        }
    }

    private static var store: HistoryStore? {
        (NSApp.delegate as? AppDelegate)?.historyStore
    }

    private func refresh() async {
        entries = await Self.store?.list(limit: 50) ?? []
    }

    /// Push the entry-cap to the store. Age and disk caps stay loose so
    /// the entry count is the only lever the user actually feels.
    private func syncPolicy() async {
        await Self.store?.setPolicy(.userConfigured(maxEntries: maxEntries))
        await Self.store?.enforceRetention()
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: Theme.s8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.recordedAt.formatted(.relative(presentation: .named)))
                    .font(.caption.weight(.medium))
                Text(entry.transcript ?? "(no transcript yet)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Menu {
                if entry.transcript != nil {
                    Button("Copy") { copyTranscript(entry) }
                }
                if entry.audioURL != nil {
                    Button("Reveal in Finder") { revealInFinder(entry) }
                }
                Button("Delete", role: .destructive) { delete(entry) }
            } label: {
                Image(systemName: "ellipsis.circle").imageScale(.medium)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func copyTranscript(_ entry: HistoryEntry) {
        guard let text = entry.transcript else { return }
        PasteService.copyToClipboard(text)
    }

    private func revealInFinder(_ entry: HistoryEntry) {
        guard let url = entry.audioURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func delete(_ entry: HistoryEntry) {
        Task {
            try? await Self.store?.delete(entry.id)
            await refresh()
        }
    }

    private func confirmPurge() {
        let alert = NSAlert()
        alert.messageText = "Permanently delete all history?"
        alert.informativeText = "Transcripts and recordings on this Mac will be removed. This cannot be undone."
        alert.addButton(withTitle: "Delete all")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            try? await Self.store?.purgeAll()
            await refresh()
        }
    }
}

// MARK: - SPEC-007 polish model download sheet

private struct PolishModelDownloadSheet: View {
    @ObservedObject var model: PolishModelDownloadController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download \(PolishModelCatalog.displayName)")
                .font(.headline)

            switch model.phase {
            case .confirming:
                Text("The local LLM polish needs a one-time \(PolishModelCatalog.sizeLabel) model download. It stays on your Mac; nothing leaves your machine.")
                    .fixedSize(horizontal: false, vertical: true)
                Link("Model license", destination: PolishModelCatalog.licenseURL)
                    .font(.caption)
                HStack {
                    Spacer()
                    Button("Cancel") { model.cancel() }
                    Button("Download") { model.confirm() }
                        .keyboardShortcut(.defaultAction)
                }
            case .downloading(let stats):
                ProgressView(value: stats.fraction)
                Text(Self.progressCaption(stats))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { model.cancel() }
                    Button("Download in Background") { model.detachToBackground() }
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { model.cancel() }
                    Button("Retry") { model.retry() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    static func progressCaption(_ s: PolishModelDownloadController.DownloadStats) -> String {
        if s.reconnecting { return "Reconnecting…" }
        var parts = ["\(Int(s.fraction * 100))% of \(PolishModelCatalog.sizeLabel)"]
        if let bps = s.bytesPerSecond {
            parts.append(String(format: "%.1f MB/s", bps / 1_000_000))
        }
        if let eta = s.eta {
            parts.append("~\(Self.formatETA(eta)) left")
        }
        return parts.joined(separator: " · ")
    }

    private static func formatETA(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s < 60 { return "\(s) sec" }
        let m = (s + 30) / 60
        return "\(m) min"
    }
}

private struct SpeechModelDownloadSheet: View {
    @ObservedObject var model: SpeechModelDownloadController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download \(SpeechModelCatalog.displayName(for: model.target))")
                .font(.headline)

            switch model.phase {
            case .idle, .confirming:
                Text("This speech model needs a one-time \(SpeechModelCatalog.sizeLabel(for: model.target)) download. It stays on your Mac and takes effect the next time OpenQuack launches.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { model.cancel() }
                    Button("Download") { model.confirm() }
                        .keyboardShortcut(.defaultAction)
                }
            case .downloading(let fraction):
                ProgressView(value: fraction)
                Text(Self.percentLabel(fraction))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { model.cancel() }
                    Button("Download in Background") { model.detachToBackground() }
                        .keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { model.cancel() }
                    Button("Retry") { model.retry() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    /// WhisperKit only exposes a lumpy completion fraction (no reliable byte
    /// rate), so we show percent only — no fabricated ETA.
    static func percentLabel(_ fraction: Double) -> String {
        fraction <= 0 ? "Starting…" : "\(Int(fraction * 100))%"
    }
}
