import AVFoundation
import Foundation
import Speech

/// Always-on listener. Wake word is "Vantage".
///
/// The microphone stays running for the whole time the listener is enabled; only the speech
/// recognition request is swapped between utterances. Restarting the audio engine after every
/// phrase used to leave a few hundred milliseconds where "Vantage" went unheard.
@MainActor
final class AlwaysListener: NSObject {
    var onUtterance: ((String) -> Void)?
    var onWake: (() -> Void)?

    private var audioEngine = AVAudioEngine()
    private let feed = MicFeed()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var enabled = false
    private var paused = false
    private var restarting = false
    private var generation = 0
    private var latestText = ""
    private var silenceTask: Task<Void, Never>?
    /// Silence that ends an utterance. Longer once the wake word is heard, so a pause while
    /// phrasing the question doesn't cut it off; shorter otherwise so chatter clears quickly.
    private let idleSilence: UInt64 = 800_000_000
    private let requestSilence: UInt64 = 1_600_000_000
    private var speaking = false
    private var wokeAt: Date?
    /// The wake word was heard in an earlier recognition session (the recognizer finalized during
    /// the pause after "Vantage"), so everything in this session is the request.
    private var wakeCarriedOver = false
    private let requestWait: TimeInterval = 6
    private var configObserver: NSObjectProtocol?

    override init() {
        super.init()
        // Route changes (AirPods, calls) stop the engine; bring the mic back up.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] notification in
            let engine = notification.object as AnyObject?
            Task { @MainActor in
                guard let self, engine === self.audioEngine else { return }
                self.stopAudio()
                if self.enabled, !self.paused { self.scheduleRestart(after: 300_000_000) }
            }
        }
    }

    func start() {
        enabled = true
        paused = false
        beginRecognition()
    }

    func stop() {
        enabled = false
        clearWake()
        endRecognition()
        stopAudio()
    }

    func ensureRunning() {
        guard enabled, !paused, !restarting else { return }
        if request != nil, audioEngine.isRunning { return }
        beginRecognition()
    }

    func setSpeaking(_ speaking: Bool) {
        guard speaking != self.speaking else { return }
        self.speaking = speaking
        if speaking { clearWake() }
        if !speaking, wokeAt == nil, request != nil {
            // Fresh request so the transcript of Vantage's own speech is dropped.
            beginRecognition()
        }
    }

    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        if paused {
            clearWake()
            endRecognition()
        } else if enabled {
            beginRecognition()
        }
    }

    // MARK: - Audio

    /// Starts the mic once and leaves it running; recognition requests attach to `feed`.
    private func startAudioIfNeeded() -> Bool {
        if audioEngine.isRunning { return true }
        do { try Speaker.configureAudioSession() } catch { /* retry via schedule */ }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        input.removeTap(onBus: 0)
        let feed = self.feed
        do {
            // installTap raises an Objective-C exception (uncatchable in Swift) when the audio
            // session changed under a cached input format. Rebuild the engine and retry instead.
            try ObjCException.catching {
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    feed.append(buffer)
                }
            }
        } catch {
            print("AlwaysListener: installTap failed, rebuilding audio engine: \(error.localizedDescription)")
            audioEngine = AVAudioEngine()
            return false
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            return true
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
    }

    private func stopAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - Recognition

    private func beginRecognition() {
        endRecognition()
        guard enabled, !paused, let recognizer, recognizer.isAvailable,
              SFSpeechRecognizer.authorizationStatus() == .authorized
        else {
            scheduleRestart(after: 1_000_000_000)
            return
        }
        guard startAudioIfNeeded() else {
            scheduleRestart(after: 500_000_000)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        // "Vantage" is an unusual word; tell the recognizer to expect it.
        request.contextualStrings = ["Vantage", "Hey Vantage", "Vantage, what's ahead"]
        self.request = request
        feed.attach(request)

        generation += 1
        let session = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                self?.handle(text: text, isFinal: isFinal, failed: failed, session: session)
            }
        }
    }

    private func endRecognition() {
        silenceTask?.cancel()
        silenceTask = nil
        latestText = ""
        generation += 1
        feed.detach()
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool, session: Int) {
        guard session == generation, request != nil else { return }
        if let text, !text.isEmpty {
            latestText = text
            if !speaking {
                // Signal the wake word the moment it's heard (not when the sentence ends), so the
                // UI can chime and glow while the wearer is still talking.
                if wokeAt == nil, Self.textAfterWake(text) != nil {
                    wokeAt = Date()
                    onWake?()
                }
                waitForSilence()
            } else if Self.textAfterWake(text) != nil {
                speaking = false
                wokeAt = Date()
                onWake?()
                waitForSilence()
            }
        }
        if isFinal || failed {
            if speaking {
                beginRecognition()
            } else if wokeAt != nil, pendingRequest.isEmpty, !requestTimedOut {
                // The recognizer finalized during the pause after "Vantage". Keep listening for
                // the question in a fresh request instead of waiting on one that has stopped.
                wakeCarriedOver = true
                beginRecognition()
                waitForSilence()   // keeps the 6 s request timeout ticking if they say nothing
            } else {
                finishUtterance()
            }
        }
    }

    /// What the wearer has asked so far, after the wake word.
    private var pendingRequest: String {
        let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let afterWake = Self.textAfterWake(text) { return afterWake }
        return wakeCarriedOver ? text.lowercased() : ""
    }

    private var requestTimedOut: Bool {
        guard let wokeAt else { return true }
        return Date().timeIntervalSince(wokeAt) >= requestWait
    }

    private func waitForSilence() {
        silenceTask?.cancel()
        let delay = wokeAt == nil ? idleSilence : requestSilence
        silenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            finishUtterance()
        }
    }

    private func finishUtterance() {
        var text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        if wokeAt != nil {
            let request = pendingRequest
            if request.isEmpty, !requestTimedOut {
                // Bare "Vantage" — keep waiting for the question.
                if self.request == nil {
                    wakeCarriedOver = true
                    beginRecognition()
                }
                waitForSilence()
                return
            }
            clearWake()
            text = "Vantage, " + request
        }
        if !text.isEmpty { onUtterance?(text) }
        // New request right away — the mic never stopped, so there's no deaf gap.
        if enabled, !paused { beginRecognition() } else { endRecognition() }
    }

    private func clearWake() {
        wokeAt = nil
        wakeCarriedOver = false
    }

    private func scheduleRestart(after delay: UInt64) {
        guard enabled, !paused, !restarting else { return }
        restarting = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            self.restarting = false
            if self.enabled, !self.paused, self.request == nil { self.beginRecognition() }
        }
    }

    private static func textAfterWake(_ text: String) -> String? {
        let lowered = text.lowercased()
        let ranges = Brand.wakePhrases.compactMap { lowered.range(of: $0, options: .backwards) }
        guard let last = ranges.max(by: { $0.upperBound < $1.upperBound }) else { return nil }
        return String(lowered[last.upperBound...]).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }
}

/// Hands mic buffers from the audio thread to whichever recognition request is current.
private final class MicFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }

    func attach(_ request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
    }

    func detach() {
        lock.lock()
        defer { lock.unlock() }
        request = nil
    }
}
