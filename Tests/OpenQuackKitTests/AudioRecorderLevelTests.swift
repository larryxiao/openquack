import XCTest
import AVFoundation
@testable import OpenQuackKit

final class AudioRecorderLevelTests: XCTestCase {
    private let sampleRate = 16_000.0
    private let frames: AVAudioFrameCount = 1_600   // 0.1 s

    private func buffer(fill: (Int) -> Float) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: sampleRate,
                                channels: 1,
                                interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        let ch = buf.floatChannelData![0]
        for i in 0..<Int(frames) { ch[i] = fill(i) }
        return buf
    }

    func testRawRMS_silentBuffer_isBelowSilenceThreshold() {
        let buf = buffer { _ in 0 }
        let rms = AudioRecorder.rawRMS(from: buf)
        XCTAssertLessThan(rms, AudioRecorder.silenceRMSThreshold)
    }

    func testRawRMS_veryQuietNoise_isBelowSilenceThreshold() {
        // Ambient floor (~0.002 amplitude) should not count as speech.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        let buf = buffer { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let unit = Float(seed >> 40) / Float(1 << 24) * 2 - 1  // -1…1
            return unit * 0.002
        }
        let rms = AudioRecorder.rawRMS(from: buf)
        XCTAssertLessThan(rms, AudioRecorder.silenceRMSThreshold)
    }

    func testRawRMS_conversationalSine_isAboveSilenceThreshold() {
        // Amplitude 0.05 → RMS ≈ 0.035, squarely in conversational range.
        let buf = buffer { i in 0.05 * sin(2 * .pi * 220 * Float(i) / Float(sampleRate)) }
        let rms = AudioRecorder.rawRMS(from: buf)
        XCTAssertGreaterThan(rms, AudioRecorder.silenceRMSThreshold)
        XCTAssertEqual(rms, 0.05 / Float(2).squareRoot(), accuracy: 0.01)  // A/√2
    }

    func testUILevel_isClampedAndMonotonic() {
        XCTAssertEqual(AudioRecorder.uiLevel(fromRMS: 0), 0, accuracy: 1e-6)
        let quiet = AudioRecorder.uiLevel(fromRMS: 0.02)
        let loud = AudioRecorder.uiLevel(fromRMS: 0.1)
        XCTAssertGreaterThan(loud, quiet)
        XCTAssertLessThanOrEqual(AudioRecorder.uiLevel(fromRMS: 5.0), 1.0)  // clamps
        XCTAssertGreaterThanOrEqual(AudioRecorder.uiLevel(fromRMS: 0), 0.0)
    }
}
