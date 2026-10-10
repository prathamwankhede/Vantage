import ARKit
import CoreImage
import ImageIO

struct FrameSnapshot {
    private static let context = CIContext()
    let jpeg: Data

    init?(frame: ARFrame) {
        let upright = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let scale = 768 / max(upright.extent.width, upright.extent.height)
        let scaled = upright.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let jpeg = FrameSnapshot.context.jpegRepresentation(
            of: scaled,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]
        ) else { return nil }
        self.jpeg = jpeg
    }
}
