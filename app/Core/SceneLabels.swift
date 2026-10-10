import ARKit
import Vision

/// Shared on-device vision labels for Gemma prompts and template fallback.
enum SceneLabels {
    static func classify(_ frame: ARFrame) -> [String] {
        let classify = VNClassifyImageRequest()
        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)
        do {
            try handler.perform([classify, humans])
        } catch {
            return []
        }

        var names: [String] = []
        if let people = humans.results, people.contains(where: { $0.confidence > 0.45 }) {
            names.append("Person")
        }
        for observation in classify.results ?? [] where observation.confidence >= 0.2 {
            if let name = ObstacleNamer.spokenNames[observation.identifier], !names.contains(name) {
                names.append(name)
            }
            if names.count >= 4 { break }
        }
        return names
    }

    static func summary(for frame: ARFrame) -> String {
        let labels = classify(frame)
        if labels.isEmpty { return "No clear objects labeled." }
        return labels.joined(separator: ", ")
    }
}
