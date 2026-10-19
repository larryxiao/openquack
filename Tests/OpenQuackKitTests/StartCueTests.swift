import XCTest
import AVFoundation
@testable import OpenQuackKit

final class StartCueTests: XCTestCase {
    private let sampleRate = 48_000.0

    private func writeFile(seconds: Double, fill: (Int) -> Float) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("startcue-\(UUID().uuidString).caf")
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        for i in 0..<Int(frames) { buf.floatChannelData![0][i] = fill(i) }
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        try file.write(from: buf)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAudibleDuration_clickPaddedWithSilence_endsAtClick() throws {
        let clickFrames = Int(0.05 * sampleRate)
        let url = try writeFile(seconds: 0.5) { i in i < clickFrames ? 0.8 : 0 }
        let d = try XCTUnwrap(StartCue.audibleDuration(of: url))
        XCTAssertEqual(d, 0.05, accuracy: 0.001)
    }

    func testAudibleDuration_tailBelowFloor_isIgnored() throws {
        let clickFrames = Int(0.05 * sampleRate)
        let url = try writeFile(seconds: 0.5) { i in i < clickFrames ? 0.8 : 0.8 * 0.0001 }
        let d = try XCTUnwrap(StartCue.audibleDuration(of: url))
        XCTAssertEqual(d, 0.05, accuracy: 0.001)
    }

    func testAudibleDuration_allSilent_isZero() throws {
        let url = try writeFile(seconds: 0.2) { _ in 0 }
        XCTAssertEqual(StartCue.audibleDuration(of: url), 0)
    }

    func testAudibleDuration_unreadableFile_isNil() {
        XCTAssertNil(StartCue.audibleDuration(of: URL(fileURLWithPath: "/nonexistent.aiff")))
    }
}
