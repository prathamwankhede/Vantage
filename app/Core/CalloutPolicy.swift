import Foundation

struct Callout: Equatable {
    var text: String
    var playLandmarkEarcon: Bool
}

/// Sparse Freeroam spoken callouts: approach-only, cooldowns, specials boost.
struct CalloutPolicy {
    private static let approachDelta: Float = 0.25
    private static let maxDistance: Float = 2.5
    private static let cooldownGeneral: TimeInterval = 5
    private static let cooldownSpecial: TimeInterval = 3
    private static let stableTicksNeeded = 2

    private var lastDistance: [String: Float] = [:]
    private var stableTicks: [String: Int] = [:]
    private var lastSpokenAt: [String: Date] = [:]

    mutating func reset() {
        lastDistance = [:]
        stableTicks = [:]
        lastSpokenAt = [:]
    }

    mutating func evaluate(
        objects: [SceneObject],
        isMoving: Bool,
        quietMode: Bool,
        now: Date = Date()
    ) -> Callout? {
        guard isMoving, !quietMode else { return nil }

        var best: (object: SceneObject, score: Float)?
        for object in objects {
            guard object.distance > 0.2, object.distance <= Self.maxDistance else { continue }
            let previous = lastDistance[object.id]
            lastDistance[object.id] = object.distance
            let approaching: Bool
            if let previous {
                approaching = object.distance < previous - Self.approachDelta
                stableTicks[object.id] = approaching ? (stableTicks[object.id] ?? 0) + 1 : 0
            } else {
                approaching = true
                stableTicks[object.id] = 1
            }
            guard approaching, (stableTicks[object.id] ?? 0) >= Self.stableTicksNeeded else { continue }

            let cooldown = object.isSpecial ? Self.cooldownSpecial : Self.cooldownGeneral
            if let spoken = lastSpokenAt[object.id], now.timeIntervalSince(spoken) < cooldown { continue }

            let score = (object.isSpecial ? 0 : 1) * 10 + object.distance
            if best == nil || score < best!.score {
                best = (object, score)
            }
        }

        // Drop stale ids.
        let live = Set(objects.map(\.id))
        lastDistance = lastDistance.filter { live.contains($0.key) }
        stableTicks = stableTicks.filter { live.contains($0.key) }

        guard let pick = best?.object else { return nil }
        lastSpokenAt[pick.id] = now
        let feet = max(1, Int((pick.distance * 3.28084).rounded()))
        let place: String
        switch pick.zone {
        case .left: place = "on your left"
        case .right: place = "on your right"
        case .center: place = "ahead"
        }
        return Callout(
            text: "\(pick.name) \(place), about \(feet) feet.",
            playLandmarkEarcon: pick.isSpecial
        )
    }

    static func aroundMeLine(objects: [SceneObject]) -> String {
        let top = Array(objects.prefix(3))
        guard !top.isEmpty else { return "Nothing close." }
        let parts = top.map { object -> String in
            let feet = max(1, Int((object.distance * 3.28084).rounded()))
            let side: String
            switch object.zone {
            case .left: side = "left"
            case .right: side = "right"
            case .center: side = "ahead"
            }
            return "\(object.name) \(side), \(feet) feet"
        }
        return parts.joined(separator: ". ") + "."
    }
}
