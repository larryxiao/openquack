import AVFoundation
import CoreAudio
import Foundation

/// A selectable audio input device. `uid` is the persistent identifier
/// (stable across reboots and re-plugs); the numeric `id` is only valid for
/// the current boot and must be re-resolved from the `uid` before use.
public struct AudioInputDevice: Identifiable, Sendable, Equatable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String

    public init(id: AudioDeviceID, uid: String, name: String) {
        self.id = id
        self.uid = uid
        self.name = name
    }
}

/// CoreAudio enumeration of input-capable devices. Used by the Settings
/// "Microphone" picker and by `AudioRecorder` to route capture to a chosen
/// device instead of the system default.
public enum AudioInputDevices {

    /// All input-capable devices currently present, in CoreAudio order.
    public static func list() -> [AudioInputDevice] {
        allDeviceIDs()
            .filter { inputChannelCount($0) > 0 }
            .compactMap { id in
                guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                      let name = stringProperty(id, kAudioObjectPropertyName)
                else { return nil }
                return AudioInputDevice(id: id, uid: uid, name: name)
            }
    }

    /// Resolve a persistent UID back to the current-boot AudioDeviceID, or nil
    /// if that device is no longer present (unplugged, removed).
    public static func deviceID(forUID uid: String) -> AudioDeviceID? {
        list().first { $0.uid == uid }?.id
    }

    /// Route an `AVAudioEngine` input node to the device identified by `uid`.
    /// Must be called before reading the node's format — the format follows
    /// whatever device is current. Returns true on success; false (leaving the
    /// system default in place) if the UID is empty/unresolved or the audio
    /// unit rejects the change. Shared by `AudioRecorder` and `MicMonitor`.
    @discardableResult
    public static func route(_ inputNode: AVAudioInputNode, toUID uid: String) -> Bool {
        guard !uid.isEmpty,
              let deviceID = deviceID(forUID: uid),
              let unit = inputNode.audioUnit
        else { return false }
        var dev = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &dev,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        return status == noErr
    }

    // MARK: - CoreAudio helpers

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0
        else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr
        else { return 0 }
        let listPtr = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self))
        return listPtr.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(
        _ id: AudioDeviceID, _ selector: AudioObjectPropertySelector
    ) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cf: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cf) { ptr -> OSStatus in
            ptr.withMemoryRebound(to: CFString.self, capacity: 1) { rebound in
                AudioObjectGetPropertyData(id, &addr, 0, nil, &size, rebound)
            }
        }
        guard status == noErr, let result = cf else { return nil }
        return result as String
    }
}
