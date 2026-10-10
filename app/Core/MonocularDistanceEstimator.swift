import ARKit
import Vision

/// Camera-only distance estimate for iPhones without LiDAR.
enum MonocularDistanceEstimator {
    static let maxRange: Float = 5
    static let minRange: Float = 0.4
    private static let assumedHeights: [String: Float] = [
        "Person": 1.7, "Chair": 0.9, "Table": 0.75, "Car": 1.5,
        "Bicycle": 1.1, "Door": 2.0, "Dog": 0.5, "Bench": 0.5,
        "Trash can": 0.9, "Backpack": 0.5
    ]
    private static let verticalFOVDegrees: Float = 60

    nonisolated static func nearestPerZone(in frame: ARFrame) -> DepthReading {
        var distances = SIMD3<Float>(repeating: maxRange)
        var points: [SIMD2<Float>?] = [nil, nil, nil]

        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let classify = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)

        do {
            try handler.perform([humans, classify])
        } catch {
            return DepthReading(distances: distances, points: points)
        }

        if let people = humans.results {
            for person in people where person.confidence > 0.4 {
                absorb(box: person.boundingBox, name: "Person", into: &distances, points: &points)
            }
        }

        if distances[Zone.center.rawValue] >= maxRange * 0.99,
           let top = classify.results?.first(where: {
               $0.confidence >= 0.25 && ObstacleNamer.spokenNames[$0.identifier] != nil
           }),
           let name = ObstacleNamer.spokenNames[top.identifier] {
            let guess = name == "Car" ? Float(4.0) : Float(2.5)
            distances[Zone.center.rawValue] = min(distances[Zone.center.rawValue], guess)
            points[Zone.center.rawValue] = SIMD2(0.5, 0.5)
        }

        return DepthReading(distances: distances, points: points)
    }

    private nonisolated static func absorb(
        box: CGRect,
        name: String,
        into distances: inout SIMD3<Float>,
        points: inout [SIMD2<Float>?]
    ) {
        let midX = Float(box.midX)
        let zone: Zone
        if midX < 0.33 { zone = .left }
        else if midX > 0.66 { zone = .right }
        else { zone = .center }

        let height = assumedHeights[name] ?? 1.0
        let fovRad = verticalFOVDegrees * .pi / 180
        let frac = max(Float(box.height), 0.02)
        let distance = max(minRange, min(maxRange, height / (2 * tan(fovRad / 2) * frac)))

        if distance < distances[zone.rawValue] {
            distances[zone.rawValue] = distance
            points[zone.rawValue] = SIMD2(midX, 1 - Float(box.midY))
        }
    }
}
