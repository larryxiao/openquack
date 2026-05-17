import SwiftUI
import AppKit
import KeyboardShortcuts
import os
import ServiceManagement
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
    @AppStorage("chineseScript")       private var chineseScript: String = "auto"
    @AppStorage("playSounds")          private var playSounds: Bool = true
    @AppStorage("vadAutoStop")         private var vadAutoStop: Bool = false
    @AppStorage("vadSilenceSeconds")   private var vadSilenceSeconds: Double = 1.5
    @AppStorage("customWords")         private var customWords: String = ""
    @AppStorage("model")               private var model: String = "medium"
    @AppStorage("launchAtLogin")       private var launchAtLogin: Bool = false

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

                if language == "zh" {
                    Picker("Chinese script", selection: $chineseScript) {
                        Text("Auto (Whisper default — often Traditional)").tag("auto")
                        Text("Simplified (zh-Hans)").tag("simplified")
                        Text("Traditional (zh-Hant)").tag("traditional")
                    }
                    .help("Whisper's Chinese output mixes Simplified and Traditional. Pick one to force a script.")
                    Text("Character-level conversion only — region-specific vocabulary (e.g. 软件 vs. 軟體) isn't rewritten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        }
        .onChange(of: launchAtLogin) { newValue in
            handleLaunchAtLoginChange(newValue)
        }
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
                KeyboardShortcuts.Recorder("Hotkey:", name: .toggleRecording)
                Text("Press once to start dictating, again to stop. ⌃⇧Space is the default and works in most apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("Global hotkey")
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
                    UpgradeAction.run(release: release, installMethod: appState.installMethod)
                } label: {
                    Label("v\(release.version) ready", systemImage: "arrow.down.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.moss)
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

                // SPEC-028 — length distribution. Only rendered when there's
                // at least one bucketed entry so an empty pane stays quiet.
                if let perf = performance, Self.totalBucketCount(perf) > 0 {
                    Section {
                        durationHistogram(perf)
                    } header: {
                        SectionHeader("Sessions by length")
                    }
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
    @AppStorage("historyMaxEntries") private var maxEntries: Int = 50
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
        let policy = RetentionPolicy(
            maxEntries: maxEntries,
            maxAge: 365 * 24 * 60 * 60,
            maxBytesOnDisk: 5 * 1024 * 1024 * 1024
        )
        await Self.store?.setPolicy(policy)
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
