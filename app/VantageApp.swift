import SwiftUI

@main
struct VantageApp: App {
    @State private var phase: AppPhase = .loading

    var body: some Scene {
        WindowGroup {
            Group {
                switch phase {
                case .loading:
                    LoadingScreen()
                        .task {
                            try? await Task.sleep(nanoseconds: 1_100_000_000)
                            withAnimation(.easeInOut(duration: 0.35)) { phase = .home }
                        }
                case .home:
                    HomeScreen {
                        withAnimation(.easeInOut(duration: 0.3)) { phase = .main }
                    }
                case .main:
                    NavigationStack {
                        MainScreen {
                            withAnimation(.easeInOut(duration: 0.3)) { phase = .home }
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

private enum AppPhase {
    case loading, home, main
}
