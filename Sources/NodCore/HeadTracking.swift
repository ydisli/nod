import Foundation

/// Head orientation from headphone motion sensors, in radians, already turned
/// into Nod's screen convention: yaw grows as you turn right, pitch grows as
/// you look down (screen y points down), roll grows as you lean your head
/// towards your right shoulder. Only differences matter; the zero point is
/// wherever the headphones happened to start.
public struct HeadPose: Sendable, Equatable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double

    public init(yaw: Double, pitch: Double, roll: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    /// Where the head points, as a 2D position (x right, y down).
    public var point: Vec2 { Vec2(yaw, pitch) }

    public static let zero = HeadPose(yaw: 0, pitch: 0, roll: 0)
}

public enum HeadGestureEvent: Equatable, Sendable {
    /// `startedAt` is when the movement began; for a nod that is before the
    /// head went down, so the click can land where the pointer was then.
    case began(HeadGesture, startedAt: Double)
    case ended(HeadGesture, duration: Double)
}

/// Turns a stream of head poses into tilt and nod events.
///
/// Tilts work like face gestures: an activation that must stay above 1 for
/// the hold time, with hysteresis on release. Leaning sideways does not steer
/// the pointer, so a tilt can be held while turning, which makes dragging easy.
/// A nod is a quick dip and return, reported as one tap.
public struct HeadGestureDetector: Sendable {
    public private(set) var activations: [HeadGesture: Double] = [:]
    /// Current sideways lean from the resting pose, radians, right positive.
    public private(set) var lean: Double = 0
    public var releaseLevel = 0.6
    public var cooldown = 0.3

    private enum Phase: Sendable, Equatable {
        case idle
        case pending(since: Double)
        case active(since: Double)
    }

    private var phases: [HeadGesture: Phase] = [:]
    private var cooldownUntil: [HeadGesture: Double] = [:]
    private var neutralRoll: Double?
    private var bootstrap: [Double] = []
    private var pitchHistory: [(time: Double, pitch: Double)] = []
    private var lastTime: Double?

    public init() {}

    /// Sideways lean, in radians, that counts as a tilt. Sensitivity 0.5
    /// asks for about 11 degrees.
    public static func tiltThreshold(sensitivity: Double) -> Double {
        (16 - 10 * sensitivity.clamped(0, 1)) * .pi / 180
    }

    /// How far the head must dip, in radians, for a nod.
    public static func nodDepth(sensitivity: Double) -> Double {
        (12 - 7 * sensitivity.clamped(0, 1)) * .pi / 180
    }

    public func isActive(_ g: HeadGesture) -> Bool {
        if case .active = phases[g] ?? .idle { return true }
        return false
    }

    /// Ends every held gesture, for example when the headphones disconnect.
    public mutating func reset(at time: Double) -> [HeadGestureEvent] {
        var events: [HeadGestureEvent] = []
        for g in HeadGesture.allCases {
            if case let .active(since) = phases[g] ?? .idle {
                events.append(.ended(g, duration: time - since))
            }
        }
        phases.removeAll()
        activations.removeAll()
        lean = 0
        pitchHistory.removeAll()
        lastTime = nil
        return events
    }

