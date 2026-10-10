import ARKit
import Vision

/// On-device scene answers when Gemini is unreachable.
enum OfflineAnswers {
    static func answer(_ question: String, in frame: ARFrame) -> String {
        let labels = classify(frame)
        let lowered = question.lowercased()

        if lowered.contains("in front") || lowered.contains("ahead") || lowered.contains("see")
            || lowered.contains("what") || lowered.contains("around") {
            if labels.isEmpty { return "I'm not sure what's there." }
            return "I think I see \(labels.prefix(3).joined(separator: ", ")) ahead."
        }
        if lowered.contains("car") || lowered.contains("vehicle") || lowered.contains("traffic") {
            if labels.contains(where: { $0 == "Car" || $0 == "Bicycle" }) {
                return "I think there's a vehicle ahead. Stay back until you're sure."
            }
            return "I don't clearly see a car right now."
        }
        if lowered.contains("person") || lowered.contains("people") {
            if labels.contains("Person") { return "There's a person ahead." }
            return "I don't clearly see a person right now."
        }
        if labels.isEmpty { return "I'm not sure what's there." }
        return "Nearby I notice \(labels.prefix(2).joined(separator: " and "))."
    }

    private static func classify(_ frame: ARFrame) -> [String] {
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
}
