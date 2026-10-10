import SwiftUI

struct HomeScreen: View {
    var onContinue: () -> Void

    @State private var risen = false
    @State private var listening = false
    @StateObject private var listener = HomeVoiceBridge()

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer(minLength: 80)
                brandBlock
                    .offset(y: risen ? 0 : 36)
                    .opacity(risen ? 1 : 0)
                Spacer()
                cta
                    .offset(y: risen ? 0 : 24)
                    .opacity(risen ? 1 : 0)
                    .padding(.bottom, 48)
            }
            if listening {
                VStack {
                    Spacer()
                    ListeningIndicator()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.18)) { risen = true }
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                Speaker.shared.say(
                    "Hello, this is Vantage. Know what's ahead. Move with confidence.",
                    interrupt: true
                )
                await Speaker.shared.waitUntilIdle()
                listening = true
                await listener.listen {
                    listening = false
                    onContinue()
                }
            }
        }
        .onDisappear { listener.stop() }
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height < -80 { onContinue() }
            }
        )
    }

    private var background: some View {
        ZStack {
            Brand.ink
            RadialGradient(
                colors: [Brand.teal.opacity(0.35), Brand.ink.opacity(0)],
                center: .top,
                startRadius: 40,
                endRadius: 420
            )
            LinearGradient(
                colors: [Brand.inkElevated.opacity(0.0), Brand.tealDeep.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var brandBlock: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Brand.teal.opacity(0.55), lineWidth: 3)
                    .frame(width: 88, height: 88)
                Text("V")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Brand.teal)
            }
            Text("Vantage")
                .font(Brand.titleFont)
                .foregroundStyle(Brand.cream)
            Text(Brand.tagline)
                .font(Brand.taglineFont)
                .foregroundStyle(Brand.creamMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    private var cta: some View {
        VStack(spacing: 14) {
            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Brand.teal, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(.horizontal, 32)
            Text("Swipe up · or say continue")
                .font(Brand.statusFont)
                .foregroundStyle(Brand.creamMuted)
        }
    }
}

/// Tiny bridge so home can listen without pulling in AlwaysListener wake logic.
@MainActor
private final class HomeVoiceBridge: ObservableObject {
    private let listener = AlwaysListener()
    private var continuation: (() -> Void)?

    func listen(onContinue: @escaping () -> Void) async {
        continuation = onContinue
        listener.onUtterance = { [weak self] text in
            let lower = text.lowercased()
            if ["continue", "okay", "next", "start", "begin", "go", "yes", "ready", "vantage"]
                .contains(where: { lower.contains($0) }) {
                self?.continuation?()
                self?.stop()
            }
        }
        listener.start()
    }

    func stop() {
        listener.stop()
        continuation = nil
    }
}
