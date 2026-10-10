import ARKit
import Vision

/// On-device obstacle naming — used on demand, not every frame.
enum ObstacleNamer {
    static let cropSize: CGFloat = 0.35
    static let minimumConfidence: Float = 0.25

    static let spokenNames: [String: String] = [
        "chair": "Chair", "armchair": "Chair", "folding_chair": "Chair",
        "table": "Table", "desk": "Desk", "sofa": "Couch", "door": "Door",
        "stairs": "Stairs", "people": "Person", "adult": "Person",
        "backpack": "Backpack", "bag": "Bag", "trash_can": "Trash can",
        "bench": "Bench", "bicycle": "Bicycle", "car": "Car", "dog": "Dog",
        "sign": "Sign", "street_sign": "Sign", "cabinet": "Cabinet",
        "bookshelf": "Shelf", "cardboard_box": "Box"
    ]

    nonisolated static func name(in frame: ARFrame, at point: SIMD2<Float>) -> String? {
        let centre = CGPoint(x: CGFloat(point.x), y: 1 - CGFloat(point.y))
        let crop = CGRect(
            x: centre.x - cropSize / 2,
            y: centre.y - cropSize / 2,
            width: cropSize,
            height: cropSize
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !crop.isNull, crop.width > 0, crop.height > 0 else { return nil }

        let classify = VNClassifyImageRequest()
        classify.regionOfInterest = crop
        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false

        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)
        do {
            try handler.perform([classify, humans])
        } catch {
            return nil
        }

        if let people = humans.results,
           people.contains(where: { $0.confidence > 0.5 && $0.boundingBox.intersects(crop) }) {
            return "Person"
        }
        for observation in classify.results ?? [] where observation.confidence >= minimumConfidence {
            if let name = spokenNames[observation.identifier] { return name }
        }
        return nil
    }
}
