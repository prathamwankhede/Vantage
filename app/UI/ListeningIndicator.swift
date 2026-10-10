import SwiftUI

/// Pill showing whether Vantage is talking or listening, with the words it's waiting for.
struct ListeningIndicator: View {
    var listening: Bool
    var text: String

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: listening ? "mic.fill" : "speaker.wave.2.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Brand.ink)
                .frame(width: 34, height: 34)
                .background(Brand.teal, in: Circle())
                .scaleEffect(listening && pulse ? 1.12 : 1)
            Text(text)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.cream)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(Brand.inkElevated, in: Capsule())
        .overlay(Capsule().stroke(Brand.teal.opacity(listening ? 0.6 : 0.2), lineWidth: 1.5))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(listening ? "Listening. \(text)" : text)
    }
}
