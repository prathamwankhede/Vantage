import Foundation

/// On-course / off-course gate from a live bearing to a world target (or detour beacon).
/// Target updates every frame as the pin/beacon moves relative to the chest — hallways and curves
/// retarget naturally; we don't freeze a compass heading.
struct HeadingLock {
    enum State: Equatable {
        case idle
        case seeking
        case locked
    }

    enum Event: Equatable {
        case none
        case lockedOn
        case lockedOut(turnLeft: Bool)
    }

    /// "On course" means passing within this far of the target sideways, so the cone adapts to distance:
    /// wide for the corner of a bend 2 m ahead, narrow for a door 10 m down the hall.
    private static let lateralTolerance: Float = 0.6
    private static let minLockIn: Float = 8 * .pi / 180
    private static let maxLockIn: Float = 30 * .pi / 180
    private static let lockOutMargin: Float = 15 * .pi / 180
    private static let minDwell: TimeInterval = 0.35

    private(set) var state: State = .idle
    private var pending: State?
    private var pendingSince: Date?
    private var lastHint = Date.distantPast

    mutating func reset() {
        state = .idle
        pending = nil
        pendingSince = nil
    }

    /// `bearing` from `NavGuidance` (+ = right of phone forward), `distance` to the beacon in metres.
    /// Nil clears to idle.
    mutating func update(bearing: Float?, distance: Float?, now: Date = Date()) -> Event {
        guard let bearing else {
            reset()
            return .none
        }
        let error = abs(bearing)
        let lockIn = Self.lockIn(distance: distance)
        let want: State = {
            switch state {
            case .idle, .seeking:
                return error < lockIn ? .locked : .seeking
            case .locked:
                return error > lockIn + Self.lockOutMargin ? .seeking : .locked
            }
        }()

        if want == state {
            pending = nil
            pendingSince = nil
            return .none
        }
        if pending != want {
            pending = want
            pendingSince = now
            return .none
        }
        guard let since = pendingSince, now.timeIntervalSince(since) >= Self.minDwell else {
            return .none
        }
        let previous = state
        state = want
        pending = nil
        pendingSince = nil

        if previous != .locked, state == .locked {
            return .lockedOn
        }
        if previous == .locked, state == .seeking {
            return .lockedOut(turnLeft: bearing < 0)
        }
        return .none
    }

    static func lockIn(distance: Float?) -> Float {
        guard let distance, distance > 0.1 else { return maxLockIn }
        return min(maxLockIn, max(minLockIn, atan(lateralTolerance / distance)))
    }

    /// Spoken turn hint while seeking; rate-limited.
    mutating func seekHint(bearing: Float, now: Date = Date()) -> String? {
        guard state == .seeking, now.timeIntervalSince(lastHint) >= 4 else { return nil }
        lastHint = now
        let degrees = abs(bearing) * 180 / .pi
        if degrees < 20 { return nil }
        return bearing < 0 ? "Turn left." : "Turn right."
    }
}
