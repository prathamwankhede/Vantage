import Foundation

/// Gemini landmark steps — no MapKit. Depth safety stays in FreeroamEngine underneath.
@MainActor
final class NavigateSession: ObservableObject {
    @Published private(set) var lastStep = ""
    @Published private(set) var arrived = false
    @Published private(set) var busy = false

    private weak var engine: FreeroamEngine?
    private var goal = ""
    private var loopTask: Task<Void, Never>?
    private let autoInterval: TimeInterval = 14

    func start(goal: String, engine: FreeroamEngine) {
        self.goal = goal
        self.engine = engine
        arrived = false
        lastStep = ""
        loopTask?.cancel()
        loopTask = Task { @MainActor [weak self] in
            // First step shortly after greeting.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await self?.requestStep(force: true)
            while let self, !Task.isCancelled, !self.arrived {
                try? await Task.sleep(nanoseconds: UInt64(self.autoInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self.requestStep(force: false)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        engine = nil
    }

    func requestStep(force: Bool) async {
        guard let engine, !arrived else { return }
        guard force || !busy else { return }
        // Automatic steps wait until the wearer is walking and Vantage isn't mid-sentence.
        guard force || (engine.isMoving && !engine.isSpeaking) else { return }
        guard let jpeg = engine.snapshotJPEG() else {
            if force { engine.say("I need a clear camera view for the next step.") }
            return
        }
        busy = true
        defer { busy = false }

        do {
            let step = try await GeminiClient.navigateStep(goal: goal, lastStep: lastStep, in: jpeg)
            lastStep = step.spoken
            engine.updateNavigateStep(step.spoken)
            engine.setNavigateBearing(step.zoneHint)
            engine.say(step.spoken, interrupt: force)
            if step.arrived {
                arrived = true
                engine.say("I think you've arrived. Nice work.", interrupt: false)
            }
        } catch GeminiClient.Failure.offline {
            if force {
                engine.say("I'm offline, so I can't plan landmarks. Freeroam depth is still watching.")
            }
        } catch GeminiClient.Failure.quota {
            if force {
                engine.say("Navigation is pausing for a moment — quota. Depth is still on.")
            }
        } catch {
            if force {
                engine.say("I couldn't get a step just now. Try saying next again.")
            }
        }
    }
}
