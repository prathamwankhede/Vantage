import Foundation
import simd

/// Navigate without maps. Gemini (or a sign read on-device) picks the next landmark in the photo,
/// LiDAR pins it as a fixed 3D point, and between Gemini calls the beacon, a distance countdown and
/// distance-based arrival follow it. Freeroam's depth safety keeps running underneath.
@MainActor
final class NavigateSession: ObservableObject {
    enum StepReason {
        /// "Vantage, next" — always ask, and interrupt whatever is being said.
        case user
        /// Reached a waypoint or lost the target — ask now, without interrupting.
        case event
        /// No target yet and walking — ask only if Vantage is quiet.
        case search
    }

    @Published private(set) var lastStep = ""
    @Published private(set) var arrived = false
    @Published private(set) var busy = false
    @Published private(set) var target: NavTarget?
    /// Live bearing (radians, + = right) and horizontal distance (m) to the target. Updated every
    /// frame, so not @Published — the engine reads it in its own frame loop.
    private(set) var guidance: (bearing: Float, distance: Float)?
    /// Where the beacon points: the target itself, or the next clear point on a route around an
    /// obstacle the room mesh sees in the straight line.
    private(set) var beacon: (bearing: Float, distance: Float)?

    private weak var engine: FreeroamEngine?
    private var goal = ""
    private var loopTask: Task<Void, Never>?
    private var camera: simd_float4x4?
    private var lastRequest = Date.distantPast

    // Progress on the current target.
    private var closest: Float = .infinity
    private var lastProgress = Date()
    private var nextCallout = 0
    private let calloutFeet = [20, 15, 10, 6, 3]
    private let arrivalDistance: Float = 1.0
    private let passedMargin: Float = 1.5
    private let stallTimeout: TimeInterval = 30
    private let searchInterval: TimeInterval = 10

    // Routing around obstacles (room mesh). Planned off the main thread at most twice a second.
    private var detour: SIMD3<Float>?
    private var planning = false
    private var lastPlan = Date.distantPast
    private var targetGeneration = 0
    private var detourAnnounced = false

