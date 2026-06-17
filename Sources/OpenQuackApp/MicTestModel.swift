import SwiftUI
import OpenQuackKit

/// Drives the "Test" mic-level UI in Settings and onboarding. Wraps a
/// listen-only `MicMonitor`, publishes a sliding level window, and auto-stops
/// after a few seconds so the mic doesn't stay hot if the user wanders off.
final class MicTestModel: ObservableObject {
    @Published var isTesting = false
    @Published var levels: [Float] = Array(repeating: 0, count: MicTestModel.barCount)
    /// Flips true once a clearly-above-idle level is seen — drives the
    /// "Sounds good" confirmation.
    @Published var sawSignal = false
    /// Non-nil when the test couldn't start (permission denied, engine failed),
    /// so the UI can explain instead of silently doing nothing.
    @Published var errorMessage: String?

    static let barCount = 11
    private static let autoStopSeconds: UInt64 = 8

    private let monitor = MicMonitor()
    private var autoStopTask: Task<Void, Never>?

    func toggle(deviceUID: String) {
        isTesting ? stop() : start(deviceUID: deviceUID)
    }

    func start(deviceUID: String) {
        errorMessage = nil
        // The monitor needs mic permission just like recording does. The
        // engine won't prompt on its own, so request access first; without
        // this a notDetermined/denied state just produced "nothing happens".
        Task { [weak self] in
            let granted = await AudioRecorder.requestPermission()
            await MainActor.run {
                guard let self else { return }
                guard granted else {
                    self.errorMessage = "Microphone access is off. Enable OpenQuack in System Settings → Privacy & Security → Microphone."
                    return
                }
                self.beginMonitoring(deviceUID: deviceUID)
            }
        }
    }

    private func beginMonitoring(deviceUID: String) {
        monitor.levelHandler = { [weak self] level in self?.push(level) }
        do {
            try monitor.start(deviceUID: deviceUID)
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }
        isTesting = true
        sawSignal = false
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autoStopSeconds * 1_000_000_000)
            await MainActor.run { self?.stop() }
        }
    }

    func stop() {
        monitor.stop()
        autoStopTask?.cancel()
        autoStopTask = nil
        isTesting = false
        levels = Array(repeating: 0, count: Self.barCount)
    }

    private func push(_ level: Float) {
        var h = levels
        h.removeFirst()
        h.append(level)
        levels = h
        if level > 0.15 { sawSignal = true }   // well above the idle floor
    }

    deinit { monitor.stop() }
}

/// Small green bar meter shared by the Settings and onboarding mic tests.
struct MicLevelMeter: View {
    let levels: [Float]
    private let maxHeight: CGFloat = 20

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Theme.moss.opacity(0.85))
                    .frame(width: 3, height: max(3, min(maxHeight, CGFloat(level) * maxHeight)))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
        .frame(height: maxHeight)
    }
}
