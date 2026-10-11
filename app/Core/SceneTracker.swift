import ARKit
import Vision

struct SceneObject: Sendable, Equatable {
    var id: String
    var name: String
    var zone: Zone
    var distance: Float
    var isSpecial: Bool
}

/// On-device people + labeled objects merged with zone depths. Call from a background queue.
enum SceneTracker {
    private static let specials: Set<String> = ["Door", "Stairs", "Elevator"]
    private static let maxObjects = 6

    nonisolated static func scan(frame: ARFrame, distances: SIMD3<Float>) -> [SceneObject] {
        var found: [SceneObject] = []

        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let classify = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)
        do {
            try handler.perform([humans, classify])
        } catch {
            return []
        }

        if let people = humans.results {
            for (index, person) in people.enumerated() where person.confidence > 0.4 {
                let zone = zone(for: Float(person.boundingBox.midX))
                let distance = distances[zone.rawValue]
                guard distance < 2.8 else { continue }
                found.append(SceneObject(
                    id: "person-\(zone.rawValue)-\(index)",
                    name: "Person",
                    zone: zone,
                    distance: distance,
                    isSpecial: false
                ))
            }
        }

        for observation in classify.results ?? [] where observation.confidence >= 0.28 {
            guard let name = ObstacleNamer.spokenNames[observation.identifier] else { continue }
            // Classifier is whole-frame; put unknown objects in the closest occupied zone.
            let zone = nearestBusyZone(distances) ?? .center
            let distance = distances[zone.rawValue]
            guard distance < 2.8 else { continue }
            let special = specials.contains(name)
            found.append(SceneObject(
                id: "\(name.lowercased())-\(zone.rawValue)",
                name: name,
                zone: zone,
                distance: distance,
                isSpecial: special
            ))
        }

        // Prefer people and specials, then nearer.
        found.sort {
            if $0.isSpecial != $1.isSpecial { return $0.isSpecial && !$1.isSpecial }
            if ($0.name == "Person") != ($1.name == "Person") { return $0.name == "Person" }
            return $0.distance < $1.distance
        }
        var seen = Set<String>()
        var unique: [SceneObject] = []
        for object in found {
            let key = "\(object.name)-\(object.zone.rawValue)"
            if seen.insert(key).inserted { unique.append(object) }
            if unique.count >= maxObjects { break }
        }
        return unique
    }

    private nonisolated static func zone(for midX: Float) -> Zone {
        if midX < 0.33 { return .left }
        if midX > 0.66 { return .right }
        return .center
    }

    private nonisolated static func nearestBusyZone(_ distances: SIMD3<Float>) -> Zone? {
        let clear: Float = 4.5
        var best: Zone?
        var bestD = clear
        for zone in [Zone.left, .center, .right] {
            let d = distances[zone.rawValue]
            if d < bestD {
                bestD = d
                best = zone
            }
        }
        return bestD < clear ? best : nil
    }
}
