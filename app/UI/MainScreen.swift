import AVFoundation
import Speech
import SwiftUI
import UIKit

/// Feature switches. Navigate is hidden while the team focuses on Freeroam — its screens and
/// engine code stay in place so it can be rebuilt on top of Freeroam; flip this to bring it back.
enum Features {
    static let navigate = false
}

/// Where the mode screen can send you.
enum VantageRoute: Hashable {
    case freeroam
    case destination
    case navigate(goal: String)
}

/// First screen. Speaks as soon as it appears and listens for a mode; the two halves of the
/// screen are also big tap targets, so it works by voice, by touch, or with VoiceOver.
struct MainScreen: View {
    @State private var path: [VantageRoute] = []
    @State private var listening = false
    @State private var hasGreeted = false
    @State private var remindedThisVisit = false
    @State private var voiceTask: Task<Void, Never>?
    @State private var gemmaStatus = GemmaClient.status.label
    @State private var showSettings = false
    @State private var pouring: VantageRoute?
    @StateObject private var voice = VoiceCommandBridge()

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                menu
                    .navigationDestination(for: VantageRoute.self) { route in
                        switch route {
                        case .freeroam:
                            SessionScreen(mode: .freeroam, goal: "")
                        case .destination:
                            DestinationScreen { goal in pour(to: .navigate(goal: goal)) }
                        case .navigate(let goal):
                            SessionScreen(mode: .navigate, goal: goal)
                        }
                    }
            }
            if pouring != nil {
                TealWaterPour {
                    if let route = pouring {
                        path.append(route)
                        pouring = nil
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }

    private var menu: some View {
        VStack(spacing: 14) {
            header
            ListeningIndicator(
                listening: listening,
                text: listening ? listenHint : "Vantage is speaking"
            )
            ModeCard(
                title: "Freeroam",
                subtitle: Features.navigate
                    ? "Walk freely. Vibrations warn you about obstacles."
                    : "Walk freely. Vibrations warn you about obstacles. Tap anywhere here to start.",
                systemImage: "figure.walk",
                fill: Brand.teal
            ) {
                choose(.freeroam)
            }
            if Features.navigate {
                ModeCard(
                    title: "Navigate",
                    subtitle: "Tell me where to go. I'll guide you using the camera.",
                    systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                    fill: Brand.cream
                ) {
                    choose(.destination)
                }
            }
            Text(gemmaStatus)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Brand.creamMuted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Brand.ink.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            NavigationStack { DetectionSettingsScreen() }
                .preferredColorScheme(.dark)
        }
        .onAppear(perform: greet)
        .onDisappear(perform: stopVoice)
        .onReceive(NotificationCenter.default.publisher(for: GemmaClient.statusChanged)) { _ in
            gemmaStatus = GemmaClient.status.label
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vantage")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Brand.cream)
                Text(Brand.tagline)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.creamMuted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Brand.cream)
                    .frame(width: 52, height: 52)
                    .background(Brand.inkElevated, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Voice

    private var listenHint: String {
        Features.navigate ? "Say “Freeroam” or “Navigate”" : "Say “Start” or tap the screen"
    }

    private var welcomeLine: String {
        Features.navigate
            ? "Welcome to Vantage. Say Freeroam to walk with vibration warnings, or Navigate to be guided "
                + "somewhere. You can also tap the top or bottom half of the screen."
            : "Welcome to Vantage. Say Start, or tap anywhere on the screen, to begin Freeroam. "
                + "Vibrations will warn you about obstacles."
    }

    private var menuLine: String {
        Features.navigate ? "Main menu. Say Freeroam, or Navigate." : "Main menu. Say Start, or tap the screen, to begin."
    }

    private var promptLine: String {
        Features.navigate ? "Say Freeroam, or Navigate." : "Say Start, or tap the screen."
    }

    private func greet() {
        #if DEBUG
        if !hasGreeted, let route = DebugLaunch.route {
            hasGreeted = true
            path = [route]
            return
        }
        #endif
        remindedThisVisit = false
        let line = hasGreeted ? menuLine : welcomeLine
        hasGreeted = true
        voiceTask?.cancel()
        voiceTask = Task { @MainActor in
            await VoicePermissions.request()
            await speakThenListen(line)
        }
    }

    private func speakThenListen(_ line: String) async {
        voice.stop()
        listening = false
        // Before speaking: the default audio session obeys the silent switch, so the greeting was muted.
        try? Speaker.configureAudioSession()
        Speaker.shared.say(line, interrupt: true)
        await Speaker.shared.waitUntilIdle(timeout: 25)
        guard !Task.isCancelled else { return }
        listening = true
        voice.start { text in handle(text) }
        scheduleReminder()
    }

    /// One short reminder if nothing is chosen for a while.
    private func scheduleReminder() {
        guard !remindedThisVisit else { return }
        remindedThisVisit = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard path.isEmpty, listening else { return }
            voiceTask?.cancel()
            voiceTask = Task { @MainActor in await speakThenListen(promptLine) }
        }
    }

    private func handle(_ text: String) {
        guard path.isEmpty else { return }
        let intent = VoiceIntent.mode(from: text)
        if !Features.navigate {
            if intent == .freeroam || VoiceIntent.isStart(text) {
                choose(.freeroam)
                return
            }
            let line = intent != nil
                ? "Navigate isn't available right now. Say Start to begin Freeroam."
                : "Sorry, I didn't catch that. \(promptLine)"
            voiceTask?.cancel()
            voiceTask = Task { @MainActor in await speakThenListen(line) }
            return
        }
        switch intent {
        case .freeroam:
            choose(.freeroam)
        case .navigate(let goal?):
            choose(.navigate(goal: goal))
        case .navigate(nil):
            choose(.destination)
        case nil:
            voiceTask?.cancel()
            voiceTask = Task { @MainActor in
                await speakThenListen("Sorry, I didn't catch that. \(promptLine)")
            }
        }
    }

    private func choose(_ route: VantageRoute) {
        pour(to: route)
    }

    private func pour(to route: VantageRoute) {
        guard pouring == nil else { return }
        stopVoice()
        Speaker.shared.stop()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeIn(duration: 0.15)) { pouring = route }
    }

    private func stopVoice() {
        voiceTask?.cancel()
        voiceTask = nil
        voice.stop()
        listening = false
    }
}

// MARK: - Mode card

/// Half-screen button: one per mode, so either half of the screen is an easy target.
private struct ModeCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    TealRipple()
                        .frame(width: 72, height: 72)
                        .opacity(0.4)
                    Image(systemName: systemImage)
                        .font(.system(size: 32, weight: .bold))
                        .frame(width: 64, height: 64)
                        .background(Brand.ink.opacity(0.1), in: Circle())
                }
                Spacer(minLength: 8)
                Text(title)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .opacity(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Brand.ink)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Destination

