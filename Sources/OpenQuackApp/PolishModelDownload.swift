import Foundation
import OpenQuackKit

/// Drives the Settings download sheet. Commits `polishEngine = "llamaCpp"` only
/// on a verified successful download; cancel/failure leaves the setting (and so
/// the picker) untouched.
@MainActor
final class PolishModelDownload: ObservableObject {
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

    private let downloader: ModelDownloading
    private var task: Task<Void, Never>?
    private var estimator = DownloadRateEstimator()
    private var baseline: Int64 = 0

    init(downloader: ModelDownloading = ModelDownloader()) {
        self.downloader = downloader
    }

    /// Open the sheet at the confirm step (model not installed, user picked llama.cpp).
    func begin() {
        phase = .confirming
        isPresented = true
    }

    func confirm() {
        task?.cancel()
        estimator = DownloadRateEstimator()
        baseline = 0
        phase = .downloading(DownloadStats(fraction: 0, bytesPerSecond: nil, eta: nil, reconnecting: true))
        let start = Date()
        task = Task {
            do {
                try await downloader.download(
                    from: PolishModelCatalog.remoteURL,
                    to: PolishModelCatalog.localURL,
                    expectedBytes: PolishModelCatalog.expectedBytes
                ) { progress in
                    Task { @MainActor in self.ingest(progress, since: start) }
                }
                UserDefaults.standard.set("llamaCpp", forKey: "polishEngine")
                isPresented = false
            } catch let e as DownloadError where e == .cancelled {
                // cancel() owns teardown.
            } catch {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    /// Fold one progress sample into the published stats. The first sample is
    /// the resume baseline (emitted before the network call); `reconnecting`
    /// stays true until a sample arrives with more bytes than that baseline.
    private func ingest(_ progress: DownloadProgress, since start: Date) {
        guard case .downloading = phase else { return }
        if baseline == 0, progress.completed > 0 { baseline = progress.completed }
        let elapsed = Date().timeIntervalSince(start)
        estimator.add(completed: progress.completed, at: elapsed)
        let reconnecting = progress.completed <= baseline
        phase = .downloading(DownloadStats(
            fraction: progress.fraction,
            bytesPerSecond: estimator.bytesPerSecond,
            eta: estimator.eta(completed: progress.completed, total: progress.total),
            reconnecting: reconnecting
        ))
    }

    func retry() { confirm() }

    /// User cancelled or dismissed: stop, drop the partial, leave polishEngine
    /// untouched so the picker reverts to its previous value.
    func cancel() {
        task?.cancel()
        task = nil
        let partial = PolishModelCatalog.localURL.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)
        isPresented = false
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
