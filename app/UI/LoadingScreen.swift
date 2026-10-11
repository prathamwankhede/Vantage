import SwiftUI

struct LoadingScreen: View {
    @State private var glow = false
    @State private var rise = false

    var body: some View {
        ZStack {
            Brand.ink.ignoresSafeArea()
            RadialGradient(
                colors: [Brand.teal.opacity(glow ? 0.4 : 0.12), Brand.ink.opacity(0)],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .ignoresSafeArea()
            VStack(spacing: 28) {
                ZStack {
                    TealRipple()
                        .frame(width: 140, height: 140)
                    Circle()
                        .fill(Brand.teal.opacity(glow ? 0.35 : 0.12))
                        .frame(width: 160, height: 160)
                        .blur(radius: 24)
                    Text("V")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundStyle(Brand.cream)
                }
                .offset(y: rise ? 0 : 28)
                .opacity(rise ? 1 : 0)
                Text("Vantage")
                    .font(Brand.titleFont)
                    .foregroundStyle(Brand.cream)
                    .offset(y: rise ? 0 : 16)
                    .opacity(rise ? 1 : 0)
                ProgressView()
                    .tint(Brand.teal)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.85, bounce: 0.18)) { rise = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vantage loading")
    }
}
