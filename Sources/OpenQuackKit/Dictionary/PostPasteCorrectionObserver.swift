import ApplicationServices
import AppKit
import Foundation

/// SPEC-022 §2.2 — Post-paste field observer.
///
/// One instance per paste. After OpenQuack pastes `transcript` at the cursor:
///
/// 1. `start(transcript:)` snapshots the focused element's `kAXValueAttribute`
///    (the field content including the just-pasted transcript).
/// 2. We register an `AXObserver` for `kAXValueChangedNotification` on that
///    element, plus a system-wide observer for
///    `kAXFocusedUIElementChangedNotification` so we know when the user moves
///    on.
/// 3. On focus-change or a 60 s timeout, we read the element's value one final
///    time, unregister, compute the edited segment via longest-common-prefix
///    of the pasted transcript and the captured text, diff it (§2.3), and
///    forward any candidates to the store.
///
/// The observer is scoped to a single element and a single paste event — it
/// does not persist across focus changes or new transcriptions. Fields that
/// don't expose `kAXValueAttribute` (password fields, some Electron apps)
/// trigger a silent no-op (SPEC §2.2 + Out-of-scope).
public final class PostPasteCorrectionObserver {
    private let store: CorrectionCandidateStore
    private let timeoutSeconds: TimeInterval

    private var pastedTranscript: String?
    private var focusedElement: AXUIElement?
    private var elementObserver: AXObserver?
    private var systemObserver: AXObserver?
    private var timer: DispatchSourceTimer?
    private var didFire = false

    /// Stored so the C callbacks can find us — `AXObserverCreate` only gives
    /// us a raw pointer round-trip.
    private static var liveObservers: [ObjectIdentifier: PostPasteCorrectionObserver] = [:]
    private var identifier: ObjectIdentifier { ObjectIdentifier(self) }

    public init(store: CorrectionCandidateStore,
                timeoutSeconds: TimeInterval = 60) {
        self.store = store
        self.timeoutSeconds = timeoutSeconds
    }

    /// Attach the observer after a successful paste. Must be called on the
    /// main thread. No-op (returns `false`) if Accessibility is not trusted
    /// or the focused element doesn't expose `kAXValueAttribute`.
    @MainActor
    @discardableResult
    public func start(transcript: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard !didFire, focusedElement == nil else { return false }
        guard let focused = copyFocusedElement(),
              elementSupportsValue(focused) else { return false }

        self.pastedTranscript = transcript
        self.focusedElement = focused
        Self.liveObservers[identifier] = self

        if !registerElementObserver(on: focused) {
            cleanupAfterFire()
            return false
        }
        registerSystemFocusObserver()
        scheduleTimeout()
        return true
    }

    /// Test seam: drive the "final value captured" path directly without a
    /// live AX event. Equivalent to a successful `start()` + later timeout,
    /// but skips the AX registration entirely so it runs anywhere.
    /// Not for production use.
    public func testOnlyFire(transcript: String,
                             finalFieldValue: String,
                             now: Date = Date()) async {
        await MainActor.run { self.pastedTranscript = transcript }
        await fire(finalFieldValue: finalFieldValue, now: now)
    }

    // MARK: - core flow

    @MainActor
    private func handleValueChanged() {
        // Don't fire on every keystroke — wait for focus-change or timeout.
        // The value-changed notification is here purely to keep the run-loop
        // engaged and to confirm the field is still observable; SPEC §2.2.3
        // explicitly waits for focus-change or 60 s to read the final value.
    }

    @MainActor
    private func handleFocusChanged() {
        guard !didFire, let element = focusedElement else { return }
        let final = readValue(element) ?? ""
        Task { [weak self] in
            await self?.fire(finalFieldValue: final, now: Date())
        }
    }

    @MainActor
    private func handleTimeout() {
        guard !didFire, let element = focusedElement else { return }
        let final = readValue(element) ?? ""
        Task { [weak self] in
            await self?.fire(finalFieldValue: final, now: Date())
        }
    }

    private func fire(finalFieldValue: String, now: Date) async {
        // Guard fire-once. The AX callbacks can race the timer; whichever
        // arrives first wins and the rest become no-ops.
        let shouldFire: Bool = await MainActor.run {
            if self.didFire { return false }
            self.didFire = true
            return true
        }
        guard shouldFire else { return }

        let transcript = pastedTranscript ?? ""
        let segments = Self.alignedEditSegments(transcript: transcript,
                                                finalValue: finalFieldValue)
        if !segments.transcriptTail.isEmpty || !segments.fieldTail.isEmpty {
            let candidates = CorrectionDiff.extractCorrections(
                rawTranscript: segments.transcriptTail,
                committedText: segments.fieldTail,
                now: now)
            if !candidates.isEmpty {
                _ = try? await store.record(candidates)
            }
        }

        await MainActor.run { self.cleanupAfterFire() }
    }

