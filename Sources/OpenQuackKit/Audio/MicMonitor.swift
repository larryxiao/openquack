import AVFoundation
import Foundation
import OQObjCSupport

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
        // A "Test" must verify the *selected* device — if routing fails, error
        // out rather than silently metering the system default (which would
        // give false confidence that the chosen mic works).
        if let uid = deviceUID, !uid.isEmpty,
           !AudioInputDevices.route(inputNode, toUID: uid) {
            throw RecorderError.engineFailed("could not select input device \(uid)")
        }
        engine.prepare()

        let handler = levelHandler
        let tapBlock: AVAudioNodeTapBlock = { buffer, _ in
            let level = AudioRecorder.uiLevel(fromRMS: AudioRecorder.rawRMS(from: buffer))
            if let handler {
                DispatchQueue.main.async { handler(level) }
            }
        }

        // Same exception-guarded format chain as AudioRecorder: try the hardware
        // format, then nil, then outputFormat — under OQTryCatch so a mismatch
        // can't abort the process when the user hits "Test" on a quirky mic.
        let hwFormat = inputNode.inputFormat(forBus: 0)
        let outFormat = inputNode.outputFormat(forBus: 0)
        var candidates: [AVAudioFormat?] = []
        if hwFormat.sampleRate > 0, hwFormat.channelCount > 0 { candidates.append(hwFormat) }
        candidates.append(nil)
        if outFormat.sampleRate > 0, outFormat.channelCount > 0,
           outFormat.sampleRate != hwFormat.sampleRate {
            candidates.append(outFormat)
        }

        var installed = false
        for fmt in candidates {
            let err = OQTryCatch {
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: fmt, block: tapBlock)
            }
            if err == nil { installed = true; break }
            _ = OQTryCatch { inputNode.removeTap(onBus: 0) }
        }
        guard installed else {
            throw RecorderError.engineFailed("could not install an audio tap on this input device")
        }

        do {
            try engine.start()
        } catch {
            _ = OQTryCatch { inputNode.removeTap(onBus: 0) }
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
