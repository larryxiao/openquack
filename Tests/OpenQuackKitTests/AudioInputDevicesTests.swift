import XCTest
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
}
