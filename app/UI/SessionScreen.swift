import ARKit
import SceneKit
import SwiftUI

struct SessionScreen: View {
    let mode: FreeroamEngine.Mode
    let goal: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var engine = FreeroamEngine()
    @ObservedObject private var settings = DetectionSettings.shared
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(
                session: engine.session,
                depthOverlay: mode == .freeroam && settings.nightVision ? engine.nightVisionImage : nil
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            // Navigate only: soft ear cue wash. Freeroam has no L/C/R bars.
            if mode == .navigate {
                EdgeWash(side: engine.washSide, strength: engine.washStrength)
                    .ignoresSafeArea()
            }

            VStack {
                topBar
                Spacer()
                if !engine.caption.isEmpty {
                    Text(engine.caption)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.cream)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
                        .padding(.bottom, 12)
                }
                StatusBlob(
                    title: distanceTitle,
                    detail: statusDetail,
                    accent: (engine.alert?.distance ?? 99) < AlertPolicy.stopDistance ? Brand.danger : Brand.tealDeep
                )
                .padding(.bottom, 36)
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                DetectionSettingsScreen()
            }
            .preferredColorScheme(.dark)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            engine.start(mode: mode, goal: goal)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            engine.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            engine.setForeground(phase == .active)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                engine.stop()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.cream)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            Text(mode == .navigate ? "Navigate" : "Freeroam")
                .font(Brand.statusFont)
                .foregroundStyle(Brand.cream)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.cream)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Detection settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var distanceTitle: String {
        guard let alert = engine.alert else { return "Clear" }
        let feet = Int((alert.distance * 3.28084).rounded())
        return "\(feet) ft"
    }

    private var statusDetail: String {
        if mode == .freeroam {
            var parts = ["Haptics"]
            parts.append(settings.alertMode.title)
            if let alert = engine.alert {
                parts.append(alert.band.rawValue.capitalized)
            } else {
                parts.append("Path clear")
            }
            if settings.nightVision { parts.append("Night Vision") }
            return parts.joined(separator: " · ")
        }
        var parts: [String] = []
        if engine.quietMode { parts.append("Quiet") }
        if let alert = engine.alert {
            parts.append(alert.zone.label.capitalized)
        } else {
            parts.append("Following landmarks")
        }
        if !engine.navigateStepText.isEmpty {
            parts.append(engine.navigateStepText)
        } else {
            parts.append(engine.headphoneStatus)
        }
        return parts.joined(separator: " · ")
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: ARSession
    /// Night-vision depth image in the sensor's native orientation; nil hides the overlay.
    var depthOverlay: CGImage?

    func makeUIView(context: Context) -> DepthOverlayARView {
        let view = DepthOverlayARView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        view.rendersCameraGrain = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: DepthOverlayARView, context: Context) {
        uiView.setDepthOverlay(depthOverlay)
    }
}

/// Camera view with the depth overlay drawn in the same view, mapped through ARKit's
/// display transform — the same mapping ARSCNView uses for the camera image — so the
/// colours sit exactly on top of what the camera shows.
final class DepthOverlayARView: ARSCNView {
    private let overlayLayer = CALayer()
    private var overlaySize: CGSize = .zero

    override init(frame: CGRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        overlayLayer.anchorPoint = .zero
        overlayLayer.position = .zero
        overlayLayer.opacity = 0.85
        // Smooth upscaling of the 256×192 depth image.
        overlayLayer.magnificationFilter = .linear
        overlayLayer.minificationFilter = .linear
        // No implicit animations — a default fade on every new frame makes the overlay trail behind.
        overlayLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(),
                                "transform": NSNull(), "hidden": NSNull()]
        overlayLayer.isHidden = true
        layer.addSublayer(overlayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setDepthOverlay(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlayLayer.contents = image
        overlayLayer.isHidden = image == nil
        if let image {
            overlaySize = CGSize(width: image.width, height: image.height)
            layoutOverlay()
        }
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutOverlay()
        CATransaction.commit()
    }

    /// Image pixels → normalized image coords → (ARKit display transform) → normalized view
    /// coords → view points. Keeps the overlay on top of the matching camera pixels.
    private func layoutOverlay() {
        guard overlaySize != .zero, bounds.width > 0, let frame = session.currentFrame else { return }
        overlayLayer.bounds = CGRect(origin: .zero, size: overlaySize)
        let transform = CGAffineTransform(scaleX: 1 / overlaySize.width, y: 1 / overlaySize.height)
            .concatenating(frame.displayTransform(for: .portrait, viewportSize: bounds.size))
            .concatenating(CGAffineTransform(scaleX: bounds.width, y: bounds.height))
        overlayLayer.setAffineTransform(transform)
    }
}
