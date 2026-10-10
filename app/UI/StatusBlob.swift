import SwiftUI

struct StatusBlob: View {
    let title: String
    let detail: String
    var accent: Color = Brand.teal

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(Brand.digitFont)
                .foregroundStyle(Brand.cream)
            Text(detail)
                .font(Brand.statusFont)
                .foregroundStyle(Brand.creamMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(accent.opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        )
        .accessibilityElement(children: .combine)
    }
}
