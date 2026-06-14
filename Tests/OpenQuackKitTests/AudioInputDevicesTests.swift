import XCTest
import AVFoundation
@testable import OpenQuackKit

final class AudioInputDevicesTests: XCTestCase {
    // Hardware-independent: a bogus UID must never resolve, on any host
    // (including CI boxes with no audio input devices at all).
    func testDeviceID_forUnknownUID_isNil() {
        XCTAssertNil(AudioInputDevices.deviceID(forUID: "__definitely_not_a_real_device_uid__"))
        XCTAssertNil(AudioInputDevices.deviceID(forUID: ""))
    }

    // list() must not crash and every returned device must carry a non-empty
    // uid/name and at least one input channel. Empty is a valid result on a
    // host with no mic.
    func testList_returnsWellFormedDevices() {
        for device in AudioInputDevices.list() {
            XCTAssertFalse(device.uid.isEmpty, "device uid should be non-empty")
            XCTAssertFalse(device.name.isEmpty, "device name should be non-empty")
        }
    }

    // Any device list() reports must round-trip through deviceID(forUID:).
    func testListedDevices_resolveByUID() {
        for device in AudioInputDevices.list() {
            XCTAssertEqual(AudioInputDevices.deviceID(forUID: device.uid), device.id)
        }
    }

    // Routing to an unknown/empty UID must fail (and leave the default in place),
    // never crash — short-circuits before touching the audio unit.
    func testRoute_withUnknownOrEmptyUID_returnsFalse() {
        let engine = AVAudioEngine()
        XCTAssertFalse(AudioInputDevices.route(engine.inputNode, toUID: "__definitely_not_a_real_device_uid__"))
        XCTAssertFalse(AudioInputDevices.route(engine.inputNode, toUID: ""))
    }

    // A freshly constructed monitor is idle.
    func testMicMonitor_initIsNotRunning() {
        XCTAssertFalse(MicMonitor().isRunning)
    }
}
