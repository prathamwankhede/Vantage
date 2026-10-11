import SwiftUI

/// Vantage-branded water pour: ink swell → teal tide that covers the screen, then runs `onCovered`.
struct TealWaterPour: View {
    var onCovered: () -> Void

    @State private var fill: CGFloat = 0
    @State private var wavePhase: CGFloat = 0
    @State private var foam = true
    @State private var haze: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            ZStack(alignment: .bottom) {
                Brand.ink.opacity(0.28 + 0.4 * haze)

                // Rising body
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack(alignment: .top) {
                        LinearGradient(
                            colors: [Brand.tealDeep, Brand.teal, Brand.teal.opacity(0.92)],
                            startPoint: .bottom,
                            endPoint: .top
                        )

                        // Soft cream foam crest that rides the surface
                        if foam {
                            WaveCrest(phase: wavePhase, amplitude: 10)
                                .fill(
                                    LinearGradient(
                                        colors: [Brand.cream.opacity(0.55), Brand.cream.opacity(0.05)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: 56)
                                .offset(y: -8)
                                .blendMode(.plusLighter)
                        }
                    }
                    .frame(height: max(0, h * fill))
                    .mask(
                        WaveCrest(phase: wavePhase, amplitude: 14)
                            .frame(width: w, height: max(1, h * fill))
                            // Invert: solid fill below the wave line
                            .background(Color.white.padding(.top, 20))
                            .compositingGroup()
                    )
                    .clipShape(Rectangle())
                }

                // Surface highlight line
                WaveCrest(phase: wavePhase + 0.4, amplitude: 12)
                    .stroke(Brand.cream.opacity(foam ? 0.35 : 0), lineWidth: 2)
                    .frame(height: 28)
                    .offset(y: -h * fill + 14)
                    .opacity(fill > 0.05 ? 1 : 0)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(true)
        .onAppear {
            withAnimation(.easeIn(duration: 0.18)) { haze = 1 }
            withAnimation(.easeInOut(duration: 0.62)) { fill = 1 }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                wavePhase = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                onCovered()
                withAnimation(.easeOut(duration: 0.22)) { foam = false }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Soft sine crest used for the pour surface.
private struct WaveCrest: Shape {
    var phase: CGFloat
    var amplitude: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.minY + amplitude + 4
        path.move(to: CGPoint(x: rect.minX, y: midY))
        let steps = max(24, Int(rect.width / 8))
        for i in 0...steps {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(steps)
            let t = CGFloat(i) / CGFloat(steps) * .pi * 2 + phase * .pi * 2
            let y = midY + sin(t) * amplitude * 0.55 + sin(t * 1.7 + 0.6) * amplitude * 0.35
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Soft teal ripple used on loading / listening presence.
struct TealRipple: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Brand.teal.opacity(0.5), lineWidth: 2)
                .scaleEffect(pulse ? 1.4 : 0.82)
                .opacity(pulse ? 0 : 0.75)
            Circle()
                .stroke(Brand.tealDeep.opacity(0.35), lineWidth: 1.5)
                .scaleEffect(pulse ? 1.15 : 0.7)
                .opacity(pulse ? 0 : 0.55)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.55).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
