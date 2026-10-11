import ARKit
import Vision

/// Reads text in the camera image a couple of times a second and reports a sign that matches the
/// destination ("214", "Pharmacy"), already pinned in 3D. On-device and offline. Call `scan` from
/// one serial queue; it holds the frame only for the duration of the call.
final class SignSpotter: @unchecked Sendable {
    struct Match: Sendable {
        let text: String
        let world: SIMD3<Float>
        let measured: Bool
    }

    private let lock = NSLock()
    private var keywords: [String] = []
    // Debounce state — only touched from the scanning queue.
    private var candidate: (key: String, at: Date)?
    private var pinnedAt: [String: Date] = [:]

    private static let fillerWords: Set<String> = ["the", "a", "an", "to", "room", "my", "your", "of", "front", "main"]

    /// Keywords from the destination: numbers must match whole ("214"); words need 4+ letters ("pharmacy").
    func setGoal(_ goal: String) {
        let tokens = goal.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !Self.fillerWords.contains($0) }
        let keys = tokens.filter { $0.allSatisfy(\.isNumber) || $0.count >= 4 }
        lock.withLock { keywords = keys }
    }

    func scan(_ frame: ARFrame) -> Match? {
        let keys = lock.withLock { keywords }
        guard !keys.isEmpty else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let now = Date()
        for observation in request.results ?? [] {
            guard let best = observation.topCandidates(1).first, best.confidence >= 0.5 else { continue }
            let words = best.string.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            guard let key = keys.first(where: { key in
                key.allSatisfy(\.isNumber) ? words.contains(key) : words.contains { $0.hasPrefix(key) }
            }) else { continue }

            if let pinned = pinnedAt[key], now.timeIntervalSince(pinned) < 30 { continue }

            // Same sign twice in a row (~0.5 s apart) before trusting it — single OCR reads flicker.
            guard let previous = candidate, previous.key == key, now.timeIntervalSince(previous.at) < 1.5 else {
                candidate = (key, now)
                return nil
            }
            candidate = nil
            guard let depth = DepthSnapshot(frame: frame) else { return nil }
            // Vision boxes are normalized in the oriented (upright) image with a bottom-left origin.
            let box = observation.boundingBox
            let center = SIMD2(Float(box.midX), Float(1 - box.midY))
            let (point, measured) = depth.worldPoint(uprightNormalized: center)
            pinnedAt[key] = now
            return Match(text: best.string, world: point, measured: measured)
        }
        return nil
    }
}