    public mutating func update(_ pose: HeadPose, time: Double, bindings: [HeadGesture: GestureBinding]) -> [HeadGestureEvent] {
        let dt = lastTime.map { max(0, min(time - $0, 0.5)) } ?? 0
        lastTime = time

        // The resting lean: the median of the first few samples, then a slow
        // follow while nothing is forming.
        guard let neutral = neutralRoll else {
            bootstrap.append(pose.roll)
            if bootstrap.count >= 8 {
                neutralRoll = bootstrap.sorted()[bootstrap.count / 2]
                bootstrap.removeAll()
            }
            return []
        }

        let lean = pose.roll - neutral
        self.lean = lean
        func binding(_ g: HeadGesture) -> GestureBinding { bindings[g] ?? .defaults(for: g) }
        var a: [HeadGesture: Double] = [:]
        a[.tiltLeft] = max(0, -lean) / Self.tiltThreshold(sensitivity: binding(.tiltLeft).sensitivity)
        a[.tiltRight] = max(0, lean) / Self.tiltThreshold(sensitivity: binding(.tiltRight).sensitivity)

        var events: [HeadGestureEvent] = []
        for g in [HeadGesture.tiltLeft, .tiltRight] {
            let b = binding(g)
            guard b.enabled else {
                if case let .active(since) = phases[g] ?? .idle {
                    events.append(.ended(g, duration: time - since))
                }
                phases[g] = .idle
                continue
            }
            let level = a[g] ?? 0
            switch phases[g] ?? .idle {
            case .idle:
                if level >= 1, time >= cooldownUntil[g] ?? 0 {
                    phases[g] = .pending(since: time)
                    if b.holdTime <= 0 {
                        phases[g] = .active(since: time)
                        events.append(.began(g, startedAt: time))
                    }
                }
            case let .pending(since):
                if level < releaseLevel {
                    phases[g] = .idle
                } else if time - since >= b.holdTime {
                    phases[g] = .active(since: since)
                    events.append(.began(g, startedAt: since))
                }
            case let .active(since):
                if level < releaseLevel {
                    phases[g] = .idle
                    cooldownUntil[g] = time + cooldown
                    events.append(.ended(g, duration: time - since))
                }
            }
        }

        a[.nod] = 0
        let nod = binding(.nod)
        if nod.enabled {
            if let startedAt = detectNod(pose.pitch, time: time, depth: Self.nodDepth(sensitivity: nod.sensitivity), activation: &a) {
                events.append(.began(.nod, startedAt: startedAt))
                events.append(.ended(.nod, duration: time - startedAt))
            }
        } else {
            pitchHistory.removeAll()
        }
        activations = a

        let leaning = max(a[.tiltLeft] ?? 0, a[.tiltRight] ?? 0)
        if dt > 0, leaning < 0.3 {
            neutralRoll = neutral + (pose.roll - neutral) * (1 - exp(-dt / 20.0))
        }
        return events
    }

    /// A nod: the head dips by at least `depth` within half a second and
    /// comes most of the way back within another half second. Returns when
    /// the dip started.
    private mutating func detectNod(_ pitch: Double, time: Double, depth: Double, activation a: inout [HeadGesture: Double]) -> Double? {
        pitchHistory.append((time, pitch))
        pitchHistory.removeAll { time - $0.time > 1.0 }
        guard time >= cooldownUntil[.nod] ?? 0,
              let lowestHead = pitchHistory.indices.max(by: { pitchHistory[$0].pitch < pitchHistory[$1].pitch })
        else { return nil }
        let bottom = pitchHistory[lowestHead]
        let before = pitchHistory[..<lowestHead].filter { bottom.time - $0.time <= 0.5 }
        guard let top = before.min(by: { $0.pitch < $1.pitch }) else { return nil }
        let dip = bottom.pitch - top.pitch
        a[.nod] = max(0, pitch - top.pitch) / depth
        guard dip >= depth,
              time - bottom.time <= 0.5,
              bottom.pitch - pitch >= 0.6 * dip,
              abs(pitch - top.pitch) <= 0.5 * dip
        else { return nil }
        pitchHistory.removeAll()
        cooldownUntil[.nod] = time + 0.6
        a[.nod] = 1
        return top.time
    }

    /// Highest activation among enabled tilts. Nods are left out: a nod
    /// looks like pointing downwards until it comes back up.
    public func formingLevel(bindings: [HeadGesture: GestureBinding], excluding: Set<HeadGesture> = []) -> Double {
        var best = 0.0
        for g in [HeadGesture.tiltLeft, .tiltRight] where !excluding.contains(g) && (bindings[g] ?? .defaults(for: g)).enabled {
            best = max(best, activations[g] ?? 0)
        }
        return best
    }
}
