import Foundation

public enum DownloadError: Error, Equatable {
    case sizeMismatch(got: Int64, expected: Int64)
    case http(Int)
    case transport(String)
    case cancelled
}

public protocol ModelDownloading: Sendable {
    func download(from url: URL, to dest: URL, expectedBytes: Int64,
                  onProgress: @escaping @Sendable (Double) -> Void) async throws
}

/// Streams a file to `<dest>.partial` (resuming via Range if a partial exists),
/// verifies the byte count, then atomically moves it to `dest`. Any failure
/// leaves the `.partial` in place so a retry can resume; the caller deletes it
/// on user-cancel.
public struct ModelDownloader: ModelDownloading {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func download(from url: URL, to dest: URL, expectedBytes: Int64,
                         onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        let partial = dest.appendingPathExtension("partial")
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        var have = PolishModelCatalog.fileSize(partial) ?? 0
        if have > expectedBytes { try? fm.removeItem(at: partial); have = 0 }

        var req = URLRequest(url: url)
        if have > 0 { req.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }

        let delegate = DownloadDelegate(partial: partial, expectedBytes: expectedBytes,
                                        alreadyHave: have, onProgress: onProgress)
        let task = session.dataTask(with: req)
        task.delegate = delegate

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                delegate.finish = { result in c.resume(with: result) }
                if Task.isCancelled {
                    delegate.finish?(.failure(DownloadError.cancelled))
                    delegate.finish = nil
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }

        let finalSize = PolishModelCatalog.fileSize(partial) ?? -1
        guard finalSize == expectedBytes else {
            try? fm.removeItem(at: partial)
            throw DownloadError.sizeMismatch(got: finalSize, expected: expectedBytes)
        }
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: partial, to: dest)
    }
}

/// URLSession data delegate: appends chunks to the partial file, tracks progress,
/// resets to a fresh file if the server ignored our Range (200 instead of 206).
/// `@unchecked Sendable` is safe because URLSession serializes a task's delegate
/// callbacks onto one queue — the mutable state is never touched concurrently.
private final class DownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let partial: URL
    private let expectedBytes: Int64
    private let onProgress: @Sendable (Double) -> Void
    private var handle: FileHandle?
    private var received: Int64
    var finish: ((Result<Void, Error>) -> Void)?

    init(partial: URL, expectedBytes: Int64, alreadyHave: Int64,
         onProgress: @escaping @Sendable (Double) -> Void) {
        self.partial = partial
        self.expectedBytes = expectedBytes
        self.received = alreadyHave
        self.onProgress = onProgress
        super.init()
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let fm = FileManager.default
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 206:
            if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }
        case 200:
            try? fm.removeItem(at: partial)
            fm.createFile(atPath: partial.path, contents: nil)
            received = 0
        default:
            let f = finish; finish = nil
            completionHandler(.cancel)
            f?(.failure(DownloadError.http(code)))
            return
        }
        handle = try? FileHandle(forWritingTo: partial)
        _ = try? handle?.seekToEnd()
        completionHandler(.allow)
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let handle else { return }
        // A write failure (e.g. disk full) stops appending; the final size check then fails → sizeMismatch.
        do { try handle.write(contentsOf: data) } catch { return }
        received += Int64(data.count)
        onProgress(min(1.0, Double(received) / Double(expectedBytes)))
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        guard let finish else { return }
        self.finish = nil
        if let error {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                finish(.failure(DownloadError.cancelled))
            } else {
                finish(.failure(DownloadError.transport(error.localizedDescription)))
            }
        } else {
            finish(.success(()))
        }
    }
}
