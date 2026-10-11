import ARKit
import simd

/// Depth and camera pose copied out of one ARFrame (it never retains the frame), so a point picked
/// in that frame's photo — by Gemini or by sign reading — can be pinned as a fixed 3D world point
/// after the frame is gone.
struct DepthSnapshot: Sendable {
    let cameraTransform: simd_float4x4
    private let intrinsics: simd_float3x3
    private let imageResolution: SIMD2<Float>
    private let depth: [Float32]
    private let confidence: [UInt8]
    private let width: Int
    private let height: Int

    /// Used when LiDAR has no reading at the point (too far, glass, open air): the bearing is still
    /// right, and the distance gets corrected by the next step.
    static let fallbackDistance: Float = 4

    init?(frame: ARFrame) {
        guard let data = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
        let map = data.depthMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }

        width = CVPixelBufferGetWidth(map)
        height = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        var values = [Float32](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<width { values[y * width + x] = row[x] }
        }
        depth = values

        var levels = [UInt8](repeating: UInt8(ARConfidenceLevel.high.rawValue), count: width * height)
        if let confidenceMap = data.confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
            if let confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap) {
                let confidenceRowBytes = CVPixelBufferGetBytesPerRow(confidenceMap)
                for y in 0..<height {
                    let row = (confidenceBase + y * confidenceRowBytes).assumingMemoryBound(to: UInt8.self)
                    for x in 0..<width { levels[y * width + x] = row[x] }
                }
            }
        }
        confidence = levels

        cameraTransform = frame.camera.transform
        intrinsics = frame.camera.intrinsics
        imageResolution = SIMD2(Float(frame.camera.imageResolution.width), Float(frame.camera.imageResolution.height))
    }

    /// World point for a spot in the upright (portrait) photo, normalized with a top-left origin.
    /// `measured` is false when there was no depth there and the point sits `fallbackDistance` along the ray.
    func worldPoint(uprightNormalized point: SIMD2<Float>) -> (point: SIMD3<Float>, measured: Bool) {
        // Upright photo is the sensor image rotated right: sensor x = upright y, sensor y = 1 - upright x.
        let sensor = SIMD2(point.y, 1 - point.x)
        let measuredDepth = medianDepth(nearSensor: sensor)
        let d = measuredDepth ?? Self.fallbackDistance

        // Unproject through the camera intrinsics (pixels at capturedImage resolution). ARKit camera
        // space: x right, y up, looking down -z; image y grows downward.
        let u = sensor.x * imageResolution.x
        let v = sensor.y * imageResolution.y
        let fx = intrinsics[0][0], fy = intrinsics[1][1]
        let cx = intrinsics[2][0], cy = intrinsics[2][1]
        let cameraPoint = SIMD4<Float>((u - cx) / fx * d, -(v - cy) / fy * d, -d, 1)
        let world = cameraTransform * cameraPoint
        return (SIMD3(world.x, world.y, world.z), measuredDepth != nil)
    }

    /// Median of confident depths in a small window — one pixel is too noisy at object edges.
    private func medianDepth(nearSensor point: SIMD2<Float>, radius: Int = 3) -> Float? {
        let centerX = min(max(Int(point.x * Float(width)), 0), width - 1)
        let centerY = min(max(Int(point.y * Float(height)), 0), height - 1)
        var samples: [Float] = []
        for y in max(0, centerY - radius)...min(height - 1, centerY + radius) {
            for x in max(0, centerX - radius)...min(width - 1, centerX + radius) {
                let index = y * width + x
                let value = depth[index]
                if confidence[index] >= UInt8(ARConfidenceLevel.medium.rawValue), value.isFinite, value > 0.15 {
                    samples.append(value)
                }
            }
        }
        guard samples.count >= 5 else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }
}
