import SwiftUI

struct LoadingScreen: View {
    @State private var glow = false

    var body: some View {
        ZStack {
            Brand.ink.ignoresSafeArea()
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Brand.teal.opacity(glow ? 0.35 : 0.12))
                        .frame(width: 160, height: 160)
                        .blur(radius: 24)
                    Text("V")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundStyle(Brand.cream)
                }
                Text("Vantage")
                    .font(Brand.titleFont)
                    .foregroundStyle(Brand.cream)
                ProgressView()
                    .tint(Brand.teal)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vantage loading")
    }
}
