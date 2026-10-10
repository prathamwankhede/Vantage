import ARKit

/// Last-resort templates when Gemini and on-device Gemma are both unavailable.
enum OfflineAnswers {
    static func answer(_ question: String, in frame: ARFrame) -> String {
        let labels = SceneLabels.classify(frame)
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
}
