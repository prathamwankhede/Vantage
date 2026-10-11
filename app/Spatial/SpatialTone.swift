import AVFoundation

/// Lock-free level for the mono render callback.
private final class ToneLevel: @unchecked Sendable {
    var value: Float = 0
}

/// HRTF spatial tone via `AVAudioEnvironmentNode` + AirPods head-tracked listener.
/// Source sits in phone/camera space; listener orientation follows head vs phone so you can pinpoint obstacles.
@MainActor
final class SpatialTone: ObservableObject {
    @Published private(set) var activeBearing: Float = 0
    @Published private(set) var activeLevel: Float = 0
    @Published private(set) var needsHeadphones = true
    @Published private(set) var usingHRTF = false

    private let audioEngine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let tone = ToneLevel()
    private var sourceNode: AVAudioSourceNode?
    private var starting = false
    private var ducking = false
    private var attached = false

    func setSpeaking(_ speaking: Bool) {
        ducking = speaking
        tone.value = ducking ? activeLevel * 0.15 : activeLevel
    }

    /// Place a hazard/landmark in camera space and orient the listener from head tracking.
    func drive(
        bearingRadians: Float,
        distanceMeters: Float,
        closeness: Double,
        listener: ListenerOrientation,
        headphonesConnected: Bool
    ) {
        needsHeadphones = !headphonesConnected
        activeBearing = bearingRadians
        let level = headphonesConnected ? Float(max(0, min(1, closeness))) : 0
        activeLevel = level
        tone.value = ducking ? level * 0.15 : level

        guard headphonesConnected, level > 0.02 else { return }

        ensureRunning()
        guard attached, let sourceNode else { return }

        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(
            yaw: listener.yaw,
            pitch: listener.pitch,
            roll: listener.roll
        )

        let r = max(0.35, min(4.5, distanceMeters))
        let x = sin(bearingRadians) * r
        let z = -cos(bearingRadians) * r
        sourceNode.position = AVAudio3DPoint(x: x, y: 0, z: z)
        sourceNode.renderingAlgorithm = .HRTFHQ
        usingHRTF = true
    }

    /// Silence / simple teardown used by Freeroam (haptics-only).
    func drive(pan: Float, closeness: Double, headphonesConnected: Bool) {
        if closeness <= 0.02 || !headphonesConnected {
            activeLevel = 0
            tone.value = 0
            needsHeadphones = !headphonesConnected
            return
        }
        let bearing = pan * (.pi / 2)
        drive(
            bearingRadians: bearing,
            distanceMeters: Float(max(0.4, 2.2 - closeness * 1.6)),
            closeness: closeness,
            listener: .identity,
            headphonesConnected: headphonesConnected
        )
    }

    func stop() {
        tone.value = 0
        activeLevel = 0
        usingHRTF = false
        if audioEngine.isRunning { audioEngine.stop() }
        if let sourceNode {
            audioEngine.detach(sourceNode)
        }
        if attached {
            audioEngine.detach(environment)
        }
        sourceNode = nil
        attached = false
    }

    private func ensureRunning() {
        if attached, audioEngine.isRunning { return }
        guard !starting else { return }
        starting = true
        Task.detached { [weak self] in
            try? Speaker.configureAudioSession()
            await MainActor.run { self?.attachGraph() }
        }
    }

    private func attachGraph() {
        defer { starting = false }
        if attached, audioEngine.isRunning { return }

        if let sourceNode { audioEngine.detach(sourceNode); self.sourceNode = nil }
        if attached { audioEngine.detach(environment); attached = false }

        let sampleRate = 44_100.0
        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let tone = self.tone
        var phase: Double = 0
        let freq = 760.0
        let step = 2 * Double.pi * freq / sampleRate

        let node = AVAudioSourceNode(format: mono) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let level = Double(tone.value)
            guard let data = abl.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(phase) * 0.28 * level)
                phase += step
                if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                data[frame] = sample
            }
            return noErr
        }

        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 0.4
        environment.distanceAttenuationParameters.maximumDistance = 6
        environment.distanceAttenuationParameters.rolloffFactor = 1.2

        audioEngine.attach(environment)
        audioEngine.attach(node)
        audioEngine.connect(node, to: environment, format: mono)
        audioEngine.connect(environment, to: audioEngine.mainMixerNode, format: nil)
        node.renderingAlgorithm = .HRTFHQ
        sourceNode = node
        attached = true

        do {
            try audioEngine.start()
            usingHRTF = true
        } catch {
            audioEngine.detach(node)
            audioEngine.detach(environment)
            sourceNode = nil
            attached = false
            usingHRTF = false
        }
    }
}
