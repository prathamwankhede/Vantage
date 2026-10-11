import Foundation

/// What the phone measured at the moment of a question, written out for Gemini / Gemma so the
/// model reports sensor readings instead of guessing distances and motion from the photo.
struct SceneContext {
    struct Nearest {
        let zone: Zone
        let distance: Float
        let name: String?
    }

    var mode: FreeroamEngine.Mode
    var goal: String?
    var lastStep: String?
    var usesLiDAR: Bool
    /// Smoothed nearest distance at chest height, (left, center, right) in metres.
    var zoneDistances: SIMD3<Float>
    /// LiDAR only: nearest per cell, rows top→bottom, columns left→right.
    var depthGrid: [[Float?]]?
    var nearest: Nearest?
    var isMoving: Bool
    var speed: Float?
    /// Positive = camera tilted up.
    var cameraPitchDegrees: Float?
    var tracking: String
    var ambientIntensity: Float?
    var labels: [String]
    var headphones: String
    var date = Date()
    /// Room structure from the LiDAR scene mesh (Navigate), e.g. detected doors.
    var structure: String? = nil

    /// Anything at or beyond this is reported as "nothing within".
    static let maxRange: Float = 5

    var promptText: String {
        var lines: [String] = []

        let sensor = usesLiDAR ? "LiDAR (accurate to a few cm)" : "camera-only estimate (rough, no LiDAR)"
        let zones = Zone.allCases.map { zone in
            "\(Self.zoneWord(zone)) \(Self.distance(zoneDistances[zone.rawValue]))"
        }
        lines.append("- Depth sensor: \(sensor). Nearest at chest height: \(zones.joined(separator: ", ")).")

        if let depthGrid {
            let rowNames = ["top", "middle", "bottom"]
            let rows = depthGrid.enumerated().map { index, row in
                let name = index < rowNames.count ? rowNames[index] : "row \(index + 1)"
                let cells = row.map { $0.map { String(format: "%.1f", $0) } ?? "-" }
                return "\(name) \(cells.joined(separator: " "))"
            }
            lines.append("- Depth grid in metres (columns left/center/right; \"-\" = nothing within \(Int(Self.maxRange)) m; "
                + "the bottom row usually sees the floor): \(rows.joined(separator: " | ")).")
        }

        if let nearest {
            let what = nearest.name.map { $0.lowercased() } ?? "obstacle"
            lines.append("- Closest: \(what) \(Self.zoneWord(nearest.zone)), \(Self.distance(nearest.distance)).")
        } else {
            lines.append("- Closest: nothing within \(Int(Self.maxRange)) m at chest height.")
        }

        var wearer = isMoving ? "walking" : "standing still"
        if isMoving, let speed { wearer += String(format: " at about %.1f m/s", speed) }
        if let cameraPitchDegrees {
            let tilt = Int(abs(cameraPitchDegrees).rounded())
            wearer += tilt < 5 ? ", camera level" : ", camera tilted \(tilt)° \(cameraPitchDegrees < 0 ? "down" : "up")"
        }
        lines.append("- Wearer: \(wearer). Phone is worn on the chest facing forward.")

        lines.append("- On-device object labels: \(labels.isEmpty ? "none" : labels.joined(separator: ", ")).")

        var conditions = "Tracking \(tracking)"
        if let ambientIntensity { conditions += ", light \(Self.lightWord(ambientIntensity))" }
        conditions += ", audio: \(headphones)"
        lines.append("- Conditions: \(conditions).")

        switch mode {
        case .freeroam:
            lines.append("- Mode: Freeroam (walking freely, no destination).")
        case .navigate:
            var line = "- Mode: Navigate to \"\(goal ?? "unknown")\""
            if let lastStep, !lastStep.isEmpty { line += "; last step given: \"\(lastStep)\"" }
            lines.append(line + ".")
        }

        let time = date.formatted(date: .omitted, time: .shortened)
        lines.append("- Local time: \(time).")
        if let structure { lines.append("- \(structure).") }

        return lines.joined(separator: "\n")
    }

    private static func zoneWord(_ zone: Zone) -> String {
        switch zone {
        case .left: return "left"
        case .center: return "ahead"
        case .right: return "right"
        }
    }

    private static func distance(_ metres: Float) -> String {
        guard metres < maxRange * 0.99 else { return "nothing within \(Int(maxRange)) m" }
        let feet = Int((metres * 3.28084).rounded())
        return String(format: "%.1f m (%d ft)", metres, feet)
    }

    /// ARKit ambient intensity: ~1000 is a lit room.
    private static func lightWord(_ intensity: Float) -> String {
        switch intensity {
        case ..<150: return "very dark"
        case ..<450: return "dim"
        case ..<1600: return "normal"
        default: return "bright"
        }
    }
}
