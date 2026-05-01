import SwiftUI
import AppKit
import KeyboardShortcuts
import OpenQuackKit

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

    var body: some View {
        TabView(selection: $selection) {
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            ShortcutPane()
                .tabItem { Label("Shortcut", systemImage: "command") }
                .tag(Tab.shortcut)
            StatsPane()
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
    }
}

// MARK: - General

private struct GeneralPane: View {
    @AppStorage("autoPaste")           private var autoPaste: Bool = true
    @AppStorage("polishText")          private var polishText: Bool = true
    @AppStorage("language")            private var language: String = "en"
    @AppStorage("playSounds")          private var playSounds: Bool = true
    @AppStorage("vadAutoStop")         private var vadAutoStop: Bool = false
    @AppStorage("vadSilenceSeconds")   private var vadSilenceSeconds: Double = 1.5
    @AppStorage("customWords")         private var customWords: String = ""
    @AppStorage("model")               private var model: String = "medium"

    var body: some View {
        Form {
            Section {
                Picker("Speech model", selection: $model) {
                    Text("tiny — fastest, lowest accuracy (~150 MB)").tag("tiny")
                    Text("base — fast, modest accuracy (~290 MB)").tag("base")
                    Text("small — balanced (~480 MB)").tag("small")
                    Text("medium — best balance, default (~1.5 GB)").tag("medium")
                    Text("large-v3 — highest accuracy (~3 GB)").tag("large-v3")
                }
                Text("Takes effect on next launch. New models download in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("Speech-to-text")
            }

            Section {
                Toggle("Paste at cursor automatically", isOn: $autoPaste)
                    .help("After transcription, OpenQuack simulates ⌘V to paste into whatever app you're in. Requires Accessibility access. If off, the transcript still goes to your clipboard and you press ⌘V yourself.")
                Toggle("Smart formatting", isOn: $polishText)
                    .help("Capitalise sentences, add a period at the end, strip filler words (um, uh) before paste. Off = paste exactly what Whisper heard.")
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
                Text("Auto-detect can be unreliable on short utterances. Set this to your primary language for the most consistent results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("Language")
            }

            Section {
                Toggle("Auto-stop after silence", isOn: $vadAutoStop)
                    .help("When you stop speaking, OpenQuack finishes the recording automatically. Only applies in toggle mode — push-to-talk is already user-controlled.")
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
        }
        .formStyle(.grouped)
        .padding()
        .creamSettingsBackground()
    }
}

// MARK: - Shortcut

private struct ShortcutPane: View {
    @AppStorage("hotkeyMode") private var hotkeyMode: String = "toggle"

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Hotkey:", name: .toggleRecording)
                Text("Press once to start dictating, again to stop. ⌃⇧Space is the default and works in most apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("Global hotkey")
            }

            Section {
                Picker("Behaviour", selection: $hotkeyMode) {
                    Text("Toggle").tag("toggle")
                    Text("Push-to-talk").tag("pushToTalk")
                }
                .pickerStyle(.segmented)
                Text("Toggle: press to start, press to stop. Push-to-talk: hold to record, release to transcribe — best for short utterances.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("Mode")
            }
        }
        .formStyle(.grouped)
        .padding()
        .creamSettingsBackground()
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
                    statusCard
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
    }

    // MARK: hero — mark, wordmark, tagline

    private var hero: some View {
        VStack(spacing: Theme.s8) {
            DuckMark(size: 88)
            Text("OpenQuack").font(.oqTitleSerif)
            Text("Speak. Send. Privately.")
                .font(.oqTaglineSerif)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: status card — version, update state, primary actions

    private var statusCard: some View {
        VStack(spacing: Theme.s12) {
            HStack(spacing: Theme.s8) {
                Text("Version")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(OpenQuackKit.version)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Theme.ink.opacity(0.85))
                Spacer()
                updateStatusChip
            }
            Divider().opacity(0.35)
            HStack(spacing: Theme.s8) {
                Button(checkForUpdatesLabel) {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.checkForUpdatesManually()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isChecking)

                Button("Replay onboarding") {
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.replayOnboarding()
                    }
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(Theme.s16)
        .background(
            RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var checkForUpdatesLabel: String {
        isChecking ? "Checking…" : "Check for updates"
    }

    private var isChecking: Bool {
        if case .checking = appState.updateStatus { return true }
        return false
    }

    @ViewBuilder
    private var updateStatusChip: some View {
        switch appState.updateStatus {
        case .unknown:
            EmptyView()
        case .checking:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Checking…").font(.caption2).foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(Theme.moss)
        case .available(let release):
            Button {
                UpgradeAction.run(release: release, installMethod: appState.installMethod)
            } label: {
                Label("v\(release.version) ready", systemImage: "arrow.down.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.moss)
        case .failed:
            Label("Check failed", systemImage: "exclamationmark.triangle")
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(Theme.amber)
        }
    }

    // MARK: links

    private var linksRow: some View {
        HStack(spacing: Theme.s12) {
            Link("Source",     destination: URL(string: "https://github.com/larryxiao/openquack")!)
            Text("·").foregroundStyle(.tertiary)
            Link("Vision",     destination: URL(string: "https://github.com/larryxiao/openquack/blob/main/docs/VISION.md")!)
            Text("·").foregroundStyle(.tertiary)
            Link("Benchmarks", destination: URL(string: "https://github.com/larryxiao/openquack/blob/main/docs/BENCHMARKS.md")!)
        }
        .font(.callout)
    }

    // MARK: faq — collapsible disclosure groups

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: Theme.s8) {
            SectionHeader("FAQ")
                .padding(.bottom, Theme.s4)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.faqs.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 { Divider().opacity(0.25) }
                    DisclosureGroup {
                        Text(item.a)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Theme.s8)
                            .padding(.bottom, Theme.s8)
                    } label: {
                        Text(item.q)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.ink.opacity(0.85))
                    }
                    .padding(.vertical, Theme.s8)
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
    @AppStorage("showUsageStats")  private var showUsageStats: Bool = false
    @AppStorage("trackUsageStats") private var trackUsageStats: Bool = true
    @AppStorage("typingWPM")       private var typingWPM: Int = 50
    @State private var snapshot: UsageStatsSnapshot?

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
                    Spacer()
                    Button("Reset…") { confirmReset() }
                        .foregroundStyle(.red)
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

    private static var stats: UsageStats? {
        (NSApp.delegate as? AppDelegate)?.usageStats
    }

    private func refresh() async {
        snapshot = await Self.stats?.snapshot()
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

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).font(.body.monospacedDigit()).foregroundStyle(.secondary)
        }
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
    @AppStorage("saveTranscripts")    private var saveTranscripts: Bool = true
    @AppStorage("saveAudio")          private var saveAudio: Bool = false
    @AppStorage("historyMaxEntries")  private var maxEntries: Int = 50
    @State private var entries: [HistoryEntry] = []

    private static let entriesMin = 10
    private static let entriesMax = 500

    var body: some View {
        Form {
            Section {
                Toggle("Save transcripts", isOn: $saveTranscripts)
                Toggle("Save audio (enables crash recovery)", isOn: $saveAudio)
                if saveAudio {
                    Text("Audio is stored locally on this Mac. Voice carries biometrics — keep this off if you share this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                SectionHeader("What to save")
            }

            Section {
                HStack {
                    Text("Keep up to **\(maxEntries)** entries")
                    Spacer()
                    Button("Change…") { promptEditEntries() }
                        .controlSize(.small)
                }
                Text("Older recordings are deleted oldest-first when this limit is exceeded.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                SectionHeader("Retention")
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
                    .foregroundStyle(.red)
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

    private static var store: HistoryStore? {
        (NSApp.delegate as? AppDelegate)?.historyStore
    }

    private func refresh() async {
        entries = await Self.store?.list(limit: 50) ?? []
    }

    /// Push the entry-cap to the store. Other caps (age, disk size) stay
    /// at very loose defaults so the entry count is the only lever the
    /// user actually feels.
    private func syncPolicy() async {
        let policy = RetentionPolicy(
            maxEntries: maxEntries,
            maxAge: 365 * 24 * 60 * 60,
            maxBytesOnDisk: 5 * 1024 * 1024 * 1024
        )
        await Self.store?.setPolicy(policy)
        await Self.store?.enforceRetention()
    }

    /// Modal input for the entry cap — the stepper felt like a chore.
    private func promptEditEntries() {
        let alert = NSAlert()
        alert.messageText = "Keep up to how many entries?"
        alert.informativeText = "Pick any number between \(Self.entriesMin) and \(Self.entriesMax)."

        let field = NSTextField(string: String(maxEntries))
        field.frame = NSRect(x: 0, y: 0, width: 80, height: 24)
        field.alignment = .center
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: Self.entriesMin)
        formatter.maximum = NSNumber(value: Self.entriesMax)
        formatter.allowsFloats = false
        field.formatter = formatter
        alert.accessoryView = field

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        // Focus the text field so the user can type immediately, with the
        // current value pre-selected for quick replacement.
        DispatchQueue.main.async { [weak field] in
            field?.becomeFirstResponder()
            field?.currentEditor()?.selectAll(nil)
        }

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let raw = field.integerValue
        let clamped = min(Self.entriesMax, max(Self.entriesMin, raw))
        if clamped != maxEntries {
            maxEntries = clamped
            Task {
                await syncPolicy()
                await refresh()
            }
        }
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
                    Button("Re-paste") { rePaste(entry) }
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

    private func rePaste(_ entry: HistoryEntry) {
        guard let text = entry.transcript else { return }
        if UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true {
            _ = PasteService.paste(text)
        } else {
            PasteService.copyToClipboard(text)
        }
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
