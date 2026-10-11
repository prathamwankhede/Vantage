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

    private static let lockInRadians: Float = 18 * .pi / 180
    private static let lockOutRadians: Float = 35 * .pi / 180
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

    /// `bearing` from `NavGuidance` (+ = right of phone forward). Nil clears to idle.
    mutating func update(bearing: Float?, now: Date = Date()) -> Event {
        guard let bearing else {
            reset()
            return .none
        }
        let error = abs(bearing)
        let want: State = {
            switch state {
            case .idle, .seeking:
                return error < Self.lockInRadians ? .locked : .seeking
            case .locked:
                return error > Self.lockOutRadians ? .seeking : .locked
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

    /// Spoken turn hint while seeking; rate-limited.
    mutating func seekHint(bearing: Float, now: Date = Date()) -> String? {
        guard state == .seeking, now.timeIntervalSince(lastHint) >= 4 else { return nil }
        lastHint = now
        let degrees = abs(bearing) * 180 / .pi
        if degrees < 20 { return nil }
        return bearing < 0 ? "Turn left." : "Turn right."
    }
}
