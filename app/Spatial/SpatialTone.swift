import AVFoundation

/// Lock-free level/pan for the audio render thread.
private final class ToneLevel: @unchecked Sendable {
    var value: Float = 0
    var pan: Float = 0
}

/// Continuous spatial tone: louder when closer, panned toward the hazard/landmark.
@MainActor
final class SpatialTone: ObservableObject {
    @Published private(set) var activePan: Float = 0
    @Published private(set) var activeLevel: Float = 0
    @Published private(set) var needsHeadphones = true

    private let audioEngine = AVAudioEngine()
    private let tone = ToneLevel()
    private var sourceNode: AVAudioSourceNode?
    private var starting = false
    private var ducking = false

    func setSpeaking(_ speaking: Bool) {
        ducking = speaking
        // Refresh ducked level immediately.
        tone.value = ducking ? activeLevel * 0.18 : activeLevel
    }

    /// `closeness` 0…1, `pan` −1…1. Level 0 silences the tone.
    func drive(pan: Float, closeness: Double, headphonesConnected: Bool) {
        needsHeadphones = !headphonesConnected
        activePan = pan
        let level = headphonesConnected ? Float(max(0, min(1, closeness))) : 0
        activeLevel = level
        tone.pan = max(-1, min(1, pan))
        tone.value = ducking ? level * 0.18 : level
        if level > 0.02 { ensureRunning() }
    }

    func stop() {
        tone.value = 0
        activeLevel = 0
        if audioEngine.isRunning { audioEngine.stop() }
        if let sourceNode {
            audioEngine.detach(sourceNode)
        }
        sourceNode = nil
    }

    private func ensureRunning() {
        guard sourceNode == nil, !starting else { return }
        starting = true
        Task.detached { [weak self] in
            try? Speaker.configureAudioSession()
            await MainActor.run { self?.attachSource() }
        }
    }

    private func attachSource() {
        defer { starting = false }
        guard sourceNode == nil else { return }

        let tone = self.tone
        var phase: Double = 0
        let freq = 880.0
        let sampleRate = 44_100.0

        let node = AVAudioSourceNode(format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!) {
            _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let level = Double(tone.value)
            let pan = Double(tone.pan)
            let leftGain = Float(sqrt(max(0, (1 - pan) * 0.5)) * level)
            let rightGain = Float(sqrt(max(0, (1 + pan) * 0.5)) * level)
            let step = 2 * Double.pi * freq / sampleRate

            if abl.count >= 2,
               let left = abl[0].mData?.assumingMemoryBound(to: Float.self),
               let right = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                for frame in 0..<Int(frameCount) {
                    let sample = Float(sin(phase) * 0.22)
                    phase += step
                    if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                    left[frame] = sample * leftGain
                    right[frame] = sample * rightGain
                }
            } else if let data = abl.first?.mData?.assumingMemoryBound(to: Float.self) {
                let channels = Int(abl.first?.mNumberChannels ?? 2)
                for frame in 0..<Int(frameCount) {
                    let sample = Float(sin(phase) * 0.22)
                    phase += step
                    if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                    if channels >= 2 {
                        data[frame * channels] = sample * leftGain
                        data[frame * channels + 1] = sample * rightGain
                    } else {
                        data[frame] = sample * Float(level)
                    }
                }
            }
            return noErr
        }

        sourceNode = node
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        do {
            try audioEngine.start()
        } catch {
            audioEngine.detach(node)
            sourceNode = nil
        }
    }
}
