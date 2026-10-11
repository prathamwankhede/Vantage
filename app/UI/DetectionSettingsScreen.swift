import SwiftUI

/// White Cane–style detection / haptic settings + Night Vision toggle.
struct DetectionSettingsScreen: View {
    @ObservedObject private var settings = DetectionSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text("Obstacles beyond this distance will not trigger haptics.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(AlertMode.allCases) { mode in
                    Button {
                        settings.alertMode = mode
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .foregroundStyle(Brand.cream)
                                Text(mode.feetLabel(custom: settings.customMaxMeters))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.alertMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Brand.teal)
                            }
                        }
                    }
                }
                if settings.alertMode == .custom {
                    HStack {
                        Text("Custom max")
                        Slider(value: Binding(
                            get: { Double(settings.customMaxMeters) },
                            set: { settings.customMaxMeters = Float($0) }
                        ), in: 1...5, step: 0.1)
                        Text(String(format: "%.1fm", settings.customMaxMeters))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Alert Mode")
            }

            Section("Haptic Patterns") {
                patternPicker("Near Range", selection: $settings.nearPattern)
                patternPicker("Medium Range", selection: $settings.mediumPattern)
                patternPicker("Far Range", selection: $settings.farPattern)
            }

            Section("Obstacle Detection") {
                Toggle("Haptics", isOn: .constant(true))
                    .disabled(true)
                Toggle("Continuous Vibration at Close Range", isOn: $settings.continuousCloseVibration)
                Toggle("Speech Feedback", isOn: $settings.speechFeedback)
                Toggle("Quick Response", isOn: $settings.quickResponse)
            }

            Section("Night Vision") {
                Toggle("LiDAR Night Vision", isOn: $settings.nightVision)
                if settings.nightVision {
                    Picker("Imaging", selection: $settings.nightVisionMode) {
                        ForEach(NightVisionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.nightVisionMode.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Overlay on the camera when there’s light. In a dark room it switches to full night vision automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.ink.ignoresSafeArea())
        .navigationTitle("Detection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(Brand.teal)
            }
        }
    }

    private func patternPicker(_ title: String, selection: Binding<HapticPattern>) -> some View {
        Picker(title, selection: selection) {
            ForEach(HapticPattern.allCases) { pattern in
                Text(pattern.title).tag(pattern)
            }
        }
        .foregroundStyle(Brand.cream)
    }
}
