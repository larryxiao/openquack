import Foundation
import Network

public enum NetworkReachability {
    /// Suspends until `NWPathMonitor` reports a satisfied path or the timeout
    /// elapses. Returns immediately if the path is already satisfied on the
    /// monitor's first callback. Event-driven — no polling.
    public static func waitForSatisfied(timeoutSeconds: TimeInterval) async {
        let monitor = NWPathMonitor()
        let stream = AsyncStream<Void> { continuation in
            monitor.pathUpdateHandler = { path in
                if path.status == .satisfied {
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in
                monitor.cancel()
            }
            monitor.start(queue: .global())
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                continuation.finish()
            }
        }
        for await _ in stream {}
    }
}
