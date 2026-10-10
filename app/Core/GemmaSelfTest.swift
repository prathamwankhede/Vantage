#if DEBUG
import UIKit

/// Launch with `-GemmaSelfTest` to load Gemma and ask one text and one image question
/// without voice. Results print to the console prefixed with `GEMMA-SELFTEST`.
@MainActor
enum GemmaSelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-GemmaSelfTest") else { return }
        Task {
            let sensors = sampleContext.promptText
            print("GEMMA-SELFTEST sensors:\n\(sensors)")

            var started = Date()
            let text = await GemmaClient.answer(question: "What's ahead?", sensors: sensors)
            print("GEMMA-SELFTEST status: \(GemmaClient.status.label)")
            print("GEMMA-SELFTEST text (\(seconds(since: started))s): \(text ?? "nil")")

            started = Date()
            let vision = await GemmaClient.answer(
                question: "What does the sign ahead say, and how far is it?",
                sensors: sensors,
                jpeg: signImage()
            )
            print("GEMMA-SELFTEST vision (\(seconds(since: started))s): \(vision ?? "nil")")
        }
    }

    /// A typical indoor reading: chair close on the left, sign about 3 m ahead.
    private static var sampleContext: SceneContext {
        SceneContext(
            mode: .freeroam,
            usesLiDAR: true,
            zoneDistances: SIMD3(0.9, 3.1, 5),
            depthGrid: [[2.4, 3.1, nil], [0.9, 3.1, nil], [0.8, 1.2, 1.3]],
            nearest: .init(zone: .left, distance: 0.9, name: "Chair"),
            isMoving: false,
            speed: 0,
            cameraPitchDegrees: -12,
            tracking: "good",
            ambientIntensity: 820,
            labels: ["Chair", "Sign"],
            headphones: "phone speaker"
        )
    }

    private static func seconds(since date: Date) -> String {
        String(format: "%.1f", Date().timeIntervalSince(date))
    }

    /// A green exit sign, so a correct vision answer is easy to recognise.
    private static func signImage() -> Data? {
        let size = CGSize(width: 768, height: 576)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let sign = CGRect(x: 184, y: 188, width: 400, height: 200)
            UIColor(red: 0, green: 0.6, blue: 0.25, alpha: 1).setFill()
            context.fill(sign)
            let text = NSAttributedString(string: "EXIT", attributes: [
                .font: UIFont.systemFont(ofSize: 120, weight: .heavy),
                .foregroundColor: UIColor.white
            ])
            let textSize = text.size()
            text.draw(at: CGPoint(x: sign.midX - textSize.width / 2, y: sign.midY - textSize.height / 2))
        }
        return image.jpegData(compressionQuality: 0.6)
    }
}
#endif
