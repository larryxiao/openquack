import Foundation
import OpenQuackKit

/// Drives the Settings download sheet. Commits `polishEngine = "llamaCpp"` only
/// on a verified successful download; cancel/failure leaves the setting (and so
/// the picker) untouched.
@MainActor
final class PolishModelDownload: ObservableObject {
    enum Phase: Equatable {
        case confirming
        case downloading(Double)
        case failed(String)
    }

    @Published var isPresented = false
    @Published var phase: Phase = .confirming

    private let downloader: ModelDownloading
    private var task: Task<Void, Never>?

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
        phase = .downloading(0)
        task = Task {
            do {
                try await downloader.download(
                    from: PolishModelCatalog.remoteURL,
                    to: PolishModelCatalog.localURL,
                    expectedBytes: PolishModelCatalog.expectedBytes
                ) { fraction in
                    Task { @MainActor in
                        if case .downloading = self.phase { self.phase = .downloading(fraction) }
                    }
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
