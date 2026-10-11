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
                depthOverlay: mode == .freeroam && settings.nightVision ? engine.nightVisionImage : nil,
                fullFrame: mode == .freeroam && settings.nightVision && engine.nightVisionFullFrame
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                statusPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            #if DEBUG
            ListeningGlow(state: DebugLaunch.glow ?? engine.listenState)
            #else
            ListeningGlow(state: engine.listenState)
            #endif
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                DetectionSettingsScreen()
            }
            .preferredColorScheme(.dark)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            engine.onExitRequested = { dismiss() }
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

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                engine.stop()
                dismiss()
            } label: {
                Label("End", systemImage: "xmark")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.cream)
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(Brand.ink.opacity(0.85), in: Capsule())
            }
            .accessibilityLabel("End \(modeTitle) and go back to the main menu")

            Spacer()

            Text(modeTitle)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.ink)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(mode == .navigate ? Brand.cream : Brand.teal, in: Capsule())
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Brand.cream)
                    .frame(width: 52, height: 52)
                    .background(Brand.ink.opacity(0.85), in: Circle())
            }
            .accessibilityLabel("Detection settings")
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var modeTitle: String { mode == .navigate ? "Navigate" : "Freeroam" }

    // MARK: - Status panel

    /// The one status surface: distance, state, the current step, and what Vantage last said.
    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(distanceTitle)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Brand.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text(stateLabel)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(stateColor, in: Capsule())
            }

            if mode == .navigate {
                Text(engine.navTargetStatus
                    ?? (engine.navigateStepText.isEmpty ? "Looking for landmarks…" : engine.navigateStepText))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(statusDetail)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.creamMuted)
                .lineLimit(2)

            if !engine.caption.isEmpty {
                Rectangle()
                    .fill(Brand.cream.opacity(0.12))
                    .frame(height: 1)
                CaptionText(text: engine.caption)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(stateColor, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
    }

    private var distanceTitle: String {
        guard let alert = engine.alert else { return "Clear" }
        let feet = Int((alert.distance * 3.28084).rounded())
        return "\(feet) ft"
    }

    private var stateLabel: String {
        guard let alert = engine.alert else { return "Path clear" }
        let side: String
        switch alert.zone {
        case .left: side = "Left"
        case .center: side = "Ahead"
        case .right: side = "Right"
        }
        if alert.distance < AlertPolicy.stopDistance { return "Very close · \(side)" }
        return "\(alert.band.rawValue.capitalized) · \(side)"
    }

    private var stateColor: Color {
        guard let alert = engine.alert else { return Brand.clear }
        if alert.distance < AlertPolicy.stopDistance { return Brand.danger }
        switch alert.band {
        case .near: return Brand.danger
        case .medium: return Color(red: 0.98, green: 0.66, blue: 0.25)
        case .far: return Brand.teal
        }
    }

    private var statusDetail: String {
        var parts: [String] = []
        if mode == .freeroam {
            parts.append("Haptics")
            parts.append("\(settings.alertMode.title) range")
            if settings.nightVision {
                if engine.nightVisionFullFrame {
                    parts.append("Night vision · full")
                } else {
                    parts.append("Night vision · \(settings.nightVisionMode.title)")
                }
            }
        } else {
            if engine.quietMode { parts.append("Quiet") }
            parts.append(engine.headphoneStatus)
        }
        parts.append("Say “Vantage” to ask")
        return parts.joined(separator: " · ")
    }
}

/// What Vantage last said: sized to fit when short, scrolls inside a capped height when long,
/// so a long answer can't push anything off screen.
private struct CaptionText: View {
    let text: String
    private let maxHeight: CGFloat = 160

    var body: some View {
        ViewThatFits(in: .vertical) {
            label
            ScrollView {
                label
            }
            .frame(maxHeight: maxHeight)
            .scrollIndicators(.visible)
        }
        .frame(maxHeight: maxHeight)
        .id(text)
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(Brand.cream)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: ARSession
    /// Night-vision depth image in the sensor's native orientation; nil hides the overlay.
    var depthOverlay: CGImage?
    /// When true, depth fully covers the camera (dark room). Lit rooms keep the translucent overlay.
    var fullFrame: Bool = false

    func makeUIView(context: Context) -> DepthOverlayARView {
        let view = DepthOverlayARView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        view.rendersCameraGrain = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: DepthOverlayARView, context: Context) {
        uiView.setDepthOverlay(depthOverlay, fullFrame: fullFrame)
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
                                "transform": NSNull(), "hidden": NSNull(), "opacity": NSNull()]
        overlayLayer.isHidden = true
        layer.addSublayer(overlayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setDepthOverlay(_ image: CGImage?, fullFrame: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlayLayer.contents = image
        overlayLayer.isHidden = image == nil
        // Lit: soft overlay so the camera still reads. Dark: solid cover.
        overlayLayer.opacity = fullFrame ? 1 : 0.85
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
