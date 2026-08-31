import XCTest
import Foundation
@testable import OpenQuackKit

final class WhisperKitEngineCacheTests: XCTestCase {
    private var base: URL!

    override func setUp() async throws {
        try await super.setUp()
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenQuackCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        if let b = base, FileManager.default.fileExists(atPath: b.path) {
            try? FileManager.default.removeItem(at: b)
        }
        try await super.tearDown()
    }

    /// Every `.mlmodelc` in `argmaxinc/whisperkit-coreml` carries its payload in
    /// `weights/weight.bin`; the rest of the bundle is small metadata.
    private func seedWeights(for variant: String, bundles: [String] = WhisperKitEngineCacheTests.allBundles) throws {
        let fm = FileManager.default
        let model = WhisperKitEngine.localModelFolder(for: variant, downloadBase: base)
        for name in bundles {
            let weights = model.appendingPathComponent(name).appendingPathComponent("weights")
            try fm.createDirectory(at: weights, withIntermediateDirectories: true)
            try Data().write(to: weights.appendingPathComponent("weight.bin"))
        }
    }

    private static let allBundles = ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"]

    private func seedCompleteCache(for variant: String) throws {
        let fm = FileManager.default
        try seedWeights(for: variant)
        let tokenizer = WhisperKitEngine.localTokenizerFolder(for: variant, downloadBase: base)
        try fm.createDirectory(at: tokenizer, withIntermediateDirectories: true)
        try Data().write(to: tokenizer.appendingPathComponent("tokenizer.json"))
    }

    func testHasCompleteLocalCache_emptyDirReturnsFalse() {
        XCTAssertFalse(WhisperKitEngine.hasCompleteLocalCache(for: "medium", downloadBase: base))
    }

    func testHasCompleteLocalCache_fullySeededReturnsTrue() throws {
        try seedCompleteCache(for: "medium")
        XCTAssertTrue(WhisperKitEngine.hasCompleteLocalCache(for: "medium", downloadBase: base))
    }

    func testHasCompleteLocalCache_missingAudioEncoderReturnsFalse() throws {
        try seedCompleteCache(for: "medium")
        let path = WhisperKitEngine.localModelFolder(for: "medium", downloadBase: base)
            .appendingPathComponent("AudioEncoder.mlmodelc")
        try FileManager.default.removeItem(at: path)
        XCTAssertFalse(WhisperKitEngine.hasCompleteLocalCache(for: "medium", downloadBase: base))
    }

    func testHasCompleteLocalCache_missingTokenizerReturnsFalse() throws {
        try seedCompleteCache(for: "medium")
        let path = WhisperKitEngine.localTokenizerFolder(for: "medium", downloadBase: base)
            .appendingPathComponent("tokenizer.json")
        try FileManager.default.removeItem(at: path)
        XCTAssertFalse(WhisperKitEngine.hasCompleteLocalCache(for: "medium", downloadBase: base))
    }

    func testHasModelWeights_trueWhenWeightsPresentEvenWithoutTokenizer() throws {
        // No tokenizer — mirrors a fresh `ensureDownloaded` (weights only).
        try seedWeights(for: "tiny")
        XCTAssertTrue(WhisperKitEngine.hasModelWeights(for: "tiny", downloadBase: base))
        XCTAssertFalse(WhisperKitEngine.hasCompleteLocalCache(for: "tiny", downloadBase: base))
    }

    /// A torn download (cancel, quit, dropped connection) leaves the bundle
    /// directories and their small files behind but not the weight payload.
    /// That must read as "not downloaded", or the app skips its own visible
    /// download and lets WhisperKit fetch gigabytes silently at load time.
    func testHasModelWeights_falseWhenBundleDirsExistWithoutWeightFiles() throws {
        let fm = FileManager.default
        let model = WhisperKitEngine.localModelFolder(for: "tiny", downloadBase: base)
        for name in Self.allBundles {
            let bundle = model.appendingPathComponent(name)
            try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data().write(to: bundle.appendingPathComponent("model.mil"))
            try Data().write(to: bundle.appendingPathComponent("coremldata.bin"))
        }
        XCTAssertFalse(WhisperKitEngine.hasModelWeights(for: "tiny", downloadBase: base))
    }

    func testHasModelWeights_falseWhenOneBundlesWeightIsStillMissing() throws {
        try seedWeights(for: "tiny", bundles: ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc"])
        XCTAssertFalse(WhisperKitEngine.hasModelWeights(for: "tiny", downloadBase: base))
        try seedWeights(for: "tiny", bundles: ["TextDecoder.mlmodelc"])
        XCTAssertTrue(WhisperKitEngine.hasModelWeights(for: "tiny", downloadBase: base))
    }

    func testHasModelWeights_falseWhenAWeightIsMissing() throws {
        try seedCompleteCache(for: "tiny")
        let path = WhisperKitEngine.localModelFolder(for: "tiny", downloadBase: base)
            .appendingPathComponent("TextDecoder.mlmodelc")
        try FileManager.default.removeItem(at: path)
        XCTAssertFalse(WhisperKitEngine.hasModelWeights(for: "tiny", downloadBase: base))
    }

    func testDeleteModel_removesWeightsAndTokenizer() throws {
        try seedCompleteCache(for: "tiny")
        try seedCompleteCache(for: "base")
        XCTAssertTrue(WhisperKitEngine.hasCompleteLocalCache(for: "tiny", downloadBase: base))

        WhisperKitEngine.deleteModel("tiny", downloadBase: base)

        XCTAssertFalse(WhisperKitEngine.hasModelWeights(for: "tiny", downloadBase: base))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: WhisperKitEngine.localTokenizerFolder(for: "tiny", downloadBase: base).path))
        // Sibling untouched.
        XCTAssertTrue(WhisperKitEngine.hasCompleteLocalCache(for: "base", downloadBase: base))
    }

    func testHasCompleteLocalCache_isPerVariant() throws {
        try seedCompleteCache(for: "medium")
        XCTAssertTrue(WhisperKitEngine.hasCompleteLocalCache(for: "medium", downloadBase: base))
        XCTAssertFalse(WhisperKitEngine.hasCompleteLocalCache(for: "large-v3", downloadBase: base))
    }

    func testLocalModelFolder_matchesWhisperKitCacheLayout() {
        let url = WhisperKitEngine.localModelFolder(for: "medium", downloadBase: base)
        XCTAssertEqual(
            url.path,
            base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-medium").path
        )
    }

    func testLocalTokenizerFolder_matchesWhisperKitCacheLayout() {
        let url = WhisperKitEngine.localTokenizerFolder(for: "medium", downloadBase: base)
        XCTAssertEqual(
            url.path,
            base.appendingPathComponent("models/openai/whisper-medium").path
        )
    }

}
