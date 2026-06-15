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

    private func seedCompleteCache(for variant: String) throws {
        let fm = FileManager.default
        let model = WhisperKitEngine.localModelFolder(for: variant, downloadBase: base)
        for name in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            try fm.createDirectory(at: model.appendingPathComponent(name), withIntermediateDirectories: true)
        }
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
        let fm = FileManager.default
        let model = WhisperKitEngine.localModelFolder(for: "tiny", downloadBase: base)
        for name in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            try fm.createDirectory(at: model.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        // No tokenizer — mirrors a fresh `ensureDownloaded` (weights only).
        XCTAssertTrue(WhisperKitEngine.hasModelWeights(for: "tiny", downloadBase: base))
        XCTAssertFalse(WhisperKitEngine.hasCompleteLocalCache(for: "tiny", downloadBase: base))
    }

    func testHasModelWeights_falseWhenAWeightIsMissing() throws {
        try seedCompleteCache(for: "tiny")
        let path = WhisperKitEngine.localModelFolder(for: "tiny", downloadBase: base)
            .appendingPathComponent("TextDecoder.mlmodelc")
        try FileManager.default.removeItem(at: path)
        XCTAssertFalse(WhisperKitEngine.hasModelWeights(for: "tiny", downloadBase: base))
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

    func testCleanupOtherModels_keepsActiveAndDeletesSiblings() throws {
        let fm = FileManager.default
        let weightsRoot = WhisperKitEngine.localModelFolder(for: "x", downloadBase: base)
            .deletingLastPathComponent()
        let tokenizerRoot = WhisperKitEngine.localTokenizerFolder(for: "x", downloadBase: base)
            .deletingLastPathComponent()
        for variant in ["medium", "tiny", "large-v3"] {
            try fm.createDirectory(at: weightsRoot.appendingPathComponent("openai_whisper-\(variant)"),
                                    withIntermediateDirectories: true)
            try fm.createDirectory(at: tokenizerRoot.appendingPathComponent("whisper-\(variant)"),
                                    withIntermediateDirectories: true)
        }

        _ = WhisperKitEngine.cleanupOtherModels(keeping: "medium", downloadBase: base)

        XCTAssertTrue(fm.fileExists(atPath: weightsRoot.appendingPathComponent("openai_whisper-medium").path))
        XCTAssertFalse(fm.fileExists(atPath: weightsRoot.appendingPathComponent("openai_whisper-tiny").path))
        XCTAssertFalse(fm.fileExists(atPath: weightsRoot.appendingPathComponent("openai_whisper-large-v3").path))
        XCTAssertTrue(fm.fileExists(atPath: tokenizerRoot.appendingPathComponent("whisper-medium").path))
        XCTAssertFalse(fm.fileExists(atPath: tokenizerRoot.appendingPathComponent("whisper-tiny").path))
    }
}
