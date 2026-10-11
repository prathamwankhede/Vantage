import Foundation
import SwiftUI

enum AlertMode: String, CaseIterable, Identifiable {
    case universal, indoor, outdoor, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .universal: return "Universal"
        case .indoor: return "Indoor"
        case .outdoor: return "Outdoor"
        case .custom: return "Custom"
        }
    }

    /// Max detection distance in metres (White Cane presets).
    func maxDistanceMeters(custom: Float) -> Float {
        switch self {
        case .universal: return 2.0
        case .indoor: return 1.5
        case .outdoor: return 2.5
        case .custom: return custom
        }
    }

    func feetLabel(custom: Float) -> String {
        String(format: "%.2f ft", Double(maxDistanceMeters(custom: custom)) * 3.28084)
    }
}

/// Haptic patterns mirroring White Cane near/medium/far sound slots.
enum HapticPattern: String, CaseIterable, Identifiable {
    case tapSharp, tap, beep, toot, tootSharp, mute
    var id: String { rawValue }

    var title: String {
        switch self {
        case .tapSharp: return "Tap (Sharp)"
        case .tap: return "Tap"
        case .beep: return "Beep"
        case .toot: return "Toot"
        case .tootSharp: return "Toot (Sharp)"
        case .mute: return "Mute"
        }
    }
}

enum DistanceBand: String, CaseIterable {
    case near, medium, far
}

/// Walking detection prefs — White Cane–style alert modes and per-range haptic patterns.
@MainActor
final class DetectionSettings: ObservableObject {
    static let shared = DetectionSettings()

    @Published var alertMode: AlertMode {
        didSet { UserDefaults.standard.set(alertMode.rawValue, forKey: Keys.alertMode) }
    }
    @Published var customMaxMeters: Float {
        didSet { UserDefaults.standard.set(customMaxMeters, forKey: Keys.customMax) }
    }
    @Published var nearPattern: HapticPattern {
        didSet { UserDefaults.standard.set(nearPattern.rawValue, forKey: Keys.near) }
    }
    @Published var mediumPattern: HapticPattern {
        didSet { UserDefaults.standard.set(mediumPattern.rawValue, forKey: Keys.medium) }
    }
    @Published var farPattern: HapticPattern {
        didSet { UserDefaults.standard.set(farPattern.rawValue, forKey: Keys.far) }
    }
    @Published var continuousCloseVibration: Bool {
        didSet { UserDefaults.standard.set(continuousCloseVibration, forKey: Keys.continuous) }
    }
    @Published var speechFeedback: Bool {
        didSet { UserDefaults.standard.set(speechFeedback, forKey: Keys.speech) }
    }
    @Published var nightVision: Bool {
        didSet { UserDefaults.standard.set(nightVision, forKey: Keys.nightVision) }
    }
    /// Color rainbow vs 3D Spatial shading. Overlay stays in lit rooms; full-frame only when dark.
    @Published var nightVisionMode: NightVisionMode {
        didSet { UserDefaults.standard.set(nightVisionMode.rawValue, forKey: Keys.nightVisionMode) }
    }
    @Published var quickResponse: Bool {
        didSet { UserDefaults.standard.set(quickResponse, forKey: Keys.quick) }
    }

    var maxDistance: Float { alertMode.maxDistanceMeters(custom: customMaxMeters) }

    func pattern(for band: DistanceBand) -> HapticPattern {
        switch band {
        case .near: return nearPattern
        case .medium: return mediumPattern
        case .far: return farPattern
        }
    }

    private enum Keys {
        static let alertMode = "vantage.alertMode"
        static let customMax = "vantage.customMax"
        static let near = "vantage.haptic.near"
        static let medium = "vantage.haptic.medium"
        static let far = "vantage.haptic.far"
        static let continuous = "vantage.haptic.continuous"
        static let speech = "vantage.speechFeedback"
        static let nightVision = "vantage.nightVision"
        static let nightVisionMode = "vantage.nightVisionMode"
        static let quick = "vantage.quickResponse"
    }

    private init() {
        let d = UserDefaults.standard
        alertMode = AlertMode(rawValue: d.string(forKey: Keys.alertMode) ?? "") ?? .indoor
        customMaxMeters = (d.object(forKey: Keys.customMax) as? Float) ?? 2.5
        nearPattern = HapticPattern(rawValue: d.string(forKey: Keys.near) ?? "") ?? .tootSharp
        mediumPattern = HapticPattern(rawValue: d.string(forKey: Keys.medium) ?? "") ?? .toot
        farPattern = HapticPattern(rawValue: d.string(forKey: Keys.far) ?? "") ?? .tap
        continuousCloseVibration = d.object(forKey: Keys.continuous) as? Bool ?? true
        speechFeedback = d.object(forKey: Keys.speech) as? Bool ?? false
        nightVision = d.object(forKey: Keys.nightVision) as? Bool ?? false
        nightVisionMode = NightVisionMode(rawValue: d.string(forKey: Keys.nightVisionMode) ?? "") ?? .color
        quickResponse = d.object(forKey: Keys.quick) as? Bool ?? true
    }
}
