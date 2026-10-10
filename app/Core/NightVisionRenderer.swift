import ARKit
import CoreGraphics
import UIKit

/// Full-frame LiDAR depth as a colour overlay.
/// Closest → farthest: navy → blue → green → yellow → orange → red; nothing drawn beyond `maxDepth`.
///
/// The image keeps the depth map's native sensor orientation and full resolution (256×192) —
/// `CameraPreview` places it with ARKit's display transform so it lines up with the camera feed.
enum NightVisionRenderer {
    /// Depths at or beyond this (metres) get no overlay, so the camera shows through.
    private static let maxDepth: Float = 10
    /// Overlay alpha for in-range depths.
    private static let overlayAlpha: Float = 220 / 255
    /// The last stretch before `maxDepth` fades out so red doesn't end in a hard edge.
    private static let fadeOutDepth: Float = 0.3

    /// Evenly spaced colour stops from closest (0) to farthest (1), linearly blended between.
    /// Sampled at 10% steps from the "Default" depth gradient the team picked.
    private static let stops: [SIMD3<Float>] = [
        SIMD3(3, 20, 142),     // navy
        SIMD3(25, 65, 187),
        SIMD3(48, 113, 234),   // blue
        SIMD3(72, 161, 180),   // teal
        SIMD3(95, 209, 101),   // green
        SIMD3(117, 251, 76),
        SIMD3(146, 252, 77),   // lime
        SIMD3(211, 253, 80),
        SIMD3(248, 215, 72),   // yellow
        SIMD3(237, 125, 48),   // orange
        SIMD3(234, 55, 35)     // red
    ]

    /// Premultiplied RGBA per depth step, so the per-pixel loop is a table lookup.
    private static let lutSize = 1024
    private static let lut: [(UInt8, UInt8, UInt8, UInt8)] = (0..<lutSize).map { index in
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

    nonisolated static func cgImage(from depthData: ARDepthData) -> CGImage? {
        let map = depthData.depthMap
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
                // No reading or out of range: leave the pixel fully transparent.
                guard d.isFinite, d > 0, d < maxDepth else { continue }
                let c = lut[min(lutSize - 1, Int(d * scale))]
                let i = (y * width + x) * 4
                rgba[i] = c.0
                rgba[i + 1] = c.1
                rgba[i + 2] = c.2
                rgba[i + 3] = c.3
            }
        }

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
