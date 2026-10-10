import SwiftUI

struct MainScreen: View {
    var onBack: () -> Void

    @State private var showFreeroam = false
    @State private var showNavigate = false
    @State private var showGoalSheet = false
    @State private var goalText = "the exit"
    @State private var appeared = false
    @State private var gemmaStatus = GemmaClient.status.label
    @StateObject private var listener = ModeVoiceBridge()

    var body: some View {
        ZStack {
            Brand.inkElevated.ignoresSafeArea()
            RadialGradient(
                colors: [Brand.teal.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Brand.cream)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("How can Vantage help?")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Brand.cream)
                    Text("Freeroam watches the path. Navigate talks you through a place using what the camera sees — no map.")
                        .font(Brand.bodyFont)
                        .foregroundStyle(Brand.creamMuted)
                }

                Spacer(minLength: 12)

                modeCard(
                    title: "Freeroam",
                    subtitle: "Calm path awareness",
                    systemImage: "waveform.path.ecg"
                ) {
                    showFreeroam = true
                }
                .offset(y: appeared ? 0 : 40)
                .opacity(appeared ? 1 : 0)

                modeCard(
                    title: "Navigate",
                    subtitle: "Landmark steps to a goal",
                    systemImage: "eye.trianglebadge.exclamationmark"
                ) {
                    showGoalSheet = true
                }
                .offset(y: appeared ? 0 : 56)
                .opacity(appeared ? 1 : 0)

                Spacer()

                Text(gemmaStatus)
                    .font(Brand.statusFont)
                    .foregroundStyle(Brand.creamMuted)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .navigationDestination(isPresented: $showFreeroam) {
            SessionScreen(mode: .freeroam, goal: "")
        }
        .navigationDestination(isPresented: $showNavigate) {
            SessionScreen(mode: .navigate, goal: goalText)
        }
        .sheet(isPresented: $showGoalSheet) {
            NavigateGoalSheet(goal: $goalText) {
                showGoalSheet = false
                showNavigate = true
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            withAnimation(.spring(duration: 0.85, bounce: 0.2).delay(0.05)) { appeared = true }
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                Speaker.shared.say(
                    "Are you freeroaming, or do you want to navigate somewhere?",
                    interrupt: true
                )
                await Speaker.shared.waitUntilIdle()
                await listener.listen(
                    onFreeroam: { showFreeroam = true },
                    onNavigate: { showGoalSheet = true }
                )
            }
        }
        .onDisappear {
            listener.stop()
            if !showFreeroam, !showNavigate { Speaker.shared.stop() }
        }
        .navigationBarBackButtonHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: GemmaClient.statusChanged)) { _ in
            gemmaStatus = GemmaClient.status.label
        }
    }

    private func modeCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Brand.ink)
                    .frame(width: 56, height: 56)
                    .background(Brand.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.cream)
                    Text(subtitle)
                        .font(Brand.statusFont)
                        .foregroundStyle(Brand.creamMuted)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(Brand.teal)
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Brand.ink)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Brand.teal.opacity(0.35), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct NavigateGoalSheet: View {
    @Binding var goal: String
    var onStart: () -> Void

    private let suggestions = ["the exit", "the front desk", "the elevator", "the pharmacy", "room 214"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Where are you going?")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                TextField("Destination", text: $goal)
                    .textFieldStyle(.roundedBorder)
                    .font(Brand.bodyFont)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(suggestions, id: \.self) { item in
                            Button(item) { goal = item }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                Button(action: onStart) {
                    Text("Start Navigate")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.tealDeep)
                Spacer()
            }
            .padding(24)
            .navigationTitle("Navigate")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@MainActor
private final class ModeVoiceBridge: ObservableObject {
    private let listener = AlwaysListener()

    func listen(onFreeroam: @escaping () -> Void, onNavigate: @escaping () -> Void) async {
        listener.onUtterance = { text in
            let lower = text.lowercased()
            if ["freeroam", "free roam", "roam", "watch"].contains(where: { lower.contains($0) }) {
                onFreeroam()
            } else if ["navigate", "navigation", "go to", "find the way", "guide"].contains(where: { lower.contains($0) }) {
                onNavigate()
            }
        }
        listener.start()
    }

    func stop() { listener.stop() }
}
