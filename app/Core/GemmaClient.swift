import Foundation

#if canImport(LiteRTLM)
import LiteRTLM
#endif

/// On-device Gemma via Google LiteRT-LM when a `.litertlm` model is installed.
/// See `scripts/download_gemma.sh` and `app/SETUP.md`.
@MainActor
enum GemmaClient {
    enum Failure: Error {
        case unavailable
        case inference
    }

    private static var ready = false
    private static var loadFailed = false

#if canImport(LiteRTLM)
    private static var engine: Engine?
#endif

    static var isReady: Bool { ready }

    static func preload() {
        Task { _ = await ensureLoaded() }
    }

    static func answer(question: String, sceneSummary: String, jpeg: Data? = nil) async -> String? {
        guard await ensureLoaded() else { return nil }

        let prompt = """
        You are Vantage, a calm guide for a blind or low-vision person. \
        Answer in under 18 words. Use left, ahead, or right when useful. \
        Be honest if unsure. Never invent street names or signal colors. \
        On-device vision currently sees: \(sceneSummary). \
        Question: \(question)
        """

#if canImport(LiteRTLM)
        do {
            if let jpeg, let path = try? writeTempJPEG(jpeg),
               let multimodal = try? await generate(prompt: prompt, imagePath: path) {
                return multimodal
            }
            return try await generate(prompt: prompt, imagePath: nil)
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

    @discardableResult
    private static func ensureLoaded() async -> Bool {
        if ready { return true }
        if loadFailed { return false }

#if canImport(LiteRTLM)
        guard let modelPath = resolveModelPath() else {
            loadFailed = true
            print("Gemma: no .litertlm found — run scripts/download_gemma.sh")
            return false
        }
        do {
            let config = try EngineConfig(
                modelPath: modelPath,
                backend: .gpu,
                maxNumTokens: 512,
                cacheDir: NSTemporaryDirectory()
            )
            let engine = Engine(engineConfig: config)
            try await engine.initialize()
            self.engine = engine
            ready = true
            print("Gemma ready: \(modelPath)")
            return true
        } catch {
            loadFailed = true
            print("Gemma load failed: \(error)")
            return false
        }
#else
        loadFailed = true
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

#if canImport(LiteRTLM)
    private static func generate(prompt: String, imagePath: String?) async throws -> String {
        guard let engine else { throw Failure.unavailable }
        let config = ConversationConfig(
            systemMessage: Message(
                "You are Vantage. Keep answers under 18 words. Be calm and honest."
            )
        )
        let conversation = try await engine.createConversation(with: config)
        let message: Message
        if let imagePath {
            message = Message(contents: [
                .imageFile(imagePath),
                .text(prompt)
            ])
        } else {
            message = Message(prompt)
        }
        let response = try await conversation.sendMessage(message)
        let text = response.toString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.inference }
        return text
    }

    private static func writeTempJPEG(_ data: Data) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vantage-gemma-\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url.path
    }
#endif
}
