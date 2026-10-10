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
    static func answer(_ question: String, jpeg: Data, frame: ARFrame?) async -> String {
        if isOnline {
            do {
                return try await GeminiClient.answer(question, in: jpeg)
            } catch {
                // Fall through to Gemma.
            }
        }

        let summary = frame.map { SceneLabels.summary(for: $0) } ?? "No camera labels."
        if let gemma = await GemmaClient.answer(question: question, sceneSummary: summary, jpeg: jpeg) {
            return gemma
        }

        if let frame {
            return OfflineAnswers.answer(question, in: frame)
        }
        return "I can't reach the internet right now, and Gemma isn't loaded yet."
    }
}
