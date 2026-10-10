import CoreHaptics
import Foundation

/// White Cane–style haptic patterns (tap / beep / toot) with Night Vision–style faster pulses when closer.
final class HapticPulser {
    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var continuousOn = false

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in
            try? self?.engine?.start()
        }
        try? engine?.start()
    }

    func play(_ pattern: HapticPattern, intensity: Float = 1) {
        guard pattern != .mute else { return }
        let i = max(0.15, min(1, intensity))
        switch pattern {
        case .tapSharp:
            play(events: [transient(intensity: i, sharpness: 1.0, at: 0)])
        case .tap:
            play(events: [transient(intensity: i * 0.75, sharpness: 0.35, at: 0)])
        case .beep:
            play(events: [continuous(intensity: i * 0.7, sharpness: 0.55, at: 0, duration: 0.08)])
        case .toot:
            play(events: [continuous(intensity: i * 0.85, sharpness: 0.4, at: 0, duration: 0.16)])
        case .tootSharp:
            play(events: [continuous(intensity: i, sharpness: 0.95, at: 0, duration: 0.12)])
        case .mute:
            break
        }
    }

    /// Continuous vibration while an obstacle is very close (White Cane “Continuous Vibration at Close Range”).
    func setContinuousClose(_ on: Bool, intensity: Float = 0.9) {
        if on {
            startContinuous(intensity: intensity)
        } else {
            stopContinuous()
        }
    }

    func heartbeat() {
        play(events: [
            transient(intensity: 0.4, sharpness: 0.12, at: 0),
            transient(intensity: 0.28, sharpness: 0.12, at: 0.16)
        ])
    }

    func urgentStop() {
        play(events: (0..<3).map { transient(intensity: 1, sharpness: 1, at: Double($0) * 0.12) })
    }

    // Legacy helpers
    func pulse(intensity: Float) {
        play(.tap, intensity: intensity)
    }

    private func startContinuous(intensity: Float) {
        guard let engine else { return }
        if continuousOn {
            try? continuousPlayer?.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0)
            ], atTime: 0)
            return
        }
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: [
                continuous(intensity: intensity, sharpness: 0.5, at: 0, duration: 30)
            ], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            continuousPlayer = player
            continuousOn = true
        } catch {
            try? engine.start()
        }
    }

    private func stopContinuous() {
        try? continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
        continuousPlayer = nil
        continuousOn = false
    }

    private func transient(intensity: Float, sharpness: Float, at time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    private func continuous(intensity: Float, sharpness: Float, at time: TimeInterval, duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time,
            duration: duration
        )
    }

    private func play(events: [CHHapticEvent]) {
        guard let engine else { return }
        do {
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            try? engine.start()
        }
    }
}
