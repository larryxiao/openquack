import AppKit
import UserNotifications
import Combine
import OpenQuackKit

/// SPEC-031 — tracks live + recently-completed agent-kickoff sessions
/// for the app. Lives on AppDelegate, observed by SwiftUI views.
///
/// Lifecycle per session:
///   track(session) → background Task awaits result → handle(result)
///     → liveSessions[id] removed, completedSessions cap-appended,
///     → UNUserNotificationCenter notification posted.
///
/// Click handler in AppDelegate's UNUserNotificationCenterDelegate
/// looks up the result by sessionId and asks ResponseWindowController
/// to open.
@MainActor
final class AgentSessionManager: ObservableObject {
    @Published private(set) var liveSessions: [UUID: KickoffSession] = [:]
    @Published private(set) var completedResults: [KickoffResult] = []

    private static let completedCap = 20

    /// SPEC-031 — track an already-started session. Spawns a detached
    /// Task that awaits completion off the main actor; result is
    /// delivered back on main via `handle`.
    func track(_ session: KickoffSession) {
        liveSessions[session.id] = session
        Task { [weak self] in
            let result = await session.awaitResult()
            await self?.handle(result)
        }
    }

    /// Look up a completed result by session ID. Used by the
    /// notification click handler.
    func result(for sessionId: UUID) -> KickoffResult? {
        completedResults.first(where: { $0.sessionId == sessionId })
    }

    /// Cancel all in-flight sessions. Called on app quit.
    func cancelAll() {
        for session in liveSessions.values {
            session.cancel()
        }
    }

    // MARK: - private

    private func handle(_ result: KickoffResult) {
        liveSessions[result.sessionId] = nil
        completedResults.append(result)
        if completedResults.count > Self.completedCap {
            completedResults.removeFirst(completedResults.count - Self.completedCap)
        }
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
        guard granted else {
            // Notification permission denied — surface via a future
            // menu-bar dot. v1: silent. The result is still in
            // completedResults; the user can drive a UI surface later.
            return
        }
        let content = UNMutableNotificationContent()
        if result.succeeded {
            content.title = "claude finished"
        } else {
            content.title = "claude failed (exit \(result.exitCode))"
        }
        content.body = AgentKickoffService.notificationBody(
            from: result.succeeded ? result.response : result.stderr
        )
        content.sound = .default
        content.userInfo = ["sessionId": result.sessionId.uuidString]
        content.categoryIdentifier = AgentSessionManager.notificationCategory

        let request = UNNotificationRequest(
            identifier: "openquack.kickoff.\(result.sessionId.uuidString)",
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
