import AVFoundation

/// Short UI tones. Synthesized once in memory and played through the app's playAndRecord
/// session, so (unlike system sounds) the silent switch doesn't mute them.
@MainActor
enum Earcon {
    /// Rising two-note "ting": the wake word was heard and Vantage is listening.
    case listening
    /// Soft falling note: got the request, working on it.
    case heard

    private static var players: [Earcon: AVAudioPlayer] = [:]

    static func play(_ earcon: Earcon) {
        let player = players[earcon] ?? makePlayer(for: earcon)
        players[earcon] = player
        player?.currentTime = 0
        player?.play()
    }

    private static func makePlayer(for earcon: Earcon) -> AVAudioPlayer? {
        let notes: [(frequency: Double, duration: Double)]
        switch earcon {
        case .listening: notes = [(880, 0.075), (1318.5, 0.16)]   // A5 → E6
        case .heard: notes = [(1046.5, 0.06), (784, 0.12)]        // C6 → G5
        }
        let player = try? AVAudioPlayer(data: wav(notes), fileTypeHint: AVFileType.wav.rawValue)
        player?.volume = earcon == .listening ? 0.7 : 0.45
        player?.prepareToPlay()
        return player
    }

    /// Bell-like sine notes (fast attack, exponential decay, a little second harmonic) as 16-bit mono WAV.
    private static func wav(_ notes: [(frequency: Double, duration: Double)]) -> Data {
        let sampleRate = 44_100
        var samples: [Int16] = []
        for note in notes {
            let count = Int(Double(sampleRate) * note.duration)
            for index in 0..<count {
                let t = Double(index) / Double(sampleRate)
                let attack = min(1, t / 0.004)
                let fundamental = sin(2 * .pi * note.frequency * t) * exp(-t * 16)
                let overtone = sin(4 * .pi * note.frequency * t) * exp(-t * 32) * 0.25
                let value = (fundamental + overtone) * attack * 0.55
                samples.append(Int16(max(-1, min(1, value)) * Double(Int16.max)))
            }
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))                 // fmt chunk size
        append(UInt16(1))                  // PCM
        append(UInt16(1))                  // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))     // byte rate
        append(UInt16(2))                  // block align
        append(UInt16(16))                 // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(byteCount))
        samples.forEach { append($0) }
        return data
    }
}