/// Asks "where to?" out loud and listens; suggestions and typing are there as backups.
struct DestinationScreen: View {
    var onGoal: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var listening = false
    @State private var voiceTask: Task<Void, Never>?
    @StateObject private var voice = VoiceCommandBridge()

    private let suggestions = ["the exit", "the front desk", "the elevator", "the restroom", "the stairs"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Brand.cream)
                    .frame(width: 52, height: 52)
                    .background(Brand.inkElevated, in: Circle())
            }
            .accessibilityLabel("Back to main menu")

            Text("Where to?")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Brand.cream)
                .accessibilityAddTraits(.isHeader)

            ListeningIndicator(
                listening: listening,
                text: listening ? "Say a place, like “the front desk”" : "Vantage is speaking"
            )

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(suggestions, id: \.self) { place in
                        Button {
                            go(place)
                        } label: {
                            HStack {
                                Text(place.prefix(1).uppercased() + place.dropFirst())
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .foregroundStyle(Brand.cream)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(Brand.inkElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("Navigate to \(place)")
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                TextField("Or type a place", text: $typed)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.cream)
                    .padding(.horizontal, 18)
                    .frame(height: 60)
                    .background(Brand.inkElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .submitLabel(.go)
                    .onSubmit { go(typed) }
                Button {
                    go(typed)
                } label: {
                    Text("Go")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.ink)
                        .frame(width: 76, height: 60)
                        .background(Brand.teal, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Start navigating")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Brand.ink.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            voiceTask = Task { @MainActor in
                await speakThenListen("Where do you want to go? For example, the front desk, or the exit.")
            }
        }
        .onDisappear(perform: stopVoice)
    }

    private func speakThenListen(_ line: String) async {
        voice.stop()
        listening = false
        try? Speaker.configureAudioSession()
        Speaker.shared.say(line, interrupt: true)
        await Speaker.shared.waitUntilIdle(timeout: 15)
        guard !Task.isCancelled else { return }
        listening = true
        voice.start { text in handle(text) }
    }

    private func handle(_ text: String) {
        if VoiceIntent.isCancel(text) {
            stopVoice()
            dismiss()
            return
        }
        if let goal = VoiceIntent.destination(in: text) {
            go(goal)
        }
    }

    private func go(_ place: String) {
        let goal = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return }
        stopVoice()
        Speaker.shared.stop()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onGoal(goal)
    }

    private func stopVoice() {
        voiceTask?.cancel()
        voiceTask = nil
        voice.stop()
        listening = false
    }
}

