import AVFoundation
import Foundation
import Speech

/// Always-on listener. Wake word is "Vantage".
@MainActor
final class AlwaysListener: NSObject {
    var onUtterance: ((String) -> Void)?
    var onWake: (() -> Void)?

    private var audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var enabled = false
    private var paused = false
    private var restarting = false
    private var generation = 0
    private var latestText = ""
    private var silenceTask: Task<Void, Never>?
    private let endOfSpeechDelay: UInt64 = 1_000_000_000
    private var speaking = false
    private var wokeAt: Date?
    private let requestWait: TimeInterval = 6

    func start() {
        enabled = true
        paused = false
        beginSession()
    }

    func stop() {
        enabled = false
        wokeAt = nil
        endSession()
    }

    func ensureRunning() {
        guard enabled, !paused, !restarting else { return }
        if request != nil, audioEngine.isRunning { return }
        beginSession()
    }

    func setSpeaking(_ speaking: Bool) {
        guard speaking != self.speaking else { return }
        self.speaking = speaking
        if speaking { wokeAt = nil }
        if !speaking, wokeAt == nil, request != nil {
            endSession()
            scheduleRestart(after: 150_000_000)
        }
    }

    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        if paused {
            wokeAt = nil
            endSession()
        } else if enabled {
            beginSession()
        }
    }

    private func beginSession() {
        endSession()
        guard enabled, !paused, let recognizer, recognizer.isAvailable,
              SFSpeechRecognizer.authorizationStatus() == .authorized
        else {
            scheduleRestart(after: 1_000_000_000)
            return
        }

        do { try Speaker.configureAudioSession() } catch { /* retry via schedule */ }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            scheduleRestart(after: 500_000_000)
            return
        }
        input.removeTap(onBus: 0)
        do {
            // installTap raises an Objective-C exception (uncatchable in Swift) when the audio
            // session changed under a cached input format. Rebuild the engine and retry instead.
            try ObjCException.catching {
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    request.append(buffer)
                }
            }
        } catch {
            print("AlwaysListener: installTap failed, rebuilding audio engine: \(error.localizedDescription)")
            endSession()
            audioEngine = AVAudioEngine()
            scheduleRestart(after: 500_000_000)
            return
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            endSession()
            scheduleRestart(after: 500_000_000)
            return
        }
        self.request = request

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

    private func handle(text: String?, isFinal: Bool, failed: Bool, session: Int) {
        guard session == generation, request != nil else { return }
        if let text, !text.isEmpty {
            latestText = text
            if !speaking {
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
                endSession()
                scheduleRestart(after: 150_000_000)
            } else {
                finishUtterance()
            }
        }
    }

    private func waitForSilence() {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: endOfSpeechDelay)
            guard !Task.isCancelled else { return }
            finishUtterance()
        }
    }

    private func finishUtterance() {
        var text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let wokeAt {
            let request = Self.textAfterWake(text) ?? ""
            if request.isEmpty, Date().timeIntervalSince(wokeAt) < requestWait, self.request != nil {
                waitForSilence()
                return
            }
            self.wokeAt = nil
            text = "Vantage, " + request
        }
        endSession()
        if !text.isEmpty { onUtterance?(text) }
        scheduleRestart(after: 150_000_000)
    }

    private func scheduleRestart(after delay: UInt64) {
        guard enabled, !paused, !restarting else { return }
        restarting = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            self.restarting = false
            if self.enabled, !self.paused, self.request == nil { self.beginSession() }
        }
    }

    private static func textAfterWake(_ text: String) -> String? {
        let lowered = text.lowercased()
        let ranges = Brand.wakePhrases.compactMap { lowered.range(of: $0, options: .backwards) }
        guard let last = ranges.max(by: { $0.upperBound < $1.upperBound }) else { return nil }
        return String(lowered[last.upperBound...]).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private func endSession() {
        silenceTask?.cancel()
        silenceTask = nil
        latestText = ""
        generation += 1
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
    }
}
