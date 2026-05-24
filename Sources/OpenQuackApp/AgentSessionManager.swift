import AppKit
import UserNotifications
import Combine
import OpenQuackKit

/// SPEC-031 v3 — tracks live + recently-completed agent-kickoff
/// sessions, drives StateFileWatchers, posts notifications.
///
/// Lifecycle per session:
///   track(session) → install StateFileWatcher on
///     ~/.claude/jobs/<short>/state.json
///   → on each state change, update liveStates
///   → on terminal state (done/blocked/idle): archive as
///     KickoffResult, post UNNotification, stop the watcher.
///
/// Click handler in AppDelegate's UNUserNotificationCenterDelegate
/// looks up the result by shortID and asks ResponseWindowController
/// to open.
@MainActor
final class AgentSessionManager: ObservableObject {
    @Published private(set) var liveSessions: [String: KickoffSession] = [:]
    @Published private(set) var liveStates:   [String: KickoffState]   = [:]
    @Published private(set) var completedResults: [KickoffResult] = []

    private static let completedCap = 20
    private var watchers: [String: StateFileWatcher] = [:]

    /// Begin tracking a dispatched session. Installs a state-file
    /// watcher that drives notifications on terminal-state transitions.
    func track(_ session: KickoffSession) {
        liveSessions[session.shortID] = session
        let watcher = StateFileWatcher(url: session.stateFileURL) { [weak self] state in
            // Watcher callback fires off-main; hop to main.
            Task { @MainActor in
                self?.handle(state: state, session: session)
            }
        }
        watchers[session.shortID] = watcher
        watcher.start()
    }

    /// Look up a completed result by short ID. Used by the
    /// notification click handler.
    func result(for shortID: String) -> KickoffResult? {
        completedResults.first(where: { $0.shortID == shortID })
    }

    /// Stop watching everything. Sessions themselves are owned by the
    /// daemon and keep running even after we forget about them —
    /// that's the whole point of `--bg`.
    func stopTrackingAll() {
        for watcher in watchers.values {
            watcher.stop()
        }
        watchers.removeAll()
    }

    // MARK: - private

    private func handle(state: KickoffState, session: KickoffSession) {
        liveStates[session.shortID] = state
        guard state.isTerminal else { return }

        // Archive + notify.
        let result = KickoffResult(from: state, session: session)
        completedResults.append(result)
        if completedResults.count > Self.completedCap {
            completedResults.removeFirst(completedResults.count - Self.completedCap)
        }
        watchers[session.shortID]?.stop()
        watchers[session.shortID] = nil
        liveSessions[session.shortID] = nil
        postNotification(for: result)
    }

    private func postNotification(for result: KickoffResult) {
        // Request authorization the first time we'd post. Asks
        // in-context per the spec (not at app launch).
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.deliver(result: result, granted: granted)
            }
        }
    }

    private func deliver(result: KickoffResult, granted: Bool) {
        guard granted else { return }
        let content = UNMutableNotificationContent()
        switch result.state {
        case .done, .idle:
            content.title = "claude finished"
        case .blocked:
            content.title = "claude needs input"
        default:
            content.title = "claude session updated"
        }
        let bodySource: String =
            result.detail
            ?? result.output
            ?? result.needs
            ?? ""
        content.body = AgentKickoffService.notificationBody(from: bodySource)
        content.sound = .default
        content.userInfo = ["shortID": result.shortID]
        content.categoryIdentifier = AgentSessionManager.notificationCategory

        let request = UNNotificationRequest(
            identifier: "openquack.kickoff.\(result.shortID)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static let notificationCategory = "openquack.kickoff.result"

    /// Register the notification category + actions. Called once from
    /// AppDelegate at launch.
    static func registerNotificationCategory() {
        let openAction = UNNotificationAction(
            identifier: "openquack.kickoff.open",
            title: "Open response",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: notificationCategory,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
