import Foundation

/// The user's resting face, plus optionally how strongly they perform each
/// gesture. Gesture thresholds sit between the two.
public struct GestureBaseline: Codable, Sendable, Equatable {
    public var neutral: FaceMetrics
    /// Measured metric at full expression, from gesture calibration.
    /// For blinks and winks this is the measured closedness (0...1).
    public var peaks: [FaceGesture: Double]

    public init(neutral: FaceMetrics, peaks: [FaceGesture: Double] = [:]) {
        self.neutral = neutral
        self.peaks = peaks
    }
}

public enum GestureEvent: Equatable, Sendable {
    case began(FaceGesture)
    case ended(FaceGesture, duration: Double)
}

/// Turns a stream of `FaceMetrics` into gesture began/ended events.
///
/// Each gesture has an activation: 0 at rest, 1 at the trigger threshold.
/// A gesture begins after staying above 1 for its hold time, and ends when it
/// falls below `releaseLevel` (hysteresis, so it does not chatter).
public struct GestureDetector: Sendable {
    public private(set) var baseline: GestureBaseline?
    public private(set) var activations: [FaceGesture: Double] = [:]
    public var releaseLevel = 0.7
    public var cooldown = 0.25
    /// Keep the neutral face current while no gesture is forming.
    public var adaptsBaseline = true

    private enum Phase: Sendable, Equatable {
        case idle
        case pending(since: Double)
        case active(since: Double)
    }

    private var phases: [FaceGesture: Phase] = [:]
    private var cooldownUntil: [FaceGesture: Double] = [:]
    private var bootstrap: [FaceMetrics] = []
    private var lastTime: Double?

    public init(baseline: GestureBaseline? = nil) {
        self.baseline = baseline
    }

    public mutating func setBaseline(_ b: GestureBaseline?) {
        baseline = b
        bootstrap.removeAll()
    }

    public func isActive(_ g: FaceGesture) -> Bool {
        if case .active = phases[g] ?? .idle { return true }
        return false
    }

    public var activeGestures: [FaceGesture] { FaceGesture.allCases.filter(isActive) }

    /// Ends every active gesture, for example when the face is lost.
    public mutating func reset(at time: Double) -> [GestureEvent] {
        var events: [GestureEvent] = []
        for g in FaceGesture.allCases {
            if case let .active(since) = phases[g] ?? .idle {
                events.append(.ended(g, duration: time - since))
            }
        }
        phases.removeAll()
        activations.removeAll()
        lastTime = nil
        return events
    }

    /// Default change in each metric that counts as a full expression,
    /// used until the user calibrates their own.
    static func defaultSpan(_ g: FaceGesture) -> Double {
        switch g {
        case .mouthOpen: 0.30
        case .browRaise: 0.08
        case .smile: 0.20
        case .longBlink, .leftWink, .rightWink: 0.85
        }
    }

    /// Fraction of the full expression needed to trigger. Sensitivity 0.5
    /// asks for about half of a full expression.
    static func thresholdFraction(sensitivity: Double) -> Double {
        0.8 - 0.6 * sensitivity.clamped(0, 1)
    }

    private func span(_ g: FaceGesture, base: GestureBaseline) -> Double {
        if let peak = base.peaks[g] {
            let s: Double
            switch g {
            case .mouthOpen: s = peak - base.neutral.mouthOpen
            case .browRaise: s = peak - base.neutral.browRaise
            case .smile: s = peak - base.neutral.smile
            case .longBlink, .leftWink, .rightWink: s = peak
            }
            // Ignore a calibration where the user barely moved.
            if s > Self.defaultSpan(g) * 0.25 { return s }
        }
        return Self.defaultSpan(g)
    }

    /// How closed an eye is compared with the resting face, 0 open, 1 shut.
    public static func closedness(open: Double, neutral: Double) -> Double {
        guard neutral > 1e-6 else { return 0 }
        return (1 - open / neutral).clamped(0, 1)
    }

