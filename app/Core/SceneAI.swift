import ARKit
import Foundation
import Network

enum SceneAI {
    private static let monitor = NWPathMonitor()
    private static let queue = DispatchQueue(label: "vantage.reachability")
    private static let lock = NSLock()
    private nonisolated(unsafe) static var pathSatisfied = true
    private nonisolated(unsafe) static var started = false

    static func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            lock.lock()
            pathSatisfied = path.status == .satisfied
            lock.unlock()
        }
        monitor.start(queue: queue)
    }

    static var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pathSatisfied
    }

    static func answer(_ question: String, jpeg: Data, frame: ARFrame?) async -> String {
        if isOnline {
            do {
                return try await GeminiClient.answer(question, in: jpeg)
            } catch {
                // Fall through to on-device templates.
            }
        }
        if let frame {
            return OfflineAnswers.answer(question, in: frame)
        }
        return "I can't reach the internet right now, but I'm still watching for obstacles."
    }
}
