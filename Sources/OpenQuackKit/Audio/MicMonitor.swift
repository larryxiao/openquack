import AVFoundation
import Foundation

/// Listen-only level meter for "is this mic actually picking up my voice?"
/// checks in Settings and onboarding. Unlike `AudioRecorder` it writes no
/// file and keeps no transcript — it just taps the input, computes a 0…1 UI
/// level per buffer, and hands it to `levelHandler` on the main queue.
///
/// Routes to a specific device UID (via `AudioInputDevices.route`) or the
/// system default when the UID is empty. Safe to `start`/`stop` repeatedly;
/// starting again switches device cleanly.
public final class MicMonitor {
    private let lock = NSLock()
    private var engine: AVAudioEngine?

    /// Delivered on the main queue with each buffer's UI level (0…1).
    public var levelHandler: ((Float) -> Void)?

    public init() {}

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return engine != nil
    }

    /// Begin monitoring. `deviceUID` empty/nil → system default. Throws if the
    /// audio engine can't start (e.g. no permission, no device).
    public func start(deviceUID: String? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        stopLocked()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        if let uid = deviceUID, !uid.isEmpty {
            AudioInputDevices.route(inputNode, toUID: uid)
        }
        let format = inputNode.outputFormat(forBus: 0)
        let handler = levelHandler
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            let level = AudioRecorder.uiLevel(fromRMS: AudioRecorder.rawRMS(from: buffer))
            if let handler {
                DispatchQueue.main.async { handler(level) }
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    deinit { stopLocked() }
}