    public func computeActivations(_ m: FaceMetrics, bindings: [FaceGesture: GestureBinding]) -> [FaceGesture: Double] {
        guard let base = baseline else { return [:] }
        func frac(_ g: FaceGesture) -> Double {
            let s = bindings[g]?.sensitivity ?? 0.5
            return max(span(g, base: base) * Self.thresholdFraction(sensitivity: s), 1e-6)
        }
        var a: [FaceGesture: Double] = [:]
        a[.mouthOpen] = max(0, (m.mouthOpen - base.neutral.mouthOpen) / frac(.mouthOpen))
        a[.browRaise] = max(0, (m.browRaise - base.neutral.browRaise) / frac(.browRaise))
        a[.smile] = max(0, (m.smile - base.neutral.smile) / frac(.smile))

        let cl = Self.closedness(open: m.leftEyeOpen, neutral: base.neutral.leftEyeOpen)
        let cr = Self.closedness(open: m.rightEyeOpen, neutral: base.neutral.rightEyeOpen)
        let aBlinkL = cl / frac(.longBlink)
        let aBlinkR = cr / frac(.longBlink)
        a[.longBlink] = min(aBlinkL, aBlinkR)
        // A wink needs the other eye to stay clearly open.
        let aWinkL = cl / frac(.leftWink), aWinkR = cr / frac(.rightWink)
        a[.leftWink] = aWinkR < 0.5 ? aWinkL : 0
        a[.rightWink] = aWinkL < 0.5 ? aWinkR : 0
        return a
    }

    /// Feeds one frame. Returns gesture transitions for enabled gestures.
    public mutating func update(_ m: FaceMetrics, time: Double, bindings: [FaceGesture: GestureBinding]) -> [GestureEvent] {
        let dt = lastTime.map { max(0, min(time - $0, 0.5)) } ?? 0
        lastTime = time

        // Without a calibrated baseline, learn one from the first second of
        // frames (median is robust to a blink in the middle).
        if baseline == nil {
            bootstrap.append(m)
            if bootstrap.count >= 20 {
                baseline = GestureBaseline(neutral: Self.median(bootstrap))
                bootstrap.removeAll()
            }
            return []
        }

        let a = computeActivations(m, bindings: bindings)
        activations = a

        var events: [GestureEvent] = []
        for g in FaceGesture.allCases {
            guard let binding = bindings[g], binding.enabled else {
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
                    if binding.holdTime <= 0 {
                        phases[g] = .active(since: time)
                        events.append(.began(g))
                    }
                }
            case let .pending(since):
                if level < releaseLevel {
                    phases[g] = .idle
                } else if time - since >= binding.holdTime {
                    phases[g] = .active(since: since)
                    events.append(.began(g))
                }
            case let .active(since):
                if level < releaseLevel {
                    phases[g] = .idle
                    cooldownUntil[g] = time + cooldown
                    events.append(.ended(g, duration: time - since))
                }
            }
        }

        // Slowly follow changes in the resting face (posture, lighting),
        // but only while nothing is forming.
        if adaptsBaseline, dt > 0, var base = baseline, (a.values.max() ?? 0) < 0.3 {
            let k = 1 - exp(-dt / 45.0)
            let n = base.neutral
            base.neutral = FaceMetrics(
                mouthOpen: n.mouthOpen + (m.mouthOpen - n.mouthOpen) * k,
                smile: n.smile + (m.smile - n.smile) * k,
                browRaise: n.browRaise + (m.browRaise - n.browRaise) * k,
                leftEyeOpen: n.leftEyeOpen + (m.leftEyeOpen - n.leftEyeOpen) * k,
                rightEyeOpen: n.rightEyeOpen + (m.rightEyeOpen - n.rightEyeOpen) * k
            )
            baseline = base
        }
        return events
    }

    /// Highest activation among enabled gestures that is still forming or held.
    public func formingLevel(bindings: [FaceGesture: GestureBinding], excluding: Set<FaceGesture> = []) -> Double {
        var best = 0.0
        for (g, b) in bindings where b.enabled && !excluding.contains(g) {
            best = max(best, activations[g] ?? 0)
        }
        return best
    }

    public static func median(_ ms: [FaceMetrics]) -> FaceMetrics {
        func med(_ v: [Double]) -> Double {
            let s = v.sorted()
            return s.isEmpty ? 0 : s[s.count / 2]
        }
        return FaceMetrics(
            mouthOpen: med(ms.map(\.mouthOpen)),
            smile: med(ms.map(\.smile)),
            browRaise: med(ms.map(\.browRaise)),
            leftEyeOpen: med(ms.map(\.leftEyeOpen)),
            rightEyeOpen: med(ms.map(\.rightEyeOpen))
        )
    }
}
