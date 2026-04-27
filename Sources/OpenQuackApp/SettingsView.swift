import SwiftUI
import AppKit
import KeyboardShortcuts
import OpenQuackKit

// MVP Settings scene. SwiftUI TabView in an NSWindow (we don't use SwiftUI's
// App protocol so we host the view manually — see SettingsWindowController).
//
// Storage: @AppStorage on UserDefaults. Keys are the source of truth; the
// AppDelegate reads them on launch and at hotkey events. Some keys (model)
// require a relaunch to take effect — surfaced inline.

struct SettingsView: View {
    enum Tab: Hashable { case general, models, shortcut, about }
    @State private var selection: Tab = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            ModelsPane()
                .tabItem { Label("Models", systemImage: "waveform") }
                .tag(Tab.models)
            ShortcutPane()
                .tabItem { Label("Shortcut", systemImage: "command") }
                .tag(Tab.shortcut)
            AboutPane()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 520, height: 360)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @AppStorage("autoPaste") private var autoPaste: Bool = true
    @AppStorage("polishText") private var polishText: Bool = true
    @AppStorage("language") private var language: String = "en"
    @AppStorage("playSounds") private var playSounds: Bool = true
    @AppStorage("vadAutoStop") private var vadAutoStop: Bool = false
    @AppStorage("vadSilenceSeconds") private var vadSilenceSeconds: Double = 1.5
    @AppStorage("customWords") private var customWords: String = ""

    var body: some View {
        Form {
            Section {
                Toggle("Paste at cursor automatically", isOn: $autoPaste)
                    .help("After transcription, simulate ⌘V to paste into the focused app. Requires Accessibility permission.")
                Toggle("Smart formatting", isOn: $polishText)
                    .help("Capitalise sentences, add end-punctuation, strip filler words (um, uh) before paste. Off = raw Whisper output.")
                Toggle("Play sounds on start / stop", isOn: $playSounds)
                    .help("Subtle system sounds when a recording begins and ends.")
            } header: {
                Text("Behaviour")
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
                Text("Auto-detect on short clips is unreliable — see docs/BENCHMARKS.md. Set this to your primary language for best results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Language")
            }

            Section {
                Toggle("Auto-stop after silence", isOn: $vadAutoStop)
                    .help("Detect when you've finished speaking and transcribe automatically. Toggle-mode only.")
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
                Text("Voice activity")
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if customWords.isEmpty {
                        Text("e.g.\nOpenQuack\nWhisperKit\nClaude Code")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $customWords)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80, idealHeight: 100)
                        .scrollContentBackground(.hidden)
                }
                Text("One word or phrase per line. Whisper uses these as a hint to favour proper nouns, jargon, and names.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Custom dictionary")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Models

private struct ModelsPane: View {
    @AppStorage("model") private var model: String = "medium"

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
                Text("Model changes apply on next launch. Cold-start is ~10–60 s the first time a model is downloaded; subsequent launches are 5–10 s.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Speech-to-text")
            }

            Section {
                Text("On Apple M4 / 16 GB: medium hits 2.6% WER on real human speech vs 4.1% for small. See docs/BENCHMARKS.md for the full hardware × model matrix.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Why these defaults")
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
                Text("Default: ⌃⇧Space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Global hotkey")
            }

            Section {
                Picker("Behaviour", selection: $hotkeyMode) {
                    Text("Toggle (press to start, press to stop)").tag("toggle")
                    Text("Push-to-talk (hold to record)").tag("pushToTalk")
                }
                Text("Push-to-talk is best for short utterances — release the key and OpenQuack starts transcribing immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Mode")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("🦆").font(.system(size: 56))
            Text("OpenQuack").font(.title2.weight(.semibold))
            Text("v\(OpenQuackKit.version)")
                .font(.callout).foregroundStyle(.secondary)
            Text("Privacy-first local AI agent interface, accessed via voice.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            HStack(spacing: 16) {
                Link("Source",  destination: URL(string: "https://github.com/OpenQuack/openquack")!)
                Link("Vision",  destination: URL(string: "https://github.com/OpenQuack/openquack/blob/v2/docs/VISION.md")!)
                Link("Bench",   destination: URL(string: "https://github.com/OpenQuack/openquack/blob/v2/docs/BENCHMARKS.md")!)
            }
            .font(.callout)
            .padding(.top, 4)

            Spacer()

            // Replay onboarding — only useful for development. Disabled here
            // because the new onboarding needs an AppState reference; replay
            // moves to AppDelegate via a "Replay onboarding" menu (forthcoming).
            // For now: `defaults delete org.openquack.OpenQuack hasCompletedOnboarding`
            // and relaunch.
            EmptyView()

            Text("Apache 2.0").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
