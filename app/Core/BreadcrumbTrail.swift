import Foundation
import simd

/// Clew-style pose crumbs for "return to start" — no Gemini, ARKit only.
struct BreadcrumbTrail {
    struct Crumb {
        var position: SIMD2<Float>
        var yaw: Float
    }

    private static let minStep: Float = 0.4
    private static let maxCrumbs = 200
    private static let turnRadians: Float = 35 * .pi / 180
    private static let keyDistance: Float = 2.5
    private static let arriveDistance: Float = 0.6

    private(set) var crumbs: [Crumb] = []
    private var reverseKeys: [Crumb] = []
    private var keyIndex = 0
    private(set) var returning = false

    mutating func reset() {
        crumbs = []
        reverseKeys = []
        keyIndex = 0
        returning = false
    }

    mutating func record(position: SIMD2<Float>, yaw: Float) {
        guard !returning else { return }
        if let last = crumbs.last {
            guard simd_distance(position, last.position) >= Self.minStep else { return }
        }
        crumbs.append(Crumb(position: position, yaw: yaw))
        if crumbs.count > Self.maxCrumbs { crumbs.removeFirst(crumbs.count - Self.maxCrumbs) }
    }

    mutating func beginReturn() -> String? {
        guard crumbs.count >= 2 else { return nil }
        reverseKeys = Self.keypoints(from: crumbs).reversed()
        keyIndex = 0
        returning = reverseKeys.count >= 1
        guard returning else { return nil }
        return instruction(to: reverseKeys[0], from: crumbs.last!)
    }

    mutating func update(position: SIMD2<Float>, yaw: Float) -> String? {
        guard returning, keyIndex < reverseKeys.count else {
            if returning {
                returning = false
                return "Back near where you started."
            }
            return nil
        }
        let key = reverseKeys[keyIndex]
        if simd_distance(position, key.position) <= Self.arriveDistance {
            keyIndex += 1
            if keyIndex >= reverseKeys.count {
                returning = false
                return "Back near where you started."
            }
            return instruction(to: reverseKeys[keyIndex], from: Crumb(position: position, yaw: yaw))
        }
        return nil
    }

    private static func keypoints(from crumbs: [Crumb]) -> [Crumb] {
        guard var previous = crumbs.first else { return [] }
        var keys = [previous]
        var sinceKey: Float = 0
        for crumb in crumbs.dropFirst() {
            let step = simd_distance(crumb.position, previous.position)
            sinceKey += step
            var delta = crumb.yaw - previous.yaw
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            if abs(delta) >= turnRadians || sinceKey >= keyDistance {
                keys.append(crumb)
                sinceKey = 0
            }
            previous = crumb
        }
        if keys.last?.position != crumbs.last?.position, let last = crumbs.last {
            keys.append(last)
        }
        return keys
    }

    private func instruction(to key: Crumb, from here: Crumb) -> String {
        let delta = key.position - here.position
        let distance = simd_length(delta)
        let feet = max(1, Int((distance * 3.28084).rounded()))
        let targetYaw = atan2(delta.x, delta.y)
        var turn = targetYaw - here.yaw
        while turn > .pi { turn -= 2 * .pi }
        while turn < -.pi { turn += 2 * .pi }
        if abs(turn) > 35 * .pi / 180 {
            return turn < 0 ? "Turn left, then about \(feet) feet." : "Turn right, then about \(feet) feet."
        }
        return "Walk about \(feet) feet."
    }
}
