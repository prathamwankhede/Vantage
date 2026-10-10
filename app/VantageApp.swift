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
                            GemmaClient.preload()
                            #if DEBUG
                            GemmaSelfTest.runIfRequested()
                            #endif
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            withAnimation(.easeInOut(duration: 0.3)) { phase = .main }
                        }
                case .main:
                    // Straight to the talking mode menu — no "continue" step in between.
                    MainScreen()
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

private enum AppPhase {
    case loading, main
}
