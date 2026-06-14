import XCTest
import AVFoundation
@testable import OpenQuackKit

/// Live-hardware test for the device-routed capture path (the one that was
/// crashing on the UGREEN USB mic). Skips when no non-default input device is
/// present so it's a no-op on CI / built-in-mic-only machines.
final class AudioRecorderDeviceTests: XCTestCase {
    func testStart_onEachInputDevice_doesNotCrashAndWritesWAV() async throws {
        let devices = AudioInputDevices.list()
        try XCTSkipIf(devices.isEmpty, "no input devices present")

        var producedAtLeastOneWAV = false
        for device in devices {
            let rec = AudioRecorder()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("oqrec-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: url) }

            // The regression we guard: the crash was an *uncatchable* ObjC
            // exception in installTap (SIGABRT). With the OQTryCatch bridge it
            // must degrade to a Swift error — never abort. Reaching the next
            // line at all (the process didn't abort) is the core proof; a throw
            // is also acceptable graceful handling.
            do {
                _ = try rec.start(outputURL: url, inputDeviceUID: device.uid)
            } catch {
                print("DEVICE \(device.name): start() degraded to error (no crash): \(error)")
                continue
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
            _ = rec.stop()

            // Any WAV that IS produced must be valid. Devices that deliver no
            // buffers in the short window (some USB webcams/virtual devices) are
            // not a failure here — they didn't crash, which is the point.
            if let f = try? AVAudioFile(forReading: url) {
                XCTAssertGreaterThan(f.fileFormat.sampleRate, 0, "device \(device.name)")
                producedAtLeastOneWAV = true
            }
        }
        XCTAssertTrue(producedAtLeastOneWAV, "expected at least one input device to capture audio")
    }
}
