import Foundation
import Combine
import OpenQuackKit

/// Long-lived owner of the Whisper speech-model download. Held by `AppDelegate`
/// so the transfer survives sheet/window dismissal. Commits the new
/// `@AppStorage("model")` value only on verified success; mirrors progress into
/// `AppState` for the menu-bar banner. The model takes effect on next launch
/// (no live engine hot-swap) — the existing `warmTranscriber` path loads it.
@MainActor
final class SpeechModelDownloadController: ObservableObject {
    enum Phase: Equatable {
        case confirming
        case downloading(Stats)
        case failed(String)
    }

    struct Stats: Equatable {
        var fraction: Double
        var eta: TimeInterval?
        var reconnecting: Bool
    }

    @Published var isPresented = false
    @Published var phase: Phase = .confirming

    /// The variant the user is switching to. Drives the sheet copy and the
    /// commit target.
    private(set) var target: String = ""

    /// Set by AppDelegate so progress can drive the menu-bar banner.
    weak var appState: AppState?

    private var task: Task<Void, Never>?
    private var estimator = DownloadRateEstimator()
    /// The "model" preference value when the current download started. Used to
    /// avoid clobbering a newer explicit selection the user made mid-download.
    private var baselineModel = ""

    /// Fraction (0…1) is scaled onto this nominal unit count so the
    /// byte-oriented `DownloadRateEstimator` can produce a time-to-completion.
    private static let etaScale: Int64 = 1_000_000

    /// Open the sheet for a target the picker found uncached. If a download is
    /// already running, re-surface it instead of resetting to the confirm step.
    func begin(target: String) {
        guard task == nil else { resurface(); return }
        self.target = target
        phase = .confirming
        isPresented = true
    }

    /// User tapped Download.
    func confirm() {
        start()
        isPresented = true
    }

    func retry() { start() }

    /// Dismiss the sheet but keep downloading. The window-close path and the
    /// "Download in Background" button both route here.
    func detachToBackground() {
        isPresented = false
    }

    /// Stop the transfer. Leaves `@AppStorage("model")` untouched so the picker
    /// reverts to the previously selected model. WhisperKit owns its own partial
    /// cache; a half-finished download is harmless (next launch's cache check
    /// fails and re-downloads).
    func cancel() {
        task?.cancel()
        task = nil
        appState?.speechDownload = .inactive
        isPresented = false
    }

    /// Re-open the sheet on a background download (from the Settings row or the
    /// menu-bar banner click). No-op if nothing is in flight.
    func resurface() {
        guard task != nil else { return }
        isPresented = true
    }

    /// True when a sheet-backed download is in flight (one the user can re-open).
    /// Launch-time downloads drive the banner without a controller task, so the
    /// banner hides its "Show" button for those.
    var canResurface: Bool { task != nil }

    /// Idempotent: starting while a task already runs is a no-op.
    private func start() {
        guard task == nil else { return }
        baselineModel = UserDefaults.standard.string(forKey: "model") ?? "medium"
        estimator = DownloadRateEstimator()
        phase = .downloading(Stats(fraction: 0, eta: nil, reconnecting: true))
        appState?.speechDownload = .downloading(fraction: 0)
        let begin = Date()
        let variant = target
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await WhisperKitEngine.ensureDownloaded(model: variant) { fraction in
                    Task { @MainActor in self.ingest(fraction: fraction, since: begin) }
                }
                self.finishSuccessfully()
            } catch {
                // A user cancel tears down state in cancel(); detect it via the
                // task's flag. `ensureDownloaded` currently absorbs
                // CancellationError, but guard on it too so this stays correct
                // if that ever changes.
                if Task.isCancelled || error is CancellationError { self.task = nil; return }
                self.task = nil
                self.phase = .failed("Download failed. Check your connection and retry.")
                self.appState?.speechDownload = .inactive
            }
        }
    }

    private func finishSuccessfully() {
        task = nil
        // Adopt the freshly downloaded model only if the user hasn't switched to
        // another model while this ran — their later choice wins. The download
        // still completed, so the model stays cached for a future selection.
        let current = UserDefaults.standard.string(forKey: "model") ?? "medium"
        if current == baselineModel {
            UserDefaults.standard.set(target, forKey: "model")
        }
        appState?.speechDownload = .inactive
        isPresented = false
    }

    private func ingest(fraction: Double, since start: Date) {
        guard case .downloading = phase else { return }
        let elapsed = Date().timeIntervalSince(start)
        let completed = Int64(fraction * Double(Self.etaScale))
        estimator.add(completed: completed, at: elapsed)
        phase = .downloading(Stats(
            fraction: fraction,
            eta: estimator.eta(completed: completed, total: Self.etaScale),
            reconnecting: fraction <= 0
        ))
        appState?.speechDownload = .downloading(fraction: fraction)
    }
}
