import ARKit
import CoreGraphics
import simd
import UIKit

/// How LiDAR depth is painted on screen.
enum NightVisionMode: String, CaseIterable, Identifiable {
    /// Rainbow by distance (navy → red). Default overlay look.
    case color
    /// Depth normals + virtual light so surfaces read with volume.
    case spatial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: return "Color"
        case .spatial: return "3D Spatial"
        }
    }

    var detail: String {
        switch self {
        case .color: return "Distance rainbow over the camera."
        case .spatial: return "Lighting and shadow from depth so objects look solid."
        }
    }
}

/// LiDAR depth visualisation.
/// - Lit room: translucent overlay on the camera (existing look).
/// - Dark room: auto full-frame opaque night vision (camera is useless).
enum NightVisionRenderer {
    private static let maxDepth: Float = 10
    private static let overlayAlpha: Float = 220 / 255
    private static let fadeOutDepth: Float = 0.3

    private static let stops: [SIMD3<Float>] = [
        SIMD3(3, 20, 142),
        SIMD3(25, 65, 187),
        SIMD3(48, 113, 234),
        SIMD3(72, 161, 180),
        SIMD3(95, 209, 101),
        SIMD3(117, 251, 76),
        SIMD3(146, 252, 77),
        SIMD3(211, 253, 80),
        SIMD3(248, 215, 72),
        SIMD3(237, 125, 48),
        SIMD3(234, 55, 35)
    ]

    private static let lutSize = 1024
    private static let colorLUT: [(UInt8, UInt8, UInt8, UInt8)] = (0..<lutSize).map { index in
        let depth = Float(index) / Float(lutSize - 1) * maxDepth
        let alpha = overlayAlpha * min(1, (maxDepth - depth) / fadeOutDepth)
        let rgb = color(at: depth / maxDepth) * alpha
        return (UInt8(rgb.x), UInt8(rgb.y), UInt8(rgb.z), UInt8(alpha * 255))
    }

    private static func color(at t: Float) -> SIMD3<Float> {
        let scaled = min(max(t, 0), 1) * Float(stops.count - 1)
        let index = min(Int(scaled), stops.count - 2)
        return simd_mix(stops[index], stops[index + 1], SIMD3(repeating: scaled - Float(index)))
    }

