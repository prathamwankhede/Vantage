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
    let band: DistanceBand
}

enum AlertPolicy {
    static let stopDistance: Float = 0.5
    static let nearBand: Float = 0.8
    static let mediumBand: Float = 1.5
    /// Kept for Navigate speech urgency.
    static let announceDistance: Float = 2.0

    /// Pulse interval shortens as obstacles get closer (Night Vision–style).
    static func alert(for distances: SIMD3<Float>, maxDistance: Float, quickResponse: Bool) -> ObstacleAlert? {
        guard let zone = Zone.allCases.min(by: { distances[$0.rawValue] < distances[$1.rawValue] }) else {
            return nil
        }
        let distance = distances[zone.rawValue]
        guard distance < maxDistance else { return nil }

        let closeness = 1 - min(max(distance / maxDistance, 0), 1)
        let slow: TimeInterval = quickResponse ? 0.85 : 1.1
        let fast: TimeInterval = quickResponse ? 0.12 : 0.22
        let interval = slow - Double(closeness) * (slow - fast)

        let band: DistanceBand
        if distance < nearBand { band = .near }
        else if distance < min(mediumBand, maxDistance) { band = .medium }
        else { band = .far }

        return ObstacleAlert(
            zone: zone,
            distance: distance,
            interval: interval,
            intensity: 0.4 + 0.6 * closeness,
            band: band
        )
    }
}
