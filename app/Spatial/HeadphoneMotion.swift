import AVFoundation
import CoreMotion
import Foundation
import simd

struct ListenerOrientation: Equatable {
    /// Degrees, AVAudioEnvironmentNode convention (yaw about Y, pitch about X, roll about Z).
    var yaw: Float
    var pitch: Float
    var roll: Float

    static let identity = ListenerOrientation(yaw: 0, pitch: 0, roll: 0)
}

/// AirPods head tracking when available; phone attitude as fallback. Exposes listener orientation for HRTF.
@MainActor
final class HeadphoneMotion: ObservableObject {
    @Published private(set) var headYaw: Float = 0
    @Published private(set) var usingHeadphones = false
    @Published private(set) var usingHeadTracking = false
    @Published private(set) var statusLine = "Connect AirPods for spatial audio"
    @Published private(set) var listener = ListenerOrientation.identity

    private let headphone = CMHeadphoneMotionManager()
    private let device = CMMotionManager()
    private var routeObserver: NSObjectProtocol?

    private var headAttitude: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var phoneAttitude: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var hasHead = false
    private var hasPhone = false

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
                guard let self, let motion else { return }
                Task { @MainActor in
                    self.usingHeadTracking = true
                    self.headYaw = Float(motion.attitude.yaw)
                    self.headAttitude = Self.quat(motion.attitude)
                    self.hasHead = true
                    self.recomputeListener()
                    self.statusLine = "AirPods · HRTF head tracking"
                }
            }
        }

        if device.isDeviceMotionAvailable {
            device.deviceMotionUpdateInterval = 1.0 / 30.0
            device.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                Task { @MainActor in
                    self.phoneAttitude = Self.quat(motion.attitude)
                    self.hasPhone = true
                    if !self.usingHeadTracking {
                        self.headYaw = Float(motion.attitude.yaw)
                        if self.usingHeadphones {
                            self.statusLine = "Headphones · phone attitude"
                        }
                    }
                    self.recomputeListener()
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

    /// Pan −1…1 fallback when HRTF isn't running.
    func pan(forBearingRadians bearing: Float) -> Float {
        var delta = bearing - headYaw
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        return max(-1, min(1, delta / (.pi / 2)))
    }

    private func recomputeListener() {
        // Head relative to phone so chest-mounted camera is the world frame and turning your head moves the HRTF.
        if hasHead, hasPhone {
            let relative = simd_mul(simd_inverse(phoneAttitude), headAttitude)
            let (yaw, pitch, roll) = Self.eulerDegrees(relative)
            listener = ListenerOrientation(yaw: yaw, pitch: pitch, roll: roll)
            headYaw = yaw * .pi / 180
        } else if hasHead || hasPhone {
            let q = hasHead ? headAttitude : phoneAttitude
            let (yaw, pitch, roll) = Self.eulerDegrees(q)
            listener = ListenerOrientation(yaw: yaw, pitch: pitch, roll: roll)
        }
    }

    private static func quat(_ attitude: CMAttitude) -> simd_quatf {
        let q = attitude.quaternion
        return simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
    }

    private static func eulerDegrees(_ q: simd_quatf) -> (Float, Float, Float) {
        // Yaw (Y), pitch (X), roll (Z) from quaternion.
        let sinp = 2 * (q.real * q.imag.x + q.imag.y * q.imag.z)
        let pitch: Float
        if abs(sinp) >= 1 {
            pitch = copysign(.pi / 2, sinp)
        } else {
            pitch = asin(sinp)
        }
        let siny = 2 * (q.real * q.imag.y - q.imag.z * q.imag.x)
        let cosy = 1 - 2 * (q.imag.x * q.imag.x + q.imag.y * q.imag.y)
        let yaw = atan2(siny, cosy)
        let sinr = 2 * (q.real * q.imag.z + q.imag.x * q.imag.y)
        let cosr = 1 - 2 * (q.imag.x * q.imag.x + q.imag.z * q.imag.z)
        let roll = atan2(sinr, cosr)
        let rad2deg: Float = 180 / .pi
        return (yaw * rad2deg, pitch * rad2deg, roll * rad2deg)
    }

    private func refreshRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let headphonePorts: Set<AVAudioSession.Port> = [
            .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP
        ]
        usingHeadphones = outputs.contains { headphonePorts.contains($0.portType) }
        if !usingHeadphones {
            usingHeadTracking = false
            statusLine = "Connect AirPods for spatial audio"
        } else if !usingHeadTracking {
            statusLine = "Headphones connected"
        }
    }
}
