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
            CameraPreview(session: engine.session)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            if mode == .freeroam, settings.nightVision, let cg = engine.nightVisionImage {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .opacity(0.85)
                    .accessibilityHidden(true)
            }

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

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        view.rendersCameraGrain = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
