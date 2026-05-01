import Foundation
import Darwin

/// Current resident set size of the process, in bytes.
public func currentRSSBytes() -> Int64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
    )
    let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
        }
    }
    return kr == KERN_SUCCESS ? Int64(info.resident_size) : 0
}

/// Polls `currentRSSBytes()` on a background queue and tracks the peak. Cheap;
/// 100 ms cadence is plenty for transcription latencies measured in seconds.
public final class RSSSampler {
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var peak: Int64 = 0
    private let intervalMs: Int

    public init(intervalMs: Int = 100) {
        self.intervalMs = intervalMs
    }

    public func start() {
        let initial = currentRSSBytes()
        lock.lock(); peak = initial; lock.unlock()

        let q = DispatchQueue(label: "openquack.rss-sampler", qos: .utility)
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(
            deadline: .now() + .milliseconds(intervalMs),
            repeating: .milliseconds(intervalMs),
            leeway: .milliseconds(20)
        )
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let rss = currentRSSBytes()
            self.lock.lock()
            if rss > self.peak { self.peak = rss }
            self.lock.unlock()
        }
        t.resume()
        self.timer = t
    }

    /// Stops sampling and returns the peak observed since `start()`.
    @discardableResult
    public func stop() -> Int64 {
        timer?.cancel()
        timer = nil
        lock.lock()
        let p = peak
        lock.unlock()
        return p
    }
}
