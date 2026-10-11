import ARKit
import AVFoundation
import Combine
import CoreMotion
import os
import Speech
import UIKit

/// Freeroam: haptics-only walking (White Cane / Night Vision style). Navigate may use spatial + voice.
@MainActor
final class FreeroamEngine: NSObject, ObservableObject, ARSessionDelegate {
    enum Mode: String {
        case freeroam
        case navigate
    }

    @Published private(set) var distances = SIMD3<Float>(repeating: 5)
    @Published private(set) var alert: ObstacleAlert?
    @Published private(set) var caption = ""
    @Published private(set) var status = "Starting"
    @Published private(set) var isSpeaking = false
    @Published private(set) var quietMode = false
    @Published private(set) var washSide: Zone?
    @Published private(set) var washStrength: Double = 0
    @Published private(set) var headphoneStatus = ""
    @Published private(set) var lastHeard = ""
    @Published var navigateGoal = ""
    @Published private(set) var navigateStepText = ""
    /// Live line for the status panel while a target is pinned: "Door · 12 ft · slightly left".
    @Published private(set) var navTargetStatus: String?
    @Published private(set) var mode: Mode = .freeroam
    /// Walking, from ARKit's tracked position. Spoken directions are only useful while moving.
    @Published private(set) var isMoving = false
    /// Called when the wearer asks to leave ("Vantage, go back"); the screen dismisses itself.
    var onExitRequested: (() -> Void)?

    enum ListenState { case idle, listening, thinking }
    /// Drives the Siri-style edge glow: listening after the wake word, thinking while answering.
    @Published private(set) var listenState: ListenState = .idle
    private var listenTimeout: Task<Void, Never>?
    /// Optional LiDAR night-vision depth image (full frame, not L/C/R bars).
    @Published private(set) var nightVisionImage: CGImage?
    /// True when the room is dark enough that we replace the camera with full night vision.
    @Published private(set) var nightVisionFullFrame = false

    let session = ARSession()
    let headphones = HeadphoneMotion()
    let spatial = SpatialTone()
    let navigate = NavigateSession()
    let settings = DetectionSettings.shared

    private let haptics = HapticPulser()
    private let speaker = Speaker.shared
    private let listener = AlwaysListener()
    private let motion = CMMotionManager()

    private let smoothingFrames = 5
    private var history: [SIMD3<Float>] = []
    private var lastPulse = Date.distantPast
    private var lastStop = Date.distantPast
    private var lastVoice = Date.distantPast
    private var lastClearVoice = Date.distantPast
    private var wasInPath = false
    private var stableZone: Zone?
    private var zoneHits = 0
    private let zoneHysteresis = 4
    private var usesLiDAR = false
    private var isForeground = true
    private var handlingUtterance = false
    private var awaitingRequestUntil = Date.distantPast
    private var flipWarned = false
    private var motionSample: (time: TimeInterval, position: SIMD2<Float>)?
    private var lastWalkingTime: TimeInterval = 0
    private var walkingSpeedMeasured: Float = 0
    /// Horizontal speed that counts as walking (a slow walk is ~0.8 m/s; chest sway stays well below).
    private let walkingSpeed: Float = 0.3
    /// How long below walking speed before we treat the wearer as standing still.
    private let stillAfter: TimeInterval = 2
    private var healthTask: Task<Void, Never>?
    private let frameQueue = DispatchQueue(label: "vantage.frames", qos: .userInteractive)
    private nonisolated(unsafe) var lastFrameUptime: TimeInterval = 0
    private nonisolated(unsafe) var lastMonoTime = Date.distantPast
    /// Mirrors settings.nightVision for the ARKit delegate queue.
    private nonisolated(unsafe) var renderNightVision = false
    private nonisolated(unsafe) var nightVisionModeCached: NightVisionMode = .color
    /// Hysteresis so full-frame night vision doesn’t flicker at the threshold.
    private nonisolated(unsafe) var sceneIsDark = false
    private nonisolated(unsafe) var darkStreak = 0
    private nonisolated(unsafe) var lightStreak = 0
    private var lastSessionRun = Date.distantPast
    /// True while a frame update is queued for the main actor. Frames that arrive meanwhile are
    /// skipped instead of queued — each queued update used to hold its ARFrame, and ARKit stops
    /// delivering camera images once ~10 frames are held ("delegate is retaining N ARFrames").
    private nonisolated let mainUpdatePending = OSAllocatedUnfairLock(initialState: false)
    /// Camera-only distance runs Vision (30–50 ms), so it gets its own queue and skips while busy.
    private let monoQueue = DispatchQueue(label: "vantage.mono", qos: .userInitiated)
    private nonisolated let monoBusy = OSAllocatedUnfairLock(initialState: false)
    /// Reads destination signs on-device while navigating (LiDAR phones). Own queue, skips while busy.
    nonisolated let signSpotter = SignSpotter()
    private let signQueue = DispatchQueue(label: "vantage.signs", qos: .utility)
    private nonisolated let signBusy = OSAllocatedUnfairLock(initialState: false)
    private nonisolated(unsafe) var spotSigns = false
    private nonisolated(unsafe) var lastSignScan: TimeInterval = 0

