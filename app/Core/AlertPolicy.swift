import Foundation

enum Zone: Int, CaseIterable {
    case left, center, right

    var label: String {
        switch self {
        case .left: return "LEFT"
        case .center: return "CENTER"
        case .right: return "RIGHT"
        }
    }

    /// Screen / world bearing in radians for spatial audio (−π/2 left … +π/2 right).
    var bearingRadians: Float {
        switch self {
        case .left: return -.pi / 3
        case .center: return 0
        case .right: return .pi / 3
        }
    }

    var pan: Float {
        switch self {
        case .left: return -1
        case .center: return 0
        case .right: return 1
        }
    }
}

struct ObstacleAlert: Equatable {
    let zone: Zone
    let distance: Float
    let interval: TimeInterval
    let intensity: Float
}

enum AlertPolicy {
    static let silentBeyond: Float = 3.0
    static let farDistance: Float = 2.5
    static let nearDistance: Float = 0.4
    static let stopDistance: Float = 0.5
    static let announceDistance: Float = 2.0
    static let slowInterval: TimeInterval = 1.0
    static let fastInterval: TimeInterval = 0.18

    /// Only the nearest zone alerts. Nil when everything is beyond the silent range.
    static func alert(for distances: SIMD3<Float>) -> ObstacleAlert? {
        guard let zone = Zone.allCases.min(by: { distances[$0.rawValue] < distances[$1.rawValue] }) else {
            return nil
        }
        let distance = distances[zone.rawValue]
        guard distance < silentBeyond else { return nil }

        let closeness = 1 - min(max((distance - nearDistance) / (farDistance - nearDistance), 0), 1)
        let interval = slowInterval - Double(closeness) * (slowInterval - fastInterval)
        return ObstacleAlert(
            zone: zone,
            distance: distance,
            interval: interval,
            intensity: 0.35 + 0.55 * closeness
        )
    }
}
