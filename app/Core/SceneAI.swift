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

    /// Online Gemini (vision) → on-device Gemma → short Vision templates.
    static func answer(_ question: String, jpeg: Data, frame: ARFrame?, context: SceneContext) async -> String {
        let sensors = context.promptText
        if isOnline {
            do {
                return try await GeminiClient.answer(question, in: jpeg, sensors: sensors)
            } catch {
                // Fall through to Gemma.
            }
        }

        if let gemma = await GemmaClient.answer(question: question, sensors: sensors, jpeg: jpeg) {
            return gemma
        }

        if let frame {
            return OfflineAnswers.answer(question, in: frame)
        }
        return "I can't reach the internet right now, and Gemma isn't loaded yet."
    }
}