    /// The few numbers the main actor needs from a frame — never the ARFrame itself.
    private struct FrameMotion: Sendable {
        let timestamp: TimeInterval
        let position: SIMD2<Float>
        let trackingNormal: Bool
        /// Full camera pose, for Navigate's bearing/distance to a pinned target.
        let cameraTransform: simd_float4x4
    }

    func start(mode: Mode, goal: String = "") {
        self.mode = mode
        navigateGoal = goal
        SceneAI.startMonitoring()
        AVAudioSession.sharedInstance().requestRecordPermission { @Sendable _ in }
        SFSpeechRecognizer.requestAuthorization { @Sendable _ in }
        try? Speaker.configureAudioSession()

        usesLiDAR = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        session.delegate = self
        session.delegateQueue = frameQueue
        runSession()
        headphones.start()
        listener.onUtterance = { [weak self] text in
            Task { @MainActor in self?.handleUtterance(text) }
        }
        listener.onWake = { [weak self] in
            Task { @MainActor in self?.interruptedByWearer() }
        }
        listener.start()
        startFlipMonitor()
        startHealthCheck()
        status = mode == .navigate ? "Navigate" : "Freeroam"
        headphoneStatus = headphones.statusLine

        if mode == .navigate {
            navigate.start(goal: goal, engine: self)
        }
        spotSigns = mode == .navigate && usesLiDAR

        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            let line = mode == .navigate
                ? "Navigating to \(goal). I'll guide you using what I can see. Say Vantage, next, for another step, "
                    + "or Vantage, go back, for the main menu."
                : "Freeroam. Vibrations watch the path. Say Vantage to ask me something, "
                    + "or Vantage, go back, for the main menu."
            self.say(line, interrupt: true)
        }
    }

    func stop() {
        healthTask?.cancel()
        spotSigns = false
        navigate.stop()
        navTargetStatus = nil
        listener.stop()
        speaker.stop()
        spatial.stop()
        haptics.setContinuousClose(false)
        headphones.stop()
        session.pause()
        motion.stopAccelerometerUpdates()
    }

    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        if foreground {
            lastSessionRun = Date()
            listener.start()
        } else {
            listener.stop()
            speaker.stop()
        }
    }

    // MARK: - ARKit

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastFrameUptime = ProcessInfo.processInfo.systemUptime

        guard let depth = frame.sceneDepth else {
            // No LiDAR: estimate from the camera image ~5×/s, off this queue so frames don't back up.
            let now = Date()
            guard now.timeIntervalSince(lastMonoTime) >= 0.2,
                  Self.claim(monoBusy)
            else { return }
            lastMonoTime = now
            let motion = Self.motion(of: frame)
            monoQueue.async { [weak self] in
                let distances = MonocularDistanceEstimator.nearestPerZone(in: frame).distances
                self?.monoBusy.withLock { $0 = false }
                self?.deliver(distances: distances, motion: motion, nightImage: nil)
            }
            return
        }

        let distances = DepthZoneAnalyzer.nearestPerZone(in: depth).distances
        // Only render while night vision is on. Smoothed depth flickers less.
        var nightCG: CGImage?
        var fullFrame = false
        // Skipped when the main actor hasn't taken the last frame yet — this one would be dropped.
        if renderNightVision, !mainUpdatePending.withLock({ $0 }),
           let overlayDepth = frame.smoothedSceneDepth ?? frame.sceneDepth {
            fullFrame = updateDarkness(luma: NightVisionRenderer.cameraLuma(of: frame))
            nightCG = NightVisionRenderer.cgImage(
                from: overlayDepth,
                camera: frame.camera,
                mode: nightVisionModeCached,
                opaque: fullFrame
            )
        } else if !renderNightVision {
            sceneIsDark = false
            darkStreak = 0
            lightStreak = 0
        }
        deliver(distances: distances, motion: Self.motion(of: frame), nightImage: nightCG, fullFrame: fullFrame)

        // Navigate: look for the destination's sign about twice a second.
        if spotSigns, frame.timestamp - lastSignScan >= 0.5, Self.claim(signBusy) {
            lastSignScan = frame.timestamp
            let spotter = signSpotter
            signQueue.async { [weak self] in
                let match = spotter.scan(frame)
                self?.signBusy.withLock { $0 = false }
                if let match {
                    Task { @MainActor in self?.navigate.pinSign(match) }
                }
            }
        }
    }

    /// Enter full night vision after several dark frames; leave after several lit ones.
    private nonisolated func updateDarkness(luma: Float) -> Bool {
        // ~0–255 Y plane. A lit room is usually well above 40; pitch dark sits under ~18.
        if luma < 18 {
            darkStreak += 1
            lightStreak = 0
            if darkStreak >= 4 { sceneIsDark = true }
        } else if luma > 32 {
            lightStreak += 1
            darkStreak = 0
            if lightStreak >= 4 { sceneIsDark = false }
        } else {
            darkStreak = 0
            lightStreak = 0
        }
        return sceneIsDark
    }

    /// Sets the flag if it was clear; false if it's already set.
    private nonisolated static func claim(_ flag: OSAllocatedUnfairLock<Bool>) -> Bool {
        flag.withLock { isSet in
            if isSet { return false }
            isSet = true
            return true
        }
    }

    private nonisolated static func motion(of frame: ARFrame) -> FrameMotion {
        let translation = frame.camera.transform.columns.3
        var normal = false
        if case .normal = frame.camera.trackingState { normal = true }
        return FrameMotion(
            timestamp: frame.timestamp,
            position: SIMD2(translation.x, translation.z),
            trackingNormal: normal,
            cameraTransform: frame.camera.transform
        )
    }

    /// Hands one frame's results to the main actor, dropping it if the last hand-off is still pending.
    private nonisolated func deliver(
        distances: SIMD3<Float>,
        motion: FrameMotion,
        nightImage: CGImage?,
        fullFrame: Bool = false
    ) {
        guard Self.claim(mainUpdatePending) else { return }
        Task { @MainActor in
            defer { self.mainUpdatePending.withLock { $0 = false } }
            self.renderNightVision = self.settings.nightVision
            self.nightVisionModeCached = self.settings.nightVisionMode
            if !self.settings.nightVision {
                self.nightVisionImage = nil
                self.nightVisionFullFrame = false
            } else {
                if let nightImage { self.nightVisionImage = nightImage }
                self.nightVisionFullFrame = fullFrame
            }
            self.updateMotion(motion)
            if self.mode == .navigate {
                self.navigate.update(camera: motion.cameraTransform)
                self.refreshNavStatus()
            }
            self.ingest(distances)
        }
    }

    private func refreshNavStatus() {
        var status: String?
        if let target = navigate.target, let guidance = navigate.guidance, let beacon = navigate.beacon {
            let distance = target.measured ? "\(NavGuidance.feet(guidance.distance)) ft" : "far"
            status = "\(NavGuidance.capitalized(target.label)) · \(distance) · \(NavGuidance.directionWords(beacon.bearing))"
        }
        if status != navTargetStatus { navTargetStatus = status }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.status = message }
    }

    // MARK: - Safety loop

    private func updateMotion(_ frame: FrameMotion) {
        guard frame.trackingNormal else {
            // Tracking can't tell us — keep speaking safety cues rather than risk silence while walking.
            isMoving = true
            motionSample = nil
            return
        }
        let position = frame.position
        guard let sample = motionSample else {
            motionSample = (frame.timestamp, position)
            return
        }
        let elapsed = frame.timestamp - sample.time
        guard elapsed >= 0.5 else { return }
        motionSample = (frame.timestamp, position)
        walkingSpeedMeasured = simd_distance(position, sample.position) / Float(elapsed)
        if walkingSpeedMeasured > walkingSpeed {
            lastWalkingTime = frame.timestamp
        }
        isMoving = frame.timestamp - lastWalkingTime < stillAfter
    }

    private func ingest(_ reading: SIMD3<Float>) {
        history.append(reading)
        if history.count > smoothingFrames { history.removeFirst() }
        distances = history.reduce(SIMD3<Float>(repeating: 0), +) / Float(history.count)

        let raw = AlertPolicy.alert(
            for: distances,
            maxDistance: settings.maxDistance,
            quickResponse: settings.quickResponse
        )
        if let raw {
            if raw.zone == stableZone {
                zoneHits += 1
            } else {
                stableZone = raw.zone
                zoneHits = 1
            }
            if zoneHits >= zoneHysteresis {
                alert = raw
            }
        } else {
            stableZone = nil
            zoneHits = 0
            alert = nil
        }

        headphoneStatus = headphones.statusLine
        applyCues()
        speaker.recoverIfStuck()
        let speaking = speaker.isSpeaking
        if speaking != isSpeaking {
            isSpeaking = speaking
            spatial.setSpeaking(speaking)
            syncListener()
        }
        speakWarnings()
    }

    private func applyCues() {
        let now = Date()

        if mode == .freeroam {
            // Haptics only — no beeps, no spatial tone, no L/C/R wash.
            washSide = nil
            washStrength = 0
            spatial.drive(pan: 0, closeness: 0, headphonesConnected: false)

            guard let alert else {
                haptics.setContinuousClose(false)
                if now.timeIntervalSince(lastPulse) >= 1.4 {
                    lastPulse = now
                    haptics.heartbeat()
                }
                return
            }

            let veryClose = alert.distance < AlertPolicy.stopDistance
            if settings.continuousCloseVibration, veryClose {
                haptics.setContinuousClose(true, intensity: alert.intensity)
                return
            }
            haptics.setContinuousClose(false)

            if now.timeIntervalSince(lastPulse) >= alert.interval {
                lastPulse = now
                haptics.play(settings.pattern(for: alert.band), intensity: alert.intensity)
            }
            return
        }

        // Navigate: a hazard within 2 m takes the spatial tone; otherwise the beacon sits on the pinned
        // target. Haptics still pulse for any hazard.
        haptics.setContinuousClose(false)
        if let alert, alert.distance < AlertPolicy.announceDistance {
            let closeness = Double(alert.intensity)
            spatial.drive(
                bearingRadians: alert.zone.bearingRadians,
                distanceMeters: alert.distance,
                closeness: closeness,
                listener: headphones.listener,
                headphonesConnected: headphones.usingHeadphones
            )
            washSide = alert.zone
            washStrength = closeness
        } else if let beacon = navigate.beacon {
            // A little louder as you close in.
            let closeness = 0.35 + 0.35 * Double(1 - min(beacon.distance, 10) / 10)
            spatial.drive(
                bearingRadians: beacon.bearing,
                distanceMeters: beacon.distance,
                closeness: closeness,
                listener: headphones.listener,
                headphonesConnected: headphones.usingHeadphones
            )
            washSide = NavGuidance.zone(for: beacon.bearing)
            washStrength = 0.45
        } else {
            spatial.drive(pan: 0, closeness: 0, headphonesConnected: headphones.usingHeadphones)
            washSide = nil
            washStrength = 0
        }
        if let alert, now.timeIntervalSince(lastPulse) >= alert.interval {
            lastPulse = now
            haptics.play(settings.pattern(for: alert.band), intensity: alert.intensity)
        }
    }

    private func speakWarnings() {
        // Freeroam: no automatic speech while walking — haptics only (ask with “Vantage…”).
        guard mode == .navigate else { return }
        guard !handlingUtterance, !quietMode, settings.speechFeedback || mode == .navigate else { return }
        let now = Date()
        guard now >= awaitingRequestUntil else { return }

        guard let alert else {
            if wasInPath, now.timeIntervalSince(lastClearVoice) > 8, now.timeIntervalSince(lastVoice) > 3 {
                if say("Clear path", allowNetwork: false) {
                    lastClearVoice = now
                }
            }
            wasInPath = false
            return
        }

        let inPath = alert.distance < AlertPolicy.announceDistance
        if inPath, isMoving { wasInPath = true }

        if isMoving, alert.distance < AlertPolicy.stopDistance, now.timeIntervalSince(lastStop) > 4 {
            lastStop = now
            let dodge = dodgePhrase(for: alert).map { "Stop, \($0)" } ?? "Stop"
            say(dodge, interrupt: true, allowNetwork: false)
        }
    }

    private func dodgePhrase(for alert: ObstacleAlert) -> String? {
        let left = distances[Zone.left.rawValue]
        let center = distances[Zone.center.rawValue]
        let right = distances[Zone.right.rawValue]
        if center < AlertPolicy.announceDistance {
            let side = left >= right ? "left" : "right"
            return max(left, right) >= max(center + 0.7, 1.5) ? "move \(side)" : "turn \(side)"
        }
        if alert.distance < AlertPolicy.stopDistance {
            return alert.zone == .left ? "move right" : "move left"
        }
        return nil
    }

    // MARK: - Voice

    private func handleUtterance(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastHeard = trimmed
        // Only "Vantage …" is for us — ignore anything else the mic picks up.
        guard let command = Self.stripWakePrefix(trimmed) else { return }
        awaitingRequestUntil = .distantPast
        listenTimeout?.cancel()
        guard !command.isEmpty else {
            // "Vantage" and then nothing — let the glow fade out.
            listenState = .idle
            if caption == "Listening…" { caption = "" }
            return
        }
        Earcon.play(.heard)
        listenState = .thinking
        Task {
            await handleCommand(command)
            listenState = .idle
        }
    }

    /// Wake word heard: stop talking, chime, and show the listening glow until the request arrives.
    private func interruptedByWearer() {
        speaker.stop()
        isSpeaking = false
        caption = "Listening…"
        awaitingRequestUntil = Date().addingTimeInterval(7)
        syncListener()
        Earcon.play(.listening)
        listenState = .listening
        listenTimeout?.cancel()
        listenTimeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            guard !Task.isCancelled, listenState == .listening else { return }
            listenState = .idle
            if caption == "Listening…" { caption = "" }
        }
    }

    private func syncListener() {
        let talking = speaker.isSpeaking
        if handlingUtterance || talking && caption.lowercased().contains("vantage") {
            listener.setPaused(true)
        } else {
            listener.setSpeaking(talking)
            listener.setPaused(false)
        }
    }

    private func handleCommand(_ command: String) async {
        let lowered = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        handlingUtterance = true
        defer {
            handlingUtterance = false
            syncListener()
        }

        // Local commands only — never spend Gemini/Gemma quota on these.
        if handleLocalCommand(lowered) { return }

        if lowered == "next" || lowered.hasPrefix("next ") || lowered.contains("another step") {
            if mode == .navigate {
                await navigate.requestStep(force: true)
            } else {
                say(Features.navigate
                    ? "Freeroam has no steps. Start Navigate from the menu, or ask what's ahead."
                    : "Freeroam has no steps. Ask me what's ahead.")
            }
            return
        }
        if lowered.contains("where am i") || lowered.contains("what's ahead") || lowered.contains("whats ahead")
            || lowered.contains("what is ahead") || lowered.contains("what's in front") {
            await answerScene(question: command)
            return
        }
        if lowered.contains("name") || lowered.contains("what is that") || lowered.contains("what's that") {
            await nameNearest()
            return
        }
        if mode == .navigate, lowered.contains("arrived") || lowered.contains("i'm here") || lowered.contains("im here") {
            say("Great. You can go back when you're ready.", interrupt: true)
            return
        }

        await answerScene(question: command)
    }

    /// Settings / mode toggles handled on-device with bundled or system TTS only.
    @discardableResult
    private func handleLocalCommand(_ lowered: String) -> Bool {
        // Leave the session by voice. Specific phrases only — "exit" alone could be a question
        // about an exit door.
        if ["go back", "main menu", "end session", "stop session", "change mode", "switch mode", "leave"]
            .contains(where: lowered.hasPrefix) {
            say("Going back to the main menu.", interrupt: true, allowNetwork: false)
            Task { @MainActor in
                await speaker.waitUntilIdle(timeout: 4)
                onExitRequested?()
            }
            return true
        }
        if matchesNightVision(lowered) {
            applyNightVisionCommand(lowered)
            return true
        }
        if lowered.contains("quiet") {
            quietMode = true
            say("Quiet mode. Haptics only.", interrupt: true, allowNetwork: false)
            return true
        }
        if lowered.contains("speak") || lowered.contains("talk") {
            quietMode = false
            say("Speaking on.", interrupt: true, allowNetwork: false)
            return true
        }
        if lowered.contains("haptic") && (lowered.contains("indoor") || lowered.contains("outdoor")
            || lowered.contains("universal") || lowered.contains("alert mode")) {
            if lowered.contains("indoor") {
                settings.alertMode = .indoor
                say("Indoor alert mode.", interrupt: true, allowNetwork: false)
            } else if lowered.contains("outdoor") {
                settings.alertMode = .outdoor
                say("Outdoor alert mode.", interrupt: true, allowNetwork: false)
            } else if lowered.contains("universal") {
                settings.alertMode = .universal
                say("Universal alert mode.", interrupt: true, allowNetwork: false)
            }
            return true
        }
        return false
    }

    private func matchesNightVision(_ lowered: String) -> Bool {
        lowered.contains("night vision")
            || lowered.contains("nightvision")
            || lowered.contains("lidar vision")
            || lowered.contains("lid ar vision")
            || (lowered.contains("night") && lowered.contains("vision"))
    }

    private func applyNightVisionCommand(_ lowered: String) {
        let wantsOff = lowered.contains("off") || lowered.contains("disable") || lowered.contains("stop")
            || lowered.contains("hide") || lowered.contains("turn off") || lowered.contains("switch off")
        let wantsOn = lowered.contains("on") || lowered.contains("enable") || lowered.contains("start")
            || lowered.contains("show") || lowered.contains("turn on") || lowered.contains("switch on")
            || lowered.contains("activate")

        if wantsOff && !wantsOn {
            settings.nightVision = false
            nightVisionImage = nil
            nightVisionFullFrame = false
            say("Night vision off.", interrupt: true, allowNetwork: false)
            return
        }
        if wantsOn && !wantsOff {
            settings.nightVision = true
            say(usesLiDAR ? "Night vision on." : "Night vision on. Needs LiDAR for the depth view.",
                interrupt: true, allowNetwork: false)
            return
        }
        // "night vision" / "toggle night vision" with no clear on/off → toggle
        settings.nightVision.toggle()
        if !settings.nightVision {
            nightVisionImage = nil
            nightVisionFullFrame = false
        }
        say(settings.nightVision ? "Night vision on." : "Night vision off.",
            interrupt: true, allowNetwork: false)
    }

    private func answerScene(question: String) async {
        guard let frame = session.currentFrame,
              let snap = FrameSnapshot(frame: frame) else {
            say("I can't see a frame right now.")
            return
        }
        caption = "Thinking…"
        let reply = await SceneAI.answer(question, jpeg: snap.jpeg, frame: frame, context: sceneContext(for: frame))
        say(reply, interrupt: true)
    }

    /// Everything the phone knows right now, for the model prompt.
    func sceneContext(for frame: ARFrame? = nil) -> SceneContext {
        let frame = frame ?? session.currentFrame

        var nearest: SceneContext.Nearest?
        var labels: [String] = []
        var depthGrid: [[Float?]]?
        var pitch: Float?
        var tracking = "unavailable"
        if let frame {
            labels = SceneLabels.classify(frame)
            if let depth = frame.sceneDepth { depthGrid = DepthZoneAnalyzer.grid(in: depth) }

            if let zone = Zone.allCases.min(by: { distances[$0.rawValue] < distances[$1.rawValue] }),
               distances[zone.rawValue] < SceneContext.maxRange * 0.99 {
                let reading = frame.sceneDepth.map { DepthZoneAnalyzer.nearestPerZone(in: $0) }
                    ?? MonocularDistanceEstimator.nearestPerZone(in: frame)
                let point = reading.points[zone.rawValue] ?? SIMD2(0.5, 0.5)
                nearest = .init(zone: zone, distance: distances[zone.rawValue],
                                name: ObstacleNamer.name(in: frame, at: point))
            }

            // Camera looks down its -Z axis; its world-space y component is the tilt.
            let forward = -frame.camera.transform.columns.2
            pitch = asin(max(-1, min(1, forward.y))) * 180 / .pi

            switch frame.camera.trackingState {
            case .normal: tracking = "good"
            case .notAvailable: tracking = "unavailable"
            case .limited(let reason):
                switch reason {
                case .excessiveMotion: tracking = "limited (moving fast)"
                case .insufficientFeatures: tracking = "limited (few visual features, maybe dark or blank wall)"
                case .initializing, .relocalizing: tracking = "starting up"
                @unknown default: tracking = "limited"
                }
            }
        }

        return SceneContext(
            mode: mode,
            goal: mode == .navigate ? navigateGoal : nil,
            lastStep: mode == .navigate ? navigateStepText : nil,
            usesLiDAR: frame?.sceneDepth != nil,
            zoneDistances: distances,
            depthGrid: depthGrid,
            nearest: nearest,
            isMoving: isMoving,
            speed: walkingSpeedMeasured,
            cameraPitchDegrees: pitch,
            tracking: tracking,
            ambientIntensity: frame?.lightEstimate.map { Float($0.ambientIntensity) },
            labels: labels,
            headphones: headphones.usingHeadphones ? headphones.statusLine : "phone speaker"
        )
    }

    private func nameNearest() async {
        guard let frame = session.currentFrame else {
            say("I don't have a clear name for that.", interrupt: true)
            return
        }
        let reading: DepthReading
        if let depth = frame.sceneDepth {
            reading = DepthZoneAnalyzer.nearestPerZone(in: depth)
        } else {
            reading = MonocularDistanceEstimator.nearestPerZone(in: frame)
        }
        guard let alert else {
            say("Nothing close enough to name.", interrupt: true, allowNetwork: false)
            return
        }
        let point = reading.points[alert.zone.rawValue] ?? SIMD2(0.5, 0.5)
        if let name = ObstacleNamer.name(in: frame, at: point) {
            say("\(name) \(directionWord(alert.zone))", interrupt: true, allowNetwork: false)
        } else {
            say("Obstacle \(directionWord(alert.zone))", interrupt: true, allowNetwork: false)
        }
    }

    private func directionWord(_ zone: Zone) -> String {
        switch zone {
        case .left: return "on your left"
        case .center: return "ahead"
        case .right: return "on your right"
        }
    }

    @discardableResult
    func say(_ text: String, interrupt: Bool = false, allowNetwork: Bool = true) -> Bool {
        caption = text
        let ok = speaker.say(text, interrupt: interrupt, allowNetwork: allowNetwork)
        if ok { lastVoice = Date() }
        return ok
    }

    /// Photo and depth from the same instant, so a point Gemini picks in the photo can be pinned in 3D.
    func navigateSnapshot() -> (jpeg: Data, depth: DepthSnapshot?)? {
        guard let frame = session.currentFrame, let jpeg = FrameSnapshot(frame: frame)?.jpeg else { return nil }
        return (jpeg, DepthSnapshot(frame: frame))
    }

    func updateNavigateStep(_ text: String) {
        navigateStepText = text
    }

    // MARK: - Session hygiene

    private func runSession() {
        let configuration = ARWorldTrackingConfiguration()
        if usesLiDAR {
            configuration.frameSemantics = .sceneDepth
            // Night-vision overlay; safety distances keep using the faster raw sceneDepth.
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                configuration.frameSemantics.insert(.smoothedSceneDepth)
            }
        }
        session.run(configuration)
        lastSessionRun = Date()
    }

    private func startHealthCheck() {
        healthTask?.cancel()
        healthTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.checkHealth()
            }
        }
    }

    private func checkHealth() {
        guard isForeground else { return }
        let sinceFrame = ProcessInfo.processInfo.systemUptime - lastFrameUptime
        if sinceFrame > 8, Date().timeIntervalSince(lastSessionRun) > 15 {
            runSession()
        }
        if !handlingUtterance {
            syncListener()
            listener.ensureRunning()
        }
    }

    private func startFlipMonitor() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.5
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data, !self.flipWarned else { return }
            if data.acceleration.z > 0.7 {
                self.flipWarned = true
                self.say("Phone may be facing the wrong way.", interrupt: true, allowNetwork: false)
            }
        }
    }

    static func stripWakePrefix(_ text: String) -> String? {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for wake in Brand.wakePhrases {
            if lowered == wake { return "" }
            if lowered.hasPrefix(wake + ",") || lowered.hasPrefix(wake + " ") {
                return String(lowered.dropFirst(wake.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
            }
        }
        return nil
    }
}
