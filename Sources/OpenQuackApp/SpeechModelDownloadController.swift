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
        case idle
        case confirming
        case downloading(Double)   // fraction 0…1
        case failed(String)
    }

    @Published var isPresented = false
    @Published var phase: Phase = .idle

    /// The variant the user is switching to. Drives the sheet copy and the
    /// commit target.
    private(set) var target: String = ""

    /// Set by AppDelegate so progress can drive the menu-bar banner.
    weak var appState: AppState?

    private var task: Task<Void, Never>?
    /// The "model" preference value when the current download started. Used to
    /// avoid clobbering a newer explicit selection the user made mid-download.
    private var baselineModel = ""

    /// Open the sheet for a target the picker found not-yet-downloaded. If a
    /// download is already running, re-surface it instead of resetting to confirm.
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

    /// Stop the transfer and clear all download UI. Leaves `@AppStorage("model")`
    /// untouched so the picker reverts to the previously selected model.
    /// WhisperKit keeps its partial in a resume cache; a future selection resumes.
    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
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
        phase = .downloading(0)
        let variant = target
        appState?.speechDownload = .downloading(model: variant, fraction: 0)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await WhisperKitEngine.ensureDownloaded(model: variant) { fraction in
                    Task { @MainActor in self.ingest(fraction: fraction) }
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
        phase = .idle
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

    private func ingest(fraction: Double) {
        guard case .downloading = phase else { return }
        phase = .downloading(fraction)
        appState?.speechDownload = .downloading(model: target, fraction: fraction)
    }
}
