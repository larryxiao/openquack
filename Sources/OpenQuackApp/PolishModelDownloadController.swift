import Foundation
import Combine
import UserNotifications
import OpenQuackKit

/// Long-lived owner of the polish-model download. Held by `AppDelegate` so the
/// transfer survives sheet/window dismissal. Commits `polishEngine="llamaCpp"`
/// only on verified success; persists a "pending" intent for cross-launch
/// auto-resume; mirrors progress into `AppState` for the menu-bar banner.
@MainActor
final class PolishModelDownloadController: ObservableObject {
    enum Phase: Equatable {
        case confirming
        case downloading(DownloadStats)
        case failed(String)
    }

    struct DownloadStats: Equatable {
        var fraction: Double
        var bytesPerSecond: Double?
        var eta: TimeInterval?
        var reconnecting: Bool
    }

    @Published var isPresented = false
    @Published var phase: Phase = .confirming

    /// Cross-launch intent. Set true on the Download tap; cleared on explicit
    /// Cancel and on verified success. Plain UserDefaults (not @AppStorage —
    /// that wrapper is for Views; this is a controller).
    private var pending: Bool {
        get { UserDefaults.standard.bool(forKey: "polishModelDownloadPending") }
        set { UserDefaults.standard.set(newValue, forKey: "polishModelDownloadPending") }
    }

    /// Set by AppDelegate so progress can drive the menu-bar banner.
    weak var appState: AppState?

    private let downloader: ModelDownloading
    private var task: Task<Void, Never>?
    private var estimator = DownloadRateEstimator()
    private var baseline: Int64 = 0

    init(downloader: ModelDownloading = ModelDownloader()) {
        self.downloader = downloader
    }

    /// Open the sheet at the confirm step (picker → llama.cpp, model absent).
    func begin() {
        phase = .confirming
        isPresented = true
    }

    /// User tapped Download: persist intent and start the transfer.
    func confirm() {
        pending = true
        start()
        isPresented = true
    }

    func retry() { start() }

    /// Dismiss the sheet but keep downloading. The window-close path and the
    /// "Download in Background" button both route here.
    func detachToBackground() {
        isPresented = false
    }

    /// The only destructive path: stop, drop the partial, clear intent, revert
    /// the menu-bar banner. Leaves `polishEngine` untouched (picker reverts).
    func cancel() {
        task?.cancel()
        task = nil
        pending = false
        let partial = PolishModelCatalog.localURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)
        appState?.polishDownload = .inactive
        isPresented = false
    }

    /// Re-open the sheet on a background download (from the Settings row or the
    /// menu-bar banner click). No-op if nothing is in flight.
    func resurface() {
        guard task != nil else { return }
        isPresented = true
    }

    /// Launch hook: resume an interrupted download, or clear a stale flag.
    func reconcileOnLaunch() {
        if PolishModelCatalog.isInstalled() {
            pending = false
        } else if pending {
            start()                      // background; isPresented stays false
        }
    }

    /// Idempotent: starting while a task already runs is a no-op (re-entrancy
    /// guard for launch-resume racing a manual confirm).
    private func start() {
        guard task == nil else { return }
        estimator = DownloadRateEstimator()
        baseline = 0
        let stats = DownloadStats(fraction: 0, bytesPerSecond: nil, eta: nil, reconnecting: true)
        phase = .downloading(stats)
        appState?.polishDownload = .downloading(fraction: 0)
        let begin = Date()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.downloader.download(
                    from: PolishModelCatalog.remoteURL,
                    to: PolishModelCatalog.localURL,
                    expectedBytes: PolishModelCatalog.expectedBytes
                ) { progress in
                    Task { @MainActor in self.ingest(progress, since: begin) }
                }
                self.finishSuccessfully()
            } catch let e as DownloadError where e == .cancelled {
                self.task = nil          // cancel() already tore down state
            } catch {
                self.task = nil
                self.phase = .failed(Self.message(for: error))
                self.appState?.polishDownload = .inactive
            }
        }
    }

    private func finishSuccessfully() {
        task = nil
        pending = false
        UserDefaults.standard.set("llamaCpp", forKey: "polishEngine")
        appState?.polishDownload = .inactive
        isPresented = false
        postCompletionNotification()
    }

    private func ingest(_ progress: DownloadProgress, since start: Date) {
        guard case .downloading = phase else { return }
        if baseline == 0, progress.completed > 0 { baseline = progress.completed }
        let elapsed = Date().timeIntervalSince(start)
        estimator.add(completed: progress.completed, at: elapsed)
        phase = .downloading(DownloadStats(
            fraction: progress.fraction,
            bytesPerSecond: estimator.bytesPerSecond,
            eta: estimator.eta(completed: progress.completed, total: progress.total),
            reconnecting: progress.completed <= baseline
        ))
        appState?.polishDownload = .downloading(fraction: progress.fraction)
    }

    /// Best-effort completion notification. Requests authorization in-context
    /// (matching AgentSessionManager); if denied, the banner/row already cover it.
    private func postCompletionNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Local LLM polish ready"
            content.body = "\(PolishModelCatalog.displayName) finished downloading and is now active."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "openquack.polishmodel.ready",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private static func message(for error: Error) -> String {
        guard let d = error as? DownloadError else { return "Download failed. Please try again." }
        switch d {
        case .sizeMismatch:      return "Download was incomplete. Please try again."
        case .http(let code):    return "Server error (\(code)). Please try again."
        case .transport:         return "Network error. Check your connection and retry."
        case .cancelled:         return ""
        }
    }
}
