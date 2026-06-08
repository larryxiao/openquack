import XCTest
@testable import OpenQuackKit

/// Serves a fixed byte buffer over a stubbed URL protocol. Honors Range (206)
/// unless `honorRange` is false (then 200, full body). `failAfter` delivers that
/// many bytes then errors, to exercise partial-preservation on failure.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var honorRange = true
    nonisolated(unsafe) static var failAfter: Int? = nil

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func stopLoading() {}

    override func startLoading() {
        let full = Self.body
        var start = 0
        var status = 200
        var headers = ["Accept-Ranges": "bytes"]
        if Self.honorRange,
           let raw = request.value(forHTTPHeaderField: "Range"),
           let s = Int(raw.components(separatedBy: "=").last?.components(separatedBy: "-").first ?? "") {
            start = min(s, full.count)
            status = 206
            headers["Content-Range"] = "bytes \(start)-\(max(full.count - 1, 0))/\(full.count)"
        }
        let slice = full.subdata(in: start..<full.count)
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        if let n = Self.failAfter {
            client?.urlProtocol(self, didLoad: slice.prefix(n))
            client?.urlProtocol(self, didFailWithError: NSError(domain: "stub", code: -1))
        } else {
            client?.urlProtocol(self, didLoad: slice)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

final class ModelDownloaderTests: XCTestCase {
    private var downloader: ModelDownloader!
    private var dest: URL!

    override func setUp() {
        super.setUp()
        StubURLProtocol.body = Data()
        StubURLProtocol.honorRange = true
        StubURLProtocol.failAfter = nil
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        downloader = ModelDownloader(session: URLSession(configuration: cfg))
        dest = FileManager.default.temporaryDirectory.appendingPathComponent("oq-dl-\(UUID().uuidString).bin")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.removeItem(at: dest.appendingPathExtension("partial"))
        super.tearDown()
    }

    private let url = URL(string: "https://example.test/model.gguf")!

    func testNormalDownloadWritesFileAndReportsProgress() async throws {
        StubURLProtocol.body = Data((0..<1000).map { UInt8($0 & 0xff) })
        var last = DownloadProgress(completed: 0, total: 0)
        try await downloader.download(from: url, to: dest, expectedBytes: 1000) { last = $0 }
        XCTAssertEqual(PolishModelCatalog.fileSize(dest), 1000)
        XCTAssertEqual(last.completed, 1000)
        XCTAssertEqual(last.total, 1000)
        XCTAssertEqual(last.fraction, 1.0, accuracy: 0.0001)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathExtension("partial").path))
    }

    func testEmitsResumeBaselineBeforeNetwork() async throws {
        StubURLProtocol.body = Data((0..<1000).map { UInt8($0 & 0xff) })
        let partial = dest.appendingPathExtension("partial")
        try StubURLProtocol.body.prefix(400).write(to: partial)
        var progresses: [DownloadProgress] = []
        try await downloader.download(from: url, to: dest, expectedBytes: 1000) { progresses.append($0) }
        // The very first callback must report the 400 bytes already on disk,
        // so the bar shows the resumed % immediately instead of 0%.
        XCTAssertEqual(progresses.first?.completed, 400)
    }

    func testSizeMismatchThrowsAndLeavesNoFinalFile() async {
        StubURLProtocol.body = Data(count: 500)   // but we claim 1000
        do {
            try await downloader.download(from: url, to: dest, expectedBytes: 1000) { _ in }
            XCTFail("expected sizeMismatch")
        } catch let e as DownloadError {
            guard case .sizeMismatch = e else { return XCTFail("wrong error: \(e)") }
        } catch { XCTFail("wrong error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }

    func testResumeFromPartialCompletes() async throws {
        StubURLProtocol.body = Data((0..<1000).map { UInt8($0 & 0xff) })
        let partial = dest.appendingPathExtension("partial")
        try StubURLProtocol.body.prefix(400).write(to: partial)
        try await downloader.download(from: url, to: dest, expectedBytes: 1000) { _ in }
        XCTAssertEqual(try Data(contentsOf: dest), StubURLProtocol.body)
    }

    func testServerIgnoresRangeStartsFresh() async throws {
        StubURLProtocol.body = Data((0..<1000).map { UInt8($0 & 0xff) })
        StubURLProtocol.honorRange = false
        let partial = dest.appendingPathExtension("partial")
        try Data(count: 400).write(to: partial)
        try await downloader.download(from: url, to: dest, expectedBytes: 1000) { _ in }
        XCTAssertEqual(try Data(contentsOf: dest), StubURLProtocol.body)
    }

    func testTransportFailurePreservesExistingPartial() async {
        StubURLProtocol.body = Data((0..<1000).map { UInt8($0 & 0xff) })
        StubURLProtocol.failAfter = 0   // send 206 response, then fail before finishing
        let partial = dest.appendingPathExtension("partial")
        try? Data(count: 400).write(to: partial)   // a partial from a prior interrupted attempt
        do {
            try await downloader.download(from: url, to: dest, expectedBytes: 1000) { _ in }
            XCTFail("expected a transport failure")
        } catch { /* expected */ }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path), "no final file on failure")
        XCTAssertEqual(PolishModelCatalog.fileSize(partial), 400,
                       "the downloader must not delete the partial on a transport failure (retry resumes it)")
    }
}
