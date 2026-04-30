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
    enum Tab: Hashable { case general, shortcut, about }
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
    }
}

// MARK: - About

private struct AboutPane: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            CreamSurface().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    hero
                    links.padding(.top, Theme.s16)
                    actions.padding(.top, Theme.s12)

                    Divider()
                        .opacity(0.4)
                        .padding(.horizontal, Theme.s32)
                        .padding(.vertical, Theme.s24)

                    faq.padding(.horizontal, Theme.s32)

                    Spacer().frame(height: Theme.s24)
                    footer
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: hero

    private var hero: some View {
        VStack(spacing: Theme.s8) {
            Spacer().frame(height: Theme.s24)
            Text("🦆").font(.system(size: 80))
            Text("OpenQuack").font(.oqTitleSerif)
            Text("v\(OpenQuackKit.version)")
                .font(.callout).foregroundStyle(.secondary)
            Text("Speak. Send. Privately.")
                .font(.oqTaglineSerif)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.s32)
                .padding(.top, Theme.s4)
        }
    }

    private var links: some View {
        HStack(spacing: Theme.s16) {
            Link("Source",     destination: URL(string: "https://github.com/larryxiao/openquack")!)
            Link("Vision",     destination: URL(string: "https://github.com/larryxiao/openquack/blob/main/docs/VISION.md")!)
            Link("Benchmarks", destination: URL(string: "https://github.com/larryxiao/openquack/blob/main/docs/BENCHMARKS.md")!)
        }
        .font(.callout)
    }

    private var actions: some View {
        VStack(spacing: Theme.s8) {
            HStack(spacing: Theme.s12) {
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
            }

            // Inline status — keeps "Check for updates" from feeling like a
            // dead button when the user is already on the latest version.
            updateStatusLine
        }
    }

    private var checkForUpdatesLabel: String {
        isChecking ? "Checking…" : "Check for updates"
    }

    private var isChecking: Bool {
        if case .checking = appState.updateStatus { return true }
        return false
    }

    @ViewBuilder
    private var updateStatusLine: some View {
        switch appState.updateStatus {
        case .unknown:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Checking GitHub Releases…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .upToDate(let version, _):
            Label("You're on the latest — v\(version).", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(Theme.moss)
        case .available(let release):
            HStack(spacing: Theme.s8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Theme.moss)
                Text("v\(release.version) is available.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(appState.installMethod.isBrew ? "Upgrade" : "Download") {
                    UpgradeAction.run(release: release, installMethod: appState.installMethod)
                }
                .controlSize(.small)
            }
        case .failed(let message):
            Label("Couldn't check: \(message)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Theme.amber)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: faq

    private var faq: some View {
        VStack(alignment: .leading, spacing: Theme.s16) {
            SectionHeader("FAQ")
            faqItem(
                q: "Why is the first launch slower?",
                a: "OpenQuack downloads a small speech model on first run (about 700 MB for the default size). After that it lives on disk and dictation runs entirely offline. Loading the model into memory takes a few seconds at the start of each session, then dictations are instant."
            )
            faqItem(
                q: "Why does macOS keep asking for permission after I update?",
                a: "macOS ties Accessibility and microphone grants to the app's signature. Pre-notarised builds ask again whenever the signature changes. Builds signed with a stable identity keep the grant across upgrades — that lands once Apple Developer ID is set up."
            )
            faqItem(
                q: "Where do the speech-model files live on disk?",
                a: "~/Library/Application Support/OpenQuack/WhisperKit/. Uninstalling via Homebrew with --zap clears them; manually deleting the folder is safe too."
            )
            faqItem(
                q: "Can I use a different speech model?",
                a: "Yes — Settings → Speech-to-text. Larger models are more accurate but use more disk and load more slowly. The default (medium) hits a good balance for most speech."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func faqItem(q: String, a: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
            Text(q)
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.ink.opacity(0.85))
            Text(a)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: footer

    private var footer: some View {
        VStack(spacing: 4) {
            Divider().opacity(0.4).padding(.horizontal, Theme.s32)
            Text("Open source · MIT licensed · github.com/larryxiao")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, Theme.s12)
                .padding(.bottom, Theme.s16)
        }
    }
}
