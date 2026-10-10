import SwiftUI

/// Soft edge glow mirroring the ear the spatial tone is in.
struct EdgeWash: View {
    let side: Zone?
    let strength: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let side, strength > 0.05 {
                    LinearGradient(
                        colors: washColors(for: side),
                        startPoint: start(for: side),
                        endPoint: end(for: side)
                    )
                    .opacity(0.25 + 0.45 * strength)
                    .frame(width: geo.size.width * 0.42)
                    .frame(maxWidth: .infinity, alignment: alignment(for: side))
                    .blur(radius: 28)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func washColors(for side: Zone) -> [Color] {
        switch side {
        case .left: return [Brand.teal, .clear]
        case .right: return [.clear, Brand.teal]
        case .center: return [.clear, Brand.danger.opacity(0.9), .clear]
        }
    }

    private func start(for side: Zone) -> UnitPoint {
        side == .right ? .leading : .trailing
    }

    private func end(for side: Zone) -> UnitPoint {
        side == .right ? .trailing : .leading
    }

    private func alignment(for side: Zone) -> Alignment {
        switch side {
        case .left: return .leading
        case .right: return .trailing
        case .center: return .center
        }
    }
}
