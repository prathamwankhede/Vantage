import Foundation
import simd

/// Where Navigate is leading the wearer right now: a fixed point in ARKit world space, so it stays
/// put as they walk and turn.
struct NavTarget {
    enum Source { case gemini, sign }

    let label: String
    let world: SIMD3<Float>
    let source: Source
    /// The destination itself, not a waypoint on the way.
    let isGoal: Bool
    /// False when LiDAR had no depth at the spot and the distance is a guess.
    let measured: Bool
}

/// Bearing, distance and wording from the wearer to a world point.
enum NavGuidance {
    /// Bearing in radians relative to where the phone faces (+ = right) and horizontal distance in
    /// metres. Nil when the phone points almost straight up or down.
    static func bearingAndDistance(to target: SIMD3<Float>, from camera: simd_float4x4) -> (bearing: Float, distance: Float)? {
        let position = SIMD3(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
        // The camera looks down its -Z axis whatever the phone's orientation; flatten onto the floor.
        let back = camera.columns.2
        var forward = SIMD3<Float>(-back.x, 0, -back.z)
        guard simd_length(forward) > 0.1 else { return nil }
        forward = simd_normalize(forward)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let toTarget = SIMD3(target.x - position.x, 0, target.z - position.z)
        return (atan2(simd_dot(toTarget, right), simd_dot(toTarget, forward)), simd_length(toTarget))
    }

    static func directionWords(_ bearing: Float) -> String {
        let degrees = bearing * 180 / .pi
        let side = degrees < 0 ? "left" : "right"
        switch abs(degrees) {
        case ..<15: return "ahead"
        case ..<45: return "slightly \(side)"
        case ..<110: return "to your \(side)"
        default: return "behind you"
        }
    }

    static func feet(_ metres: Float) -> Int {
        Int((metres * 3.28084).rounded())
    }

    /// "Wooden door" → "Wooden door"; "door" → "Door" — for the start of a spoken sentence.
    static func capitalized(_ label: String) -> String {
        label.prefix(1).uppercased() + label.dropFirst()
    }
}