// MARK: - Voice helpers

/// Listens without needing the wake word — for menus where Vantage just asked a question.
@MainActor
final class VoiceCommandBridge: ObservableObject {
    private let listener = AlwaysListener()

    func start(onUtterance: @escaping (String) -> Void) {
        listener.onUtterance = onUtterance
        listener.start()
    }

    func stop() {
        listener.onUtterance = nil
        listener.stop()
    }
}

/// Mic and speech permission up front, so the very first voice menu can hear the answer.
enum VoicePermissions {
    @MainActor
    static func request() async {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        }
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
    }
}

/// Turns menu speech into a choice.
enum VoiceIntent {
    enum Mode: Equatable {
        case freeroam
        case navigate(goal: String?)
    }

    private static let destinationLeads = [
        "i want to go to", "i need to go to", "navigate me to", "navigate to", "take me to",
        "guide me to", "bring me to", "go to", "find the", "find"
    ]

    static func mode(from text: String) -> Mode? {
        let lower = normalized(text)
        // "Navigate to the front desk" → straight into Navigate.
        for lead in destinationLeads where !lead.hasPrefix("find") {
            if let range = lower.range(of: lead + " ") {
                let goal = cleanGoal(String(lower[range.upperBound...]))
                if !goal.isEmpty { return .navigate(goal: goal) }
            }
        }
        if ["free roam", "freeroam", "free room", "free rome", "roam", "walk"].contains(where: lower.contains) {
            return .freeroam
        }
        if ["navigate", "navigation", "guide", "take me", "directions", "destination"].contains(where: lower.contains) {
            return .navigate(goal: nil)
        }
        return nil
    }

    /// The place in "take me to the front desk", or the whole phrase if there's no lead-in.
    static func destination(in text: String) -> String? {
        var lower = normalized(text)
        if let lead = destinationLeads.first(where: { lower.hasPrefix($0 + " ") }) {
            lower = String(lower.dropFirst(lead.count))
        }
        let goal = cleanGoal(lower)
        return goal.isEmpty ? nil : goal
    }

    /// "Start", "begin", "ready", "let's go" — used when Freeroam is the only mode.
    static func isStart(_ text: String) -> Bool {
        let lower = normalized(text)
        return lower == "go" || lower == "yes"
            || ["start", "begin", "ready", "let's go", "lets go"].contains(where: lower.contains)
    }

    static func isCancel(_ text: String) -> Bool {
        let lower = normalized(text)
        return lower == "back" || ["cancel", "go back", "main menu", "never mind", "nevermind"]
            .contains(where: lower.hasPrefix)
    }

    private static func normalized(_ text: String) -> String {
        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var lower = text.lowercased().trimmingCharacters(in: trim)
        for wake in Brand.wakePhrases where lower.hasPrefix(wake) {
            lower = String(lower.dropFirst(wake.count)).trimmingCharacters(in: trim)
        }
        return lower
    }

    private static func cleanGoal(_ text: String) -> String {
        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var goal = text.trimmingCharacters(in: trim)
        for tail in [" please", " now"] where goal.hasSuffix(tail) {
            goal = String(goal.dropLast(tail.count))
        }
        return goal.trimmingCharacters(in: trim)
    }
}

#if DEBUG
/// Launch arguments for checking screens in the Simulator without tapping through:
/// `-UITestRoute freeroam|destination|navigate` and `-UITestGlow listening|thinking`.
enum DebugLaunch {
    static var route: VantageRoute? {
        switch value(after: "-UITestRoute") {
        case "freeroam": return .freeroam
        case "destination" where Features.navigate: return .destination
        case "navigate" where Features.navigate: return .navigate(goal: "the front desk")
        default: return nil
        }
    }

    static var glow: FreeroamEngine.ListenState? {
        switch value(after: "-UITestGlow") {
        case "listening": return .listening
        case "thinking": return .thinking
        default: return nil
        }
    }

    private static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}
#endif
