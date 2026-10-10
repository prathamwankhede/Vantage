import AVFoundation

enum TTSClient {
    struct Failure: Error {}

    static func synthesize(_ text: String) async throws -> Data {
        var request: URLRequest
        if Secrets.backendURL.isEmpty {
            guard !Secrets.elevenLabsKey.isEmpty, !Secrets.elevenLabsVoiceID.isEmpty,
                  let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(Secrets.elevenLabsVoiceID)?output_format=mp3_44100_128")
            else { throw Failure() }
            request = URLRequest(url: url)
            request.setValue(Secrets.elevenLabsKey, forHTTPHeaderField: "xi-api-key")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "text": text,
                "model_id": "eleven_flash_v2_5"
            ])
        } else {
            guard let url = URL(string: Secrets.backendURL + "/tts") else { throw Failure() }
            request = URLRequest(url: url)
            request.setValue(Secrets.backendKey, forHTTPHeaderField: "x-functions-key")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 6

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure() }
        return data
    }
}

@MainActor
final class Speaker: NSObject, AVAudioPlayerDelegate {
    static let shared = Speaker()

    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var requestID = 0
    private var queuedClips: [URL] = []
    private var queuedPan: Float = 0
    private var fetching = false
    private var busySince: Date?
    private let stuckAfter: TimeInterval = 30

    var isSpeaking: Bool {
        player?.isPlaying == true || synthesizer.isSpeaking || !queuedClips.isEmpty || fetching
    }

    /// Shared session for TTS, mic, and spatial tones.
    nonisolated static func configureAudioSession() throws {
        let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP]
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord
            || session.mode != .measurement
            || session.categoryOptions != options {
            try session.setCategory(.playAndRecord, mode: .measurement, options: options)
        }
        try session.setActive(true)
    }

    @discardableResult
    func say(_ text: String, pan: Float = 0, interrupt: Bool = false, allowNetwork: Bool = true) -> Bool {
        if isSpeaking {
            guard interrupt else { return false }
            stop()
        }
        requestID += 1
        let id = requestID

        if let url = Self.clipURL(for: text), start(try? AVAudioPlayer(contentsOf: url), pan: pan) {
            return true
        }
        if let urls = Self.clipURLs(forParts: text), start(try? AVAudioPlayer(contentsOf: urls[0]), pan: pan) {
            queuedClips = Array(urls.dropFirst())
            queuedPan = pan
            return true
        }
        guard allowNetwork else {
            synthesizer.speak(AVSpeechUtterance(string: text))
            return true
        }
        fetching = true
        Task {
            let data = try? await TTSClient.synthesize(text)
            guard id == self.requestID else { return }
            self.fetching = false
            if let data, self.start(try? AVAudioPlayer(data: data), pan: pan) { return }
            self.synthesizer.speak(AVSpeechUtterance(string: text))
        }
        return true
    }

    func recoverIfStuck() {
        let playing = player?.isPlaying == true || synthesizer.isSpeaking || fetching
        if !queuedClips.isEmpty, !playing {
            let next = queuedClips.removeFirst()
            if !start(try? AVAudioPlayer(contentsOf: next), pan: queuedPan) { queuedClips = [] }
        }
        guard isSpeaking else {
            busySince = nil
            return
        }
        let since = busySince ?? Date()
        busySince = since
        if Date().timeIntervalSince(since) > stuckAfter { stop() }
    }

    func stop() {
        requestID += 1
        fetching = false
        busySince = nil
        queuedClips = []
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)
    }

    func waitUntilIdle(timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while isSpeaking, !Task.isCancelled, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func start(_ newPlayer: AVAudioPlayer?, pan: Float) -> Bool {
        guard let newPlayer else { return false }
        player?.delegate = nil
        player?.stop()
        newPlayer.pan = pan
        newPlayer.delegate = self
        player = newPlayer
        return newPlayer.play()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(finished)
        Task { @MainActor in
            guard let player, ObjectIdentifier(player) == id, !queuedClips.isEmpty else { return }
            let next = queuedClips.removeFirst()
            if !start(try? AVAudioPlayer(contentsOf: next), pan: queuedPan) { queuedClips = [] }
        }
    }

    static func slug(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private static func clipURLs(forParts text: String) -> [URL]? {
        let parts = text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return nil }
        let urls = parts.compactMap(clipURL(for:))
        return urls.count == parts.count ? urls : nil
    }

    private static func clipURL(for text: String) -> URL? {
        let name = slug(text)
        return Bundle.main.url(forResource: name, withExtension: "mp3")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Phrases")
    }
}
