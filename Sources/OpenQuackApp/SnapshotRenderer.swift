import SwiftUI
import AppKit

/// SPEC-044 — render UI surfaces to PNG so an agent (or a human) can SEE the UI
/// and validate it against the specs, locally — no launching the menu-bar app,
/// no screen-capture permissions, deterministic (fixed states, no live data).
///
/// Driven by `OQ_SNAPSHOT_DIR`: the app renders + exits instead of running.
enum SnapshotRenderer {
    static let overlaySize = CGSize(width: 320, height: 60)

    @MainActor
    static func renderAll(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var written: [String] = []
        for (name, state) in overlayStates() {
            let url = dir.appendingPathComponent("overlay-\(name).png")
            if render(OverlayPill(state: state), size: overlaySize, to: url) {
                written.append(url.lastPathComponent)
            }
        }
        FileHandle.standardError.write(
            "rendered \(written.count) snapshots → \(dir.path)\n  \(written.joined(separator: "\n  "))\n"
                .data(using: .utf8) ?? Data()
        )
    }

    /// The recording overlay (SPEC-004) in each phase, including the SPEC-036
    /// "interrupted" notice and the SPEC-031 kickoff mode.
    @MainActor
    private static func overlayStates() -> [(String, AppState)] {
        func make(_ configure: (AppState) -> Void) -> AppState {
            let a = AppState(); configure(a); return a
        }
        let wave: [Float] = [0.1, 0.2, 0.45, 0.7, 0.85, 0.6, 0.9, 0.5, 0.3, 0.55, 0.4]
        return [
            ("listening", make {
                $0.phase = .recording; $0.recordingMode = .dictation
                $0.elapsedSeconds = 3.2; $0.levelHistory = wave
            }),
            ("thinking", make {
                $0.phase = .transcribing; $0.transcriptionProgress = 0.6
            }),
            ("pasted", make {
                $0.phase = .ready; $0.recordingMode = .dictation
                $0.lastPasted = true
                $0.lastTranscript = "Hello, this is a quick test of dictation."
            }),
            ("interrupted", make {
                $0.phase = .ready; $0.recordingMode = .dictation
                $0.lastNotice = "Saved what we captured"
            }),
            ("kickoff-listening", make {
                $0.phase = .recording; $0.recordingMode = .agentKickoff
                $0.elapsedSeconds = 2.0; $0.levelHistory = wave
            }),
            ("kickoff-launched", make {
                $0.phase = .ready; $0.recordingMode = .agentKickoff
                $0.lastKickoffSucceeded = true
            }),
        ]
    }

    @MainActor
    @discardableResult
    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: url); return true } catch { return false }
    }
}
