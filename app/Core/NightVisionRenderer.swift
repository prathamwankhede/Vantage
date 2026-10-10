import ARKit
import CoreGraphics
import UIKit

/// Full-frame LiDAR depth as a night-vision style image (not left/center/right bars).
enum NightVisionRenderer {
    /// Max depth mapped to black (metres). Near = bright green.
    private static let maxDepth: Float = 5

    nonisolated static func cgImage(from depthData: ARDepthData) -> CGImage? {
        let map = depthData.depthMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }

        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)

        // Downsample for UI; rotate landscape depth into portrait for the phone.
        let step = 2
        let outW = height / step
        let outH = width / step
        var rgba = [UInt8](repeating: 0, count: outW * outH * 4)

        for oy in 0..<outH {
            for ox in 0..<outW {
                // Inverse of DepthZoneAnalyzer mapping: buffer x ~ portrait y, buffer y ~ portrait x (mirrored).
                let bx = min(width - 1, oy * step)
                let by = min(height - 1, (outW - 1 - ox) * step)
                let row = (base + by * rowBytes).assumingMemoryBound(to: Float32.self)
                let d = row[bx]
                let t = d.isFinite ? min(max(d / maxDepth, 0), 1) : 1
                // Near = bright phosphor green, far = dark (classic night vision feel).
                let g = UInt8((1 - t) * 255)
                let r = UInt8((1 - t) * 40)
                let b = UInt8((1 - t) * 60)
                let i = (oy * outW + ox) * 4
                rgba[i] = r
                rgba[i + 1] = g
                rgba[i + 2] = b
                rgba[i + 3] = 220
            }
        }

        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: outW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