    func start(goal: String, engine: FreeroamEngine) {
        self.goal = goal
        self.engine = engine
        arrived = false
        lastStep = ""
        clearTarget()
        engine.signSpotter.setGoal(goal)
        loopTask?.cancel()
        loopTask = Task { @MainActor [weak self] in
            // First step shortly after the greeting.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await self?.requestStep(.user)
            // After that, steps come from events; this only covers "no target yet, still walking".
            while let self, !Task.isCancelled, !self.arrived {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if self.target == nil, Date().timeIntervalSince(self.lastRequest) >= self.searchInterval {
                    await self.requestStep(.search)
                }
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        clearTarget()
        engine = nil
    }

    // MARK: - Per-frame tracking

    /// Called by the engine for every delivered frame while navigating.
    func update(camera: simd_float4x4) {
        self.camera = camera
        guard let target, !arrived else {
            guidance = nil
            beacon = nil
            return
        }
        guard let current = NavGuidance.bearingAndDistance(to: target.world, from: camera) else { return }
        guidance = current
        planDetourIfDue(from: camera, to: target)
        updateBeacon(camera: camera, direct: current)

        if current.distance < closest - 0.25 {
            closest = current.distance
            lastProgress = Date()
        }
        if current.distance < arrivalDistance {
            reach(target)
            return
        }
        let walkedPast = current.distance > closest + passedMargin
        let stalled = (engine?.isMoving ?? false) && Date().timeIntervalSince(lastProgress) > stallTimeout
        if walkedPast || stalled {
            lose()
            return
        }
        calloutIfDue(target, current)
    }

    /// Re-plans the route around obstacles in the background; results for an old target are dropped.
    private func planDetourIfDue(from camera: simd_float4x4, to target: NavTarget) {
        guard let engine, !planning, Date().timeIntervalSince(lastPlan) >= 0.5 else { return }
        planning = true
        lastPlan = Date()
        let map = engine.roomMap
        let position = SIMD3(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
        let goal = target.world
        let generation = targetGeneration
        Task.detached(priority: .utility) { [weak self] in
            let waypoint = map.steer(from: position, to: goal)
            await self?.finishPlan(waypoint, generation: generation)
        }
    }

    private func finishPlan(_ waypoint: SIMD3<Float>?, generation: Int) {
        planning = false
        guard generation == targetGeneration else { return }
        // Ease toward the new turn point so the beacon glides round a bend instead of jumping cell to
        // cell; a genuinely different route (> 1.5 m away) switches at once.
        if let waypoint, let old = detour, simd_distance(old, waypoint) < 1.5 {
            detour = old + (waypoint - old) * 0.5
        } else {
            detour = waypoint
        }
    }

    private func updateBeacon(camera: simd_float4x4, direct: (bearing: Float, distance: Float)) {
        guard let detour, let around = NavGuidance.bearingAndDistance(to: detour, from: camera) else {
            beacon = direct
            return
        }
        beacon = around
        // Say it once per target, when the way around differs noticeably from straight at it.
        if !detourAnnounced, abs(around.bearing - direct.bearing) > .pi / 7, let engine, !engine.isSpeaking {
            detourAnnounced = true
            engine.say("Something's in the way. Head \(NavGuidance.directionWords(around.bearing)).", allowNetwork: false)
        }
    }

    /// Short distance updates at 20, 15, 10, 6 and 3 ft — only while walking and when Vantage is quiet.
    private func calloutIfDue(_ target: NavTarget, _ current: (bearing: Float, distance: Float)) {
        guard let engine, nextCallout < calloutFeet.count else { return }
        let feet = NavGuidance.feet(current.distance)
        guard feet <= calloutFeet[nextCallout] else { return }
        // Skip thresholds already behind us (e.g. pinned at 8 ft: the next callout is 6).
        while nextCallout + 1 < calloutFeet.count, feet <= calloutFeet[nextCallout + 1] { nextCallout += 1 }
        guard engine.isMoving, !engine.isSpeaking else { return }
        nextCallout += 1
        let heading = beacon?.bearing ?? current.bearing
        engine.say(
            "\(NavGuidance.capitalized(target.label)), \(feet) feet, \(NavGuidance.directionWords(heading)).",
            allowNetwork: false
        )
    }

    private func reach(_ target: NavTarget) {
        guard let engine else { return }
        clearTarget()
        if target.isGoal {
            arrived = true
            engine.updateNavigateStep("Arrived at \(goal)")
            engine.say("You've reached \(goal).", interrupt: true, allowNetwork: false)
        } else {
            engine.say("Reached \(target.label).", allowNetwork: false)
            Task { await requestStep(.event) }
        }
    }

    private func lose() {
        clearTarget()
        Task { await requestStep(.event) }
    }

    private func setTarget(_ newTarget: NavTarget) {
        targetGeneration += 1
        detour = nil
        detourAnnounced = false
        target = newTarget
        closest = .infinity
        lastProgress = Date()
        nextCallout = 0
        guidance = camera.flatMap { NavGuidance.bearingAndDistance(to: newTarget.world, from: $0) }
        beacon = guidance
        if let distance = guidance?.distance { closest = distance }
    }

    private func clearTarget() {
        targetGeneration += 1
        detour = nil
        target = nil
        guidance = nil
        beacon = nil
        closest = .infinity
        nextCallout = 0
    }

    /// " Door, 24 feet, slightly left." — appended to a new target's announcement.
    private func whereIs(_ target: NavTarget) -> String {
        guard let guidance else { return "" }
        let distance = target.measured ? "\(NavGuidance.feet(guidance.distance)) feet" : "a few steps or more"
        return " \(NavGuidance.capitalized(target.label)), \(distance), \(NavGuidance.directionWords(guidance.bearing))."
    }

    // MARK: - Signs

    /// A sign matching the destination was read on-device. Signs win over Gemini's pick.
    func pinSign(_ match: SignSpotter.Match) {
        guard let engine, !arrived else { return }
        if target?.source == .sign { return }
        let sign = NavTarget(label: "the \(match.text) sign", world: match.world, source: .sign, isGoal: true, measured: match.measured)
        setTarget(sign)
        var line = "Sign for \(match.text)."
        if let guidance {
            let distance = match.measured ? "\(NavGuidance.feet(guidance.distance)) feet" : "a few steps or more"
            line = "Sign for \(match.text), \(NavGuidance.directionWords(guidance.bearing)), \(distance)."
        }
        engine.updateNavigateStep(line)
        engine.say(line, interrupt: true, allowNetwork: false)
    }

    // MARK: - Gemini steps

    func requestStep(force: Bool) async {
        await requestStep(force ? .user : .search)
    }

    func requestStep(_ reason: StepReason) async {
        guard let engine, !arrived, !busy else { return }
        if reason == .search {
            guard engine.isMoving, !engine.isSpeaking else { return }
        }
        guard let snapshot = engine.navigateSnapshot() else {
            if reason == .user { engine.say("I need a clear camera view for the next step.") }
            return
        }
        busy = true
        lastRequest = Date()
        defer { busy = false }

        do {
            let step = try await GeminiClient.navigateStep(
                goal: goal, lastStep: lastStep, in: snapshot.jpeg, sensors: engine.sceneContext().promptText
            )
            // The session may have ended or reached the goal while Gemini was thinking.
            guard self.engine != nil, !arrived else { return }
            lastStep = step.spoken
            engine.updateNavigateStep(step.spoken)

            var line = step.spoken
            // Pin the landmark where Gemini boxed it, unless a sign is already leading the way.
            if !step.unsure, let center = step.uprightCenter, let depth = snapshot.depth, target?.source != .sign {
                var (point, measured) = depth.worldPoint(uprightNormalized: center)
                let label = step.landmark.isEmpty ? "the landmark" : step.landmark
                // A door the room mesh actually found beats a point picked in a photo.
                let lowered = label.lowercased()
                if ["door", "exit", "entrance", "doorway"].contains(where: lowered.contains),
                   let door = engine.roomMap.door(near: point, within: 1.2) {
                    point = door
                    measured = true
                }
                let pinned = NavTarget(label: label, world: point, source: .gemini, isGoal: step.isGoal ?? false, measured: measured)
                setTarget(pinned)
                line += whereIs(pinned)
            }
            engine.say(line, interrupt: reason == .user)

            if step.arrived, target == nil {
                arrived = true
                engine.say("I think you've arrived. Nice work.", interrupt: false)
            }
        } catch GeminiClient.Failure.offline {
            if reason == .user {
                engine.say("I'm offline, so I can't plan landmarks. Signs and depth are still watching.")
            }
        } catch GeminiClient.Failure.timedOut {
            if reason == .user {
                engine.say("Gemini is slow right now. Say next to try again. Signs and depth are still watching.")
            }
        } catch GeminiClient.Failure.quota {
            if reason == .user {
                engine.say("Navigation is pausing for a moment — quota. Depth is still on.")
            }
        } catch {
            if reason == .user {
                engine.say("I couldn't get a step just now. Try saying next again.")
            }
        }
    }
}
