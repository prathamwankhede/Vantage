import CoreHaptics
import Foundation

/// White Cane–style haptic patterns (tap / beep / toot) with Night Vision–style faster pulses when closer.
final class HapticPulser {
    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var continuousOn = false
    private var continuousIntensity: Float = 0
    /// Set when the system stops or resets the engine; the next cue restarts it.
    private var needsStart = true

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        // Haptics only — don't tie the engine to the audio session the mic and TTS keep reconfiguring.
        engine?.playsHapticsOnly = true
        // The system stops the engine on audio interruptions and backgrounding, and resets it if
        // the haptic server dies. Either way, players made before are dead.
        engine?.stoppedHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.engineDidStop() }
        }
        engine?.resetHandler = { [weak self] in
            DispatchQueue.main.async { self?.engineDidStop() }
        }
        ensureStarted()
    }

    private func engineDidStop() {
        needsStart = true
        let wasContinuous = continuousOn
        continuousPlayer = nil
        continuousOn = false
        if wasContinuous { startContinuous(intensity: continuousIntensity) }
    }

    @discardableResult
    private func ensureStarted() -> Bool {
        guard let engine else { return false }
        guard needsStart else { return true }
        do {
            try engine.start()
            needsStart = false
            return true
        } catch {
            print("Haptics: engine start failed: \(error)")
            return false
        }
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
        continuousIntensity = intensity
        if continuousOn {
            try? continuousPlayer?.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0)
            ], atTime: CHHapticTimeImmediate)
            return
        }
        guard let engine, ensureStarted() else { return }
        do {
            // Full-strength base event scaled by the intensity control, looped so it lasts as long as
            // the obstacle is close (a single 30 s event used to go silent while we thought it was on).
            let pattern = try CHHapticPattern(events: [
                continuous(intensity: 1, sharpness: 0.5, at: 0, duration: 1)
            ], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            try player.start(atTime: CHHapticTimeImmediate)
            try player.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0)
            ], atTime: CHHapticTimeImmediate)
            continuousPlayer = player
            continuousOn = true
        } catch {
            print("Haptics: continuous start failed: \(error)")
            needsStart = true
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
        guard let engine, ensureStarted() else { return }
        do {
            try makeAndStart(events, on: engine)
        } catch {
            // Engine was stopped under us — restart once and retry so this cue isn't lost.
            needsStart = true
            guard ensureStarted() else { return }
            do {
                try makeAndStart(events, on: engine)
            } catch {
                print("Haptics: play failed: \(error)")
            }
        }
    }

    private func makeAndStart(_ events: [CHHapticEvent], on engine: CHHapticEngine) throws {
        let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
        try player.start(atTime: CHHapticTimeImmediate)
    }
}
