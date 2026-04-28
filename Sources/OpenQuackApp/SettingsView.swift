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

    var body: some View {
        TabView(selection: $selection) {
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            ShortcutPane()
                .tabItem { Label("Shortcut", systemImage: "command") }
                .tag(Tab.shortcut)
            AboutPane()
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
                Picker("Whisper model", selection: $model) {
                    Text("tiny — fastest, lowest accuracy (~150 MB)").tag("tiny")
                    Text("base — fast, modest accuracy (~290 MB)").tag("base")
                    Text("small — balanced (~480 MB)").tag("small")
                    Text("medium — best balance, default (~1.5 GB)").tag("medium")
                    Text("large-v3 — highest accuracy (~3 GB)").tag("large-v3")
                }
                Text("Model changes take effect on next launch. The first time you choose a model, it downloads in the background — typically 10 – 60 s. Subsequent launches load from disk in 5 – 10 s.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader("Speech-to-text")
            }

            Section {
                Toggle("Paste at cursor automatically", isOn: $autoPaste)
                    .help("After transcription, OpenQuack simulates ⌘V to paste into whatever app you're in. Requires Accessibility access. If off, the transcript still goes to your clipboard and you press ⌘V yourself.")
                Toggle("Smart formatting", isOn: $polishText)
                    .help("Capitalise sentences, add a period at the end, strip filler words (um, uh) before paste. A heavier local-LLM polish pass that catches domain terms like 'Claude Code' is on the way. Off = paste exactly what Whisper heard.")
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
                SectionHeader("Voice activity")
            }

            Section {
                PlaceholderTextEditor(
                    text: $customWords,
                    prompt: "e.g.\nOpenQuack\nWhisperKit\nClaude Code",
                    monospaced: true,
                    minHeight: 90,
                    idealHeight: 110
                )
                Text("One word or phrase per line. Whisper uses these as a hint when deciding between similar-sounding words — useful for proper nouns, jargon, project names, and the agents you talk to (e.g. 'Claude Code').")
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
    var body: some View {
        ZStack {
            CreamSurface().ignoresSafeArea()

            VStack(spacing: Theme.s12) {
                Spacer().frame(height: Theme.s16)
                Text("🦆").font(.system(size: 96))
                Text("OpenQuack").font(.oqTitleSerif)
                Text("v\(OpenQuackKit.version)")
                    .font(.callout).foregroundStyle(.secondary)
                Text("A voice interface to your local AI agents. Privacy by default.")
                    .font(.oqTaglineSerif)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.s32)

                HStack(spacing: Theme.s16) {
                    Link("Source",  destination: URL(string: "https://github.com/OpenQuack/openquack")!)
                    Link("Vision",  destination: URL(string: "https://github.com/OpenQuack/openquack/blob/main/docs/VISION.md")!)
                    Link("Bench",   destination: URL(string: "https://github.com/OpenQuack/openquack/blob/main/docs/BENCHMARKS.md")!)
                }
                .font(.callout)
                .padding(.top, Theme.s4)

                Spacer()

                Divider().opacity(0.4).padding(.horizontal, Theme.s32)

                HStack(spacing: Theme.s12) {
                    Button("Check for updates") {
                        if let delegate = NSApp.delegate as? AppDelegate {
                            delegate.checkForUpdatesManually()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Replay onboarding") {
                        if let delegate = NSApp.delegate as? AppDelegate {
                            delegate.replayOnboarding()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, Theme.s8)

                Text("MIT")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, Theme.s8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