    @MainActor
    private func cleanupAfterFire() {
        if let obs = elementObserver, let element = focusedElement {
            AXObserverRemoveNotification(obs, element,
                                         kAXValueChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(obs),
                                  .defaultMode)
        }
        if let sys = systemObserver {
            let systemWide = AXUIElementCreateSystemWide()
            AXObserverRemoveNotification(sys, systemWide,
                                         kAXFocusedUIElementChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(sys),
                                  .defaultMode)
        }
        elementObserver = nil
        systemObserver = nil
        focusedElement = nil
        timer?.cancel()
        timer = nil
        Self.liveObservers[identifier] = nil
    }

    // MARK: - AX registration

    @MainActor
    private func registerElementObserver(on element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return false }
        var observerRef: AXObserver?
        let create = AXObserverCreate(pid, Self.observerCallback, &observerRef)
        guard create == .success, let observer = observerRef else { return false }
        let ctx = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: identifier.hashValue))
        let add = AXObserverAddNotification(observer, element,
                                            kAXValueChangedNotification as CFString,
                                            ctx)
        guard add == .success else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer),
                           .defaultMode)
        self.elementObserver = observer
        return true
    }

    @MainActor
    private func registerSystemFocusObserver() {
        let systemWide = AXUIElementCreateSystemWide()
        var pid: pid_t = 0
        // System-wide AXUIElement returns the focused app's pid; if we can't
        // resolve one, skip system-focus observation. The timeout still fires.
        guard AXUIElementGetPid(systemWide, &pid) == .success else { return }
        var observerRef: AXObserver?
        let create = AXObserverCreate(pid, Self.observerCallback, &observerRef)
        guard create == .success, let observer = observerRef else { return }
        let ctx = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: identifier.hashValue))
        let add = AXObserverAddNotification(observer, systemWide,
                                            kAXFocusedUIElementChangedNotification as CFString,
                                            ctx)
        guard add == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer),
                           .defaultMode)
        self.systemObserver = observer
    }

    @MainActor
    private func scheduleTimeout() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + timeoutSeconds)
        t.setEventHandler { [weak self] in
            self?.handleTimeout()
        }
        t.resume()
        self.timer = t
    }

    // MARK: - AX helpers

    private func copyFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(systemWide,
                                                kAXFocusedUIElementAttribute as CFString,
                                                &value)
        guard err == .success, let cf = value else { return nil }
        // CFGetTypeID equality with AXUIElementGetTypeID() is the documented
        // check; we cast via `AnyObject` so ARC is happy.
        return (cf as! AXUIElement)
    }

    private func elementSupportsValue(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let arr = names as? [String]
        else { return false }
        return arr.contains(kAXValueAttribute as String)
    }

    private func readValue(_ element: AXUIElement) -> String? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element,
                                                kAXValueAttribute as CFString,
                                                &value)
        guard err == .success else { return nil }
        return value as? String
    }

    // MARK: - C callback

    /// Single C-callable trampoline used for both observers. Routes by the
    /// `notification` name into the right `handle…` method on the owning
    /// instance (looked up from `liveObservers` via the context pointer).
    private static let observerCallback: AXObserverCallback = {
        (_: AXObserver, _: AXUIElement, notification: CFString, ctx: UnsafeMutableRawPointer?) in
        guard let ctx else { return }
        let hash = Int(bitPattern: UInt(bitPattern: ctx))
        let owner = liveObservers.first { ObjectIdentifier($0.value).hashValue == hash }?.value
        guard let owner else { return }
        let name = notification as String
        DispatchQueue.main.async {
            if name == (kAXValueChangedNotification as String) {
                owner.handleValueChanged()
            } else if name == (kAXFocusedUIElementChangedNotification as String) {
                owner.handleFocusChanged()
            }
        }
    }

    // MARK: - segment extraction (exposed for tests)

    /// Locate the edited segment by longest-common-prefix (SPEC §2.2.4).
    /// Returns the matched tail of the transcript and the matched tail of
    /// the final field value, both starting where the two strings first
    /// diverge. Diffing the two tails together (instead of transcript vs.
    /// field-tail-only) keeps token alignment honest when the user edited
    /// past the common prefix.
    ///
    /// If the strings are identical, both tails are empty and the diff is
    /// skipped. If the final field value doesn't contain the pasted
    /// transcript at all (zero LCP), we fall back to diffing the whole
    /// transcript vs. the whole field — coarser alignment but still better
    /// than dropping the signal.
    static func alignedEditSegments(transcript: String,
                                    finalValue: String)
        -> (transcriptTail: String, fieldTail: String)
    {
        if transcript.isEmpty || finalValue.isEmpty {
            return (transcript, finalValue)
        }
        let t = Array(transcript)
        let f = Array(finalValue)
        var i = 0
        while i < t.count, i < f.count, t[i] == f[i] {
            i += 1
        }
        if i >= t.count, i >= f.count {
            return ("", "")  // identical
        }
        return (String(t[i...]), String(f[i...]))
    }
}
