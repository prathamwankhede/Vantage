import AVFoundation
import CoreMotion
import Foundation

/// Head yaw from AirPods when available; otherwise phone attitude as a coarse stand-in.
@MainActor
final class HeadphoneMotion: ObservableObject {
    @Published private(set) var headYaw: Float = 0
    @Published private(set) var usingHeadphones = false
    @Published private(set) var usingHeadTracking = false
    @Published private(set) var statusLine = "Connect AirPods for spatial cues"

    private let headphone = CMHeadphoneMotionManager()
    private let device = CMMotionManager()
    private var routeObserver: NSObjectProtocol?

    func start() {
        refreshRoute()
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshRoute() }
        }

        if headphone.isDeviceMotionAvailable {
            headphone.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let motion else { return }
                Task { @MainActor in
                    self?.usingHeadTracking = true
                    self?.headYaw = Float(motion.attitude.yaw)
                    self?.statusLine = "AirPods head tracking"
                }
            }
        }

        if device.isDeviceMotionAvailable {
            device.deviceMotionUpdateInterval = 1.0 / 30.0
            device.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                Task { @MainActor in
                    if !self.usingHeadTracking {
                        self.headYaw = Float(motion.attitude.yaw)
                        if self.usingHeadphones {
                            self.statusLine = "Headphones · phone attitude"
                        }
                    }
                }
            }
        }
    }

    func stop() {
        headphone.stopDeviceMotionUpdates()
        device.stopDeviceMotionUpdates()
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
    }

    /// Pan −1…1 for a world/camera bearing, rotated into the wearer's head frame.
    func pan(forBearingRadians bearing: Float) -> Float {
        var delta = bearing - headYaw
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        let clamped = max(-1, min(1, delta / (.pi / 2)))
        return clamped
    }

    private func refreshRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let headphonePorts: Set<AVAudioSession.Port> = [
            .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP
        ]
        usingHeadphones = outputs.contains { headphonePorts.contains($0.portType) }
        if !usingHeadphones {
            usingHeadTracking = false
            statusLine = "Connect AirPods for spatial cues"
        } else if !usingHeadTracking {
            statusLine = "Headphones connected"
        }
    }
}
