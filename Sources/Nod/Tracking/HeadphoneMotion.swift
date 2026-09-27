import CoreMotion
import Foundation
import NodCore

/// Head orientation from AirPods (and other headphones with head tracking)
/// through CoreMotion. The headphones fuse their own gyroscope and
/// accelerometer and send a finished orientation, so the Mac only receives a
/// few small numbers per update. No camera, no image processing.
///
/// Callbacks arrive on the queue passed to `init`.
final class HeadphoneMotion: NSObject, CMHeadphoneMotionManagerDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case pose(HeadPose)
        case connected(Bool)
        case failed(String)
    }

    private let manager = CMHeadphoneMotionManager()
    private let operations = OperationQueue()
    private let queue: DispatchQueue
    private let onEvent: @Sendable (Event) -> Void
    // Confined to `queue`.
    private var lastRawYaw: Double?
    private var turns = 0.0
    private var active = false

    init(queue: DispatchQueue, onEvent: @escaping @Sendable (Event) -> Void) {
        self.queue = queue
        self.onEvent = onEvent
        operations.underlyingQueue = queue
        operations.maxConcurrentOperationCount = 1
        super.init()
        manager.delegate = self
    }

    static var authorization: CMAuthorizationStatus { CMHeadphoneMotionManager.authorizationStatus() }

    /// Call on `queue`.
    func start() {
        guard !active else { return }
        active = true
        manager.startConnectionStatusUpdates()
        startMotion()
    }

    private func startMotion() {
        lastRawYaw = nil
        guard manager.isDeviceMotionAvailable else {
            onEvent(.failed("This Mac cannot read headphone motion."))
            return
        }
        manager.startDeviceMotionUpdates(to: operations) { [weak self] motion, error in
            guard let self else { return }
            if let motion {
                self.onEvent(.pose(self.pose(from: motion.attitude)))
            } else if let error {
                self.onEvent(.failed(Self.describe(error)))
            }
        }
    }

    /// Asks for motion again without touching connection updates (restarting
    /// those would report the connection again). Call on `queue`.
    func restartMotion() {
        guard active else { return }
        manager.stopDeviceMotionUpdates()
        startMotion()
    }

    /// Call on `queue`.
    func stop() {
        guard active else { return }
        active = false
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
    }

    /// CoreMotion angles grow turning left and looking up; Nod's grow turning
    /// right and looking down, like screen coordinates. Yaw is unwrapped so a
    /// turn through ±180 degrees does not look like a jump.
    private func pose(from a: CMAttitude) -> HeadPose {
        if let last = lastRawYaw {
            let step = a.yaw - last
            if step > .pi { turns -= 1 } else if step < -.pi { turns += 1 }
        }
        lastRawYaw = a.yaw
        let yaw = a.yaw + turns * 2 * .pi
        return HeadPose(yaw: -yaw, pitch: -a.pitch, roll: a.roll)
    }

    private static func describe(_ error: Error) -> String {
        let e = error as NSError
        let denied = [CMErrorNotAuthorized, CMErrorMotionActivityNotAuthorized].map { Int($0.rawValue) }
        if e.domain == CMErrorDomain, denied.contains(e.code) {
            return "Motion access is off for Nod. Allow it in System Settings, Privacy & Security."
        }
        return e.localizedDescription
    }

    // MARK: CMHeadphoneMotionManagerDelegate

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        queue.async {
            self.lastRawYaw = nil
            self.onEvent(.connected(true))
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        queue.async { self.onEvent(.connected(false)) }
    }
}
