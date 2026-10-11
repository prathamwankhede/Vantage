import UIKit

/// Turn-to-target feel borrowed from Apple's Compass and Measure > Level: a selection tick for every
/// 10° you rotate while off course, then one firm click when you line up. UIKit feedback generators,
/// so they stay crisp and separate from the Core Haptics obstacle patterns.
@MainActor
final class HeadingHaptics {
    private static let detentDegrees: Float = 10
    /// Stay this far past a detent edge before ticking again, so jitter on the line doesn't buzz.
    private static let hysteresisDegrees: Float = 2

    private let tick = UISelectionFeedbackGenerator()
    private let click = UIImpactFeedbackGenerator(style: .rigid)
    private let warning = UINotificationFeedbackGenerator()
    private var detent: Int?
    private var lastTick = Date.distantPast

    func reset() {
        detent = nil
    }

    /// Compass-style ticks while seeking. `bearing` in radians, + = right.
    func track(bearing: Float, seeking: Bool, now: Date = Date()) {
        let degrees = bearing * 180 / .pi
        guard seeking else {
            detent = nil
            return
        }
        let current = Int((degrees / Self.detentDegrees).rounded(.down))
        guard let previous = detent else {
            detent = current
            tick.prepare()
            return
        }
        guard current != previous else { return }
        // Distance into the new detent from the edge we just crossed.
        let edge = Float(max(current, previous)) * Self.detentDegrees
        guard abs(degrees - edge) >= Self.hysteresisDegrees else { return }
        detent = current
        guard now.timeIntervalSince(lastTick) >= 0.04 else { return }
        lastTick = now
        tick.selectionChanged()
        tick.prepare()
    }

    /// Level-style click: you're facing the target.
    func lockedOn() {
        detent = nil
        click.impactOccurred(intensity: 1)
        click.prepare()
    }

    /// Drifted off course.
    func lockedOut() {
        warning.notificationOccurred(.warning)
        tick.prepare()
    }
}
