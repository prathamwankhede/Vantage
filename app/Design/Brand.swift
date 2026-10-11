import SwiftUI

/// Vantage visual identity — deep ink + cool teal + warm off-white.
enum Brand {
    static let ink = Color(red: 0.06, green: 0.10, blue: 0.14)          // #0F1A24
    static let inkElevated = Color(red: 0.10, green: 0.16, blue: 0.22)   // #1A2938
    static let teal = Color(red: 0.20, green: 0.78, blue: 0.72)          // #33C7B8
    static let tealDeep = Color(red: 0.12, green: 0.55, blue: 0.52)      // #1F8C85
    static let cream = Color(red: 0.96, green: 0.95, blue: 0.92)         // #F5F2EB
    static let creamMuted = Color(red: 0.96, green: 0.95, blue: 0.92).opacity(0.72)
    static let danger = Color(red: 0.95, green: 0.35, blue: 0.32)
    static let clear = Color(red: 0.35, green: 0.82, blue: 0.55)

    static let tagline = "Know what’s ahead. Move with confidence."
    static let wakeWord = "Vantage"
    /// "Vantage" plus how speech recognition often mishears it ("advantage" matches as a substring).
    static let wakePhrases = ["vantage", "van tage", "vintage", "ventage", "vontage", "fantage"]

    static var titleFont: Font { .system(size: 56, weight: .heavy, design: .rounded) }
    static var taglineFont: Font { .system(size: 20, weight: .semibold, design: .rounded) }
    static var bodyFont: Font { .system(size: 17, weight: .medium, design: .rounded) }
    static var statusFont: Font { .system(size: 15, weight: .semibold, design: .rounded) }
    static var digitFont: Font { .system(size: 34, weight: .heavy, design: .rounded).monospacedDigit() }
}
