import SwiftUI

struct ListeningIndicator: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Brand.teal)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.25 : 0.85)
            Text("Listening")
                .font(Brand.statusFont)
                .foregroundStyle(Brand.cream)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
        .overlay(Capsule().stroke(Brand.cream.opacity(0.25), lineWidth: 1))
        .padding(.bottom, 28)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel("Listening")
    }
}
