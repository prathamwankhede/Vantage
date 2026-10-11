import SwiftUI

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