    /// Mean luma 0…255 from the camera Y plane. Cheap; samples a sparse grid.
    nonisolated static func cameraLuma(of frame: ARFrame) -> Float {
        let buffer = frame.capturedImage
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 128 }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let stepX = max(1, width / 32)
        let stepY = max(1, height / 24)
        var sum: Int = 0
        var count = 0
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var y = 0
        while y < height {
            let row = ptr + y * rowBytes
            var x = 0
            while x < width {
                sum += Int(row[x])
                count += 1
                x += stepX
            }
            y += stepY
        }
        return count > 0 ? Float(sum) / Float(count) : 128
    }

    nonisolated static func cgImage(
        from depthData: ARDepthData,
        camera: ARCamera,
        mode: NightVisionMode,
        opaque: Bool
    ) -> CGImage? {
        switch mode {
        case .color:
            return colorImage(from: depthData.depthMap, opaque: opaque)
        case .spatial:
            return spatialImage(from: depthData.depthMap, camera: camera, opaque: opaque)
        }
    }

    // MARK: - Color (heatmap)

    private nonisolated static func colorImage(from map: CVPixelBuffer, opaque: Bool) -> CGImage? {
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }

        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let scale = Float(lutSize - 1) / maxDepth
        for y in 0..<height {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                let d = row[x]
                let i = (y * width + x) * 4
                guard d.isFinite, d > 0, d < maxDepth else {
                    if opaque {
                        rgba[i] = 4; rgba[i + 1] = 8; rgba[i + 2] = 14; rgba[i + 3] = 255
                    }
                    continue
                }
                if opaque {
                    let rgb = color(at: d / maxDepth)
                    rgba[i] = UInt8(min(255, rgb.x))
                    rgba[i + 1] = UInt8(min(255, rgb.y))
                    rgba[i + 2] = UInt8(min(255, rgb.z))
                    rgba[i + 3] = 255
                } else {
                    let c = colorLUT[min(lutSize - 1, Int(d * scale))]
                    rgba[i] = c.0; rgba[i + 1] = c.1; rgba[i + 2] = c.2; rgba[i + 3] = c.3
                }
            }
        }
        return makeCGImage(rgba: rgba, width: width, height: height)
    }

    // MARK: - 3D Spatial (normals + light)

    private nonisolated static func spatialImage(
        from map: CVPixelBuffer,
        camera: ARCamera,
        opaque: Bool
    ) -> CGImage? {
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }

        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard width > 2, height > 2, let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)

        // Depth buffer is a scaled camera image — scale intrinsics to depth resolution.
        let imageSize = camera.imageResolution
        let sx = Float(width) / Float(imageSize.width)
        let sy = Float(height) / Float(imageSize.height)
        let fx = camera.intrinsics[0, 0] * sx
        let fy = camera.intrinsics[1, 1] * sy
        let cx = camera.intrinsics[2, 0] * sx
        let cy = camera.intrinsics[2, 1] * sy

        func depthAt(_ x: Int, _ y: Int) -> Float {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float32.self)
            return row[x]
        }
        func point(_ x: Int, _ y: Int, _ z: Float) -> SIMD3<Float> {
            SIMD3((Float(x) - cx) * z / fx, (Float(y) - cy) * z / fy, z)
        }

        // Key light from upper-left, slight fill so dark rooms aren't crushed.
        let light = simd_normalize(SIMD3<Float>(-0.45, -0.75, 0.55))
        let ambient: Float = 0.22
        let diffuse: Float = 0.78

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let z = depthAt(x, y)
                let i = (y * width + x) * 4
                guard z.isFinite, z > 0.12, z < maxDepth else {
                    if opaque {
                        rgba[i] = 4; rgba[i + 1] = 8; rgba[i + 2] = 14; rgba[i + 3] = 255
                    }
                    continue
                }
                let zl = depthAt(x - 1, y)
                let zr = depthAt(x + 1, y)
                let zu = depthAt(x, y - 1)
                let zd = depthAt(x, y + 1)
                guard zl.isFinite, zr.isFinite, zu.isFinite, zd.isFinite,
                      zl > 0, zr > 0, zu > 0, zd > 0 else {
                    if opaque {
                        rgba[i] = 4; rgba[i + 1] = 8; rgba[i + 2] = 14; rgba[i + 3] = 255
                    }
                    continue
                }

                let p = point(x, y, z)
                let dx = point(x + 1, y, zr) - point(x - 1, y, zl)
                let dy = point(x, y + 1, zd) - point(x, y - 1, zu)
                var n = simd_cross(dx, dy)
                let len = simd_length(n)
                guard len > 1e-6 else { continue }
                n /= len
                // Face the camera (negative Z).
                if n.z > 0 { n = -n }

                let shade = ambient + diffuse * max(0, simd_dot(n, light))
                // Cool teal-green night-vision base, slightly warmer when closer.
                let nearness = 1 - min(1, z / maxDepth)
                var rgb = SIMD3<Float>(
                    20 + 40 * nearness,
                    160 + 70 * nearness,
                    120 + 40 * (1 - nearness)
                ) * shade
                rgb = simd_min(rgb, SIMD3(repeating: 255))

                let alpha: Float = opaque
                    ? 1
                    : overlayAlpha * min(1, (maxDepth - z) / fadeOutDepth)
                rgba[i] = UInt8(rgb.x * alpha)
                rgba[i + 1] = UInt8(rgb.y * alpha)
                rgba[i + 2] = UInt8(rgb.z * alpha)
                rgba[i + 3] = UInt8(alpha * 255)
            }
        }
        return makeCGImage(rgba: rgba, width: width, height: height)
    }

    private nonisolated static func makeCGImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
