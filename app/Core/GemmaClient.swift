import Foundation

#if canImport(LiteRTLM)
import LiteRTLM
#endif

/// On-device Gemma via Google LiteRT-LM when a `.litertlm` model is installed.
/// See `scripts/download_gemma.sh` and `app/SETUP.md`.
@MainActor
enum GemmaClient {
    enum Status: Equatable {
        case idle
        case loading
        case ready(backend: String)
        case missingModel
        case unavailable
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "On-device Gemma: not loaded"
            case .loading: return "On-device Gemma: loading…"
            case .ready(let backend): return "On-device Gemma: ready (\(backend))"
            case .missingModel: return "On-device Gemma: model not installed"
            case .unavailable: return "On-device Gemma: LiteRT-LM not linked"
            case .failed: return "On-device Gemma: failed to load"
            }
        }
    }

    private(set) static var status: Status = .idle {
        didSet { NotificationCenter.default.post(name: statusChanged, object: nil) }
    }
    static let statusChanged = Notification.Name("GemmaClient.statusChanged")

    static var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    private static var loadTask: Task<Bool, Never>?

#if canImport(LiteRTLM)
    private static var engine: Engine?
#endif

    /// Starts loading in the background so the first offline question doesn't wait.
    static func preload() {
        Task { _ = await ensureLoaded() }
    }

    static func answer(question: String, sensors: String, jpeg: Data? = nil) async -> String? {
        guard await ensureLoaded() else { return nil }

        let prompt = """
        This photo is from a phone on their chest. \
        Use left, ahead, or right when useful. Be honest if unsure. \
        Never invent street names or signal colors.

        \(GeminiClient.sensorBlock(sensors))

        Question: \(question)
        """

#if canImport(LiteRTLM)
        if let jpeg, let reply = try? await generate([.imageData(jpeg), .text(prompt)]) {
            return reply
        }
        do {
            return try await generate([.text(prompt)])
        } catch {
            print("Gemma inference failed: \(error)")
            return nil
        }
#else
        _ = prompt
        _ = jpeg
        return nil
#endif
    }

    /// One shared load; concurrent callers await the same task. A failed load is retried on the next call.
    private static func ensureLoaded() async -> Bool {
        if isReady { return true }
        if status == .missingModel || status == .unavailable { return false }
        if let loadTask { return await loadTask.value }

        let task = Task { @MainActor in await load() }
        loadTask = task
        let ok = await task.value
        loadTask = nil
        return ok
    }

    private static func load() async -> Bool {
#if canImport(LiteRTLM)
        guard let modelPath = resolveModelPath() else {
            status = .missingModel
            print("Gemma: no .litertlm found — run scripts/download_gemma.sh")
            return false
        }
        status = .loading
        let started = Date()
        var lastError = ""
        for (backend, name) in [(Backend.gpu, "GPU"), (Backend.cpu(), "CPU")] {
            do {
                let config = try EngineConfig(
                    modelPath: modelPath,
                    backend: backend,
                    // GPU vision encoder fails to compile on iPhone and LiteRT segfaults in its cleanup
                    // (seen on iPhone 16 Pro, LiteRT-LM 0.18.0). CPU vision is slower but stable.
                    visionBackend: .cpu(),
                    maxNumTokens: 1024,
                    cacheDir: cacheDirectory()
                )
                let engine = Engine(engineConfig: config)
                try await engine.initialize()
                // The vision encoder loads with the first conversation; do it now, not on the first question.
                _ = try await engine.createConversation(with: nil)
                self.engine = engine
                status = .ready(backend: name)
                print("Gemma ready on \(name) in \(Int(Date().timeIntervalSince(started)))s: \(modelPath)")
                return true
            } catch {
                lastError = "\(error)"
                print("Gemma \(name) load failed: \(error)")
            }
        }
        status = .failed(lastError)
        return false
#else
        status = .unavailable
        print("Gemma: LiteRTLM package not linked — add via XcodeGen / SPM")
        return false
#endif
    }

    /// Looks in bundle `Models/`, then Documents/VantageModels.
    static func resolveModelPath() -> String? {
        let name = Secrets.gemmaModelFileName
        let stem = name.replacingOccurrences(of: ".litertlm", with: "")

        if let url = Bundle.main.url(forResource: stem, withExtension: "litertlm", subdirectory: "Models") {
            return url.path
        }
        if let urls = Bundle.main.urls(forResourcesWithExtension: "litertlm", subdirectory: "Models"),
           let first = urls.first {
            return first.path
        }
        if let url = Bundle.main.url(forResource: stem, withExtension: "litertlm") {
            return url.path
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VantageModels", isDirectory: true)
        let preferred = docs.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred.path
        }
        if let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            return files.first(where: { $0.pathExtension == "litertlm" })?.path
        }
        return nil
    }

    /// Persistent cache so compiled GPU kernels survive relaunches (tmp gets purged).
    private static func cacheDirectory() -> String {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gemma", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

#if canImport(LiteRTLM)
    private static func generate(_ contents: [Content]) async throws -> String {
        guard let engine else { throw GemmaFailure.unavailable }
        let config = ConversationConfig(
            systemMessage: Message(
                "You are Vantage, a calm guide for a blind or low-vision person. "
                    + "Answer in under 18 words. Be calm and honest."
            ),
            thinkingConfig: ThinkingConfig(enableThinking: false)
        )
        let conversation = try await engine.createConversation(with: config)
        let response = try await conversation.sendMessage(Message(contents: contents), maxOutputTokens: 64)
        let text = response.toString
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GemmaFailure.emptyReply }
        return text
    }
#endif
}

private enum GemmaFailure: Error {
    case unavailable
    case emptyReply
}
