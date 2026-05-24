import Foundation
import CoreServices
import OpenQuackKit

/// SPEC-031 v3 — watches a single `~/.claude/jobs/<short>/state.json`
/// file for changes. On every write, reads + parses the JSON and
/// invokes `onState`. Debounces rapid bursts (claude writes state
/// many times per second during fast tool sequences).
///
/// Implementation: FSEventStream rooted at the *parent directory*
/// (the jobs/<short>/ dir) — FSEvents reports directory-level events,
/// not file-level. We filter by checking the target file's mtime.
///
/// The watcher MAY need to wait briefly for the directory to exist:
/// when a kickoff is dispatched, the daemon creates the jobs/<short>/
/// dir asynchronously. `start()` schedules a poll that retries until
/// the dir exists (capped at ~10 seconds) before installing the
/// FSEvent stream.
final class StateFileWatcher: @unchecked Sendable {
    private let url: URL
    private let onState: (KickoffState) -> Void

    private var stream: FSEventStreamRef?
    private var pollTimer: DispatchSourceTimer?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastState: KickoffState?
    private let queue = DispatchQueue(label: "openquack.statewatcher")

    init(url: URL, onState: @escaping (KickoffState) -> Void) {
        self.url = url
        self.onState = onState
    }

    deinit { stop() }

    func start() {
        // The jobs/<short>/ dir may not exist yet — poll until it does
        // (the daemon creates it shortly after accepting the dispatch).
        scheduleDirWaitPoll()
    }

    func stop() {
        queue.sync {
            pollTimer?.cancel()
            pollTimer = nil
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            if let s = stream {
                FSEventStreamStop(s)
                FSEventStreamInvalidate(s)
                FSEventStreamRelease(s)
                stream = nil
            }
        }
    }

    // MARK: - dir-existence poll

    private func scheduleDirWaitPoll() {
        let dir = url.deletingLastPathComponent()
        let started = Date()
        let cap: TimeInterval = 10

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: dir.path) {
                self.pollTimer?.cancel()
                self.pollTimer = nil
                self.installFSEventStream()
                // Read whatever's there right now in case the file
                // already exists with a usable state.
                self.readAndDispatch()
                return
            }
            if Date().timeIntervalSince(started) > cap {
                self.pollTimer?.cancel()
                self.pollTimer = nil
                // No state dir after 10s — daemon may have failed to
                // dispatch. The session manager will time out via its
                // own logic; we just stop polling here.
            }
        }
        pollTimer = timer
        timer.resume()
    }

    // MARK: - FSEvents

    private func installFSEventStream() {
        let dir = url.deletingLastPathComponent().path
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { (_, infoPtr, _, _, _, _) in
            guard let infoPtr else { return }
            let watcher = Unmanaged<StateFileWatcher>.fromOpaque(infoPtr)
                .takeUnretainedValue()
            watcher.fsEventFired()
        }
        let flags: FSEventStreamCreateFlags =
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
                                   | kFSEventStreamCreateFlagFileEvents
                                   | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [dir] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,  // latency seconds
            flags
        ) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    private func fsEventFired() {
        // Debounce: state.json is written in bursts during fast tool
        // sequences. Wait 100ms, then dispatch the latest state.
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.readAndDispatch() }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
    }

    private func readAndDispatch() {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let state = KickoffState.parse(data) else { return }
        // Suppress no-op re-deliveries.
        if let last = lastState, last == state { return }
        lastState = state
        onState(state)
    }
}
