import SwiftUI

/// Siri-style glow around the screen edges: bright while Vantage is listening after the wake
/// word, softer and pulsing while it works out an answer, gone when idle.
struct ListeningGlow: View {
    let state: FreeroamEngine.ListenState

    /// Close to the rounded display corners of current iPhones.
    private let cornerRadius: CGFloat = 55
    private let colors: [Color] = [
        Brand.teal,
        Color(red: 0.25, green: 0.52, blue: 1.0),
        Color(red: 0.62, green: 0.36, blue: 1.0),
        Color(red: 1.0, green: 0.36, blue: 0.62),
        Color(red: 1.0, green: 0.62, blue: 0.26),
        Brand.teal
    ]

    var body: some View {
        TimelineView(.animation(paused: state == .idle)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let gradient = AngularGradient(
                colors: colors,
                center: .center,
                angle: .degrees(time.truncatingRemainder(dividingBy: 4) / 4 * 360)
            )
            let pulse = state == .thinking ? 0.55 + 0.25 * sin(time * 4) : 1
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            ZStack {
                shape.strokeBorder(gradient, lineWidth: 26).blur(radius: 28)
                shape.strokeBorder(gradient, lineWidth: 10).blur(radius: 8)
                shape.strokeBorder(gradient, lineWidth: 3)
            }
            .opacity(pulse)
        }
        .opacity(state == .idle ? 0 : 1)
        .animation(.easeInOut(duration: 0.35), value: state)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
