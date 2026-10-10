import ARKit

struct DepthReading {
    /// Nearest obstacle distance in metres as (left, center, right).
    let distances: SIMD3<Float>
    /// Per zone, sample point as fractions of the upright image (x left→right, y top→bottom).
    let points: [SIMD2<Float>?]
}

enum DepthZoneAnalyzer {
    static let maxRange: Float = 5
    static let minRange: Float = 0.15
    static let minSamples = 30
    static let percentile = 0.05
    // Chest-height band so the floor is not an obstacle.
    static let bandTop: Float = 0.35
    static let bandBottom: Float = 0.70

    /// Assumes the phone is worn in portrait.
    nonisolated static func nearestPerZone(in depthData: ARDepthData) -> DepthReading {
        let clear = DepthReading(distances: SIMD3(repeating: maxRange), points: [nil, nil, nil])
        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        if let confidenceMap { CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) }
        defer { if let confidenceMap { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) } }

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return clear }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let depthRowBytes = CVPixelBufferGetBytesPerRow(depthMap)

        let confidenceBase = confidenceMap.flatMap { CVPixelBufferGetBaseAddress($0) }
        let confidenceRowBytes = confidenceMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        // Buffer is landscape sensor orientation; phone in portrait → buffer x = top→bottom, y = right→left.
        let xStart = Int(Float(width) * bandTop)
        let xEnd = Int(Float(width) * bandBottom)

        var samples: [[(depth: Float, x: Int, y: Int)]] = [[], [], []]
        for y in stride(from: 0, to: height, by: 2) {
            let zone = (height - 1 - y) * 3 / height
            let depthRow = (depthBase + y * depthRowBytes).assumingMemoryBound(to: Float32.self)
            let confidenceRow = confidenceBase.map {
                ($0 + y * confidenceRowBytes).assumingMemoryBound(to: UInt8.self)
            }
            for x in stride(from: xStart, to: xEnd, by: 2) {
                if let confidenceRow, confidenceRow[x] < UInt8(ARConfidenceLevel.medium.rawValue) { continue }
                let depth = depthRow[x]
                if depth.isFinite, depth > minRange, depth < maxRange {
                    samples[zone].append((depth, x, y))
                }
            }
        }

        var distances = clear.distances
        var points = clear.points
        for zone in 0..<3 where samples[zone].count >= minSamples {
            samples[zone].sort { $0.depth < $1.depth }
            let chosen = samples[zone][Int(Double(samples[zone].count) * percentile)]
            distances[zone] = chosen.depth
            points[zone] = SIMD2(
                1 - (Float(chosen.y) + 0.5) / Float(height),
                (Float(chosen.x) + 0.5) / Float(width)
            )
        }
        return DepthReading(distances: distances, points: points)
    }
}
