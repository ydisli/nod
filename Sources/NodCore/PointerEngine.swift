import Foundation

public enum MouseButton: String, Sendable, Equatable {
    case left, right, middle
}

/// Output of the engine. The app turns these into real mouse events.
public enum PointerCommand: Equatable, Sendable {
    case move(to: Vec2, dragging: Bool)
    case press(MouseButton, at: Vec2)
    case release(MouseButton, at: Vec2)
    case click(MouseButton, count: Int, at: Vec2)
    /// Scroll distance in points; positive y moves the view down the page.
    case scroll(Vec2)
    case feedback(EngineFeedback)
}

/// Moments worth a sound or an on-screen hint.
public enum EngineFeedback: Equatable, Sendable {
    case performed(PointerAction)
    case dragStarted
    case dragEnded
    case scrollMode(Bool)
    case paused(Bool)
    case faceLost
    case faceFound
    case paletteToggleRequested
}

/// Where the pointer is allowed to go, in global display points (y down,
/// origin at the top left of the main display, like Quartz).
public struct EngineEnvironment: Sendable, Equatable {
    public var displays: [Rect2]
    /// Display used for direct mapping, eye mapping and recentring.
    public var mappingDisplay: Rect2
    /// Frame of the dwell palette, so dwelling on it presses its buttons.
    public var paletteFrame: Rect2?

    public init(displays: [Rect2], mappingDisplay: Rect2, paletteFrame: Rect2? = nil) {
        self.displays = displays
        self.mappingDisplay = mappingDisplay
        self.paletteFrame = paletteFrame
    }

    public static let placeholder = EngineEnvironment(
        displays: [Rect2(x: 0, y: 0, width: 1440, height: 900)],
        mappingDisplay: Rect2(x: 0, y: 0, width: 1440, height: 900)
    )

    /// Nearest point that lies on a real display (the union of display
    /// rectangles has holes when monitors differ in size).
    public func clamp(_ p: Vec2) -> Vec2 {
        guard !displays.isEmpty else { return mappingDisplay.clamp(p) }
        if displays.contains(where: { $0.contains(p) }) { return p }
        var best = displays[0].clamp(p)
        var bestD = best.distance(to: p)
        for d in displays.dropFirst() {
            let c = d.clamp(p)
            let dist = c.distance(to: p)
            if dist < bestD {
                best = c
                bestD = dist
            }
        }
        return best
    }
}

/// A read-only view of the engine for the UI.
public struct EngineStatus: Sendable, Equatable {
    public var pointer: Vec2 = .zero
    public var faceVisible = false
    public var paused = false
    public var dragging = false
    public var scrolling = false
    public var frozen = false
    public var dwellProgress: Double = 0
    public var dwellAction: PointerAction = .leftClick
    public var activations: [FaceGesture: Double] = [:]
    public var needsCalibration = false
    public var gazePoint: Vec2?

    public init() {}
}

/// The brain of Nod. Consumes face samples (about 30 per second) and clock
/// ticks (about 60 per second) and emits pointer commands.
///
/// It is a plain class with no locking: the app confines it to one queue.
public final class PointerEngine {
    public var settings: NodSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    public private(set) var profiles: [TrackingInput: CalibrationProfile]
    public var environment: EngineEnvironment {
        didSet { target = environment.clamp(target) }
    }
    public private(set) var status = EngineStatus()

    /// While suspended (during calibration) nothing is emitted at all.
    public var suspended = false {
        didSet { if suspended != oldValue { softReset() } }
    }

    // Tunables that are not user settings.
    /// Pointer glide time constant in seconds. Smooths 30 fps steps into 60+ fps motion.
    public var glideTime = 0.03
    /// Default nose travel (interocular units) to cross the display when uncalibrated.
    public static let defaultTravel = Vec2(0.6, 0.45)
    /// Physical mouse movement bigger than this (points) hands control back to it.
    public var yieldDistance = 12.0

    private var gestures = GestureDetector()
    private var dwell = DwellDetector()
    private var noseFilter = OneEuroFilter2D()
    private var headFilter = OneEuroFilter2D()
    private var filteredHead: Vec2?
    private var gazeFilter = OneEuroFilter2D()

    private var filteredNose: Vec2?
    private var lastNose: Vec2?
    private var lastSampleTime: Double?
    private var latest: FaceSample?
    private var lastFaceTime = -Double.infinity

    private var pointer = Vec2.zero
    private var target = Vec2.zero
    private var lastPosted: Vec2?
    private var yieldUntil = 0.0
    private var freezeUntil = 0.0
    private var glideBoostUntil = 0.0
    private var lastTick: Double?

    private var directOffset = Vec2.zero
    private var joystickNeutral: Vec2?
    private var joystickVelocity = Vec2.zero

    private var dragButtonDown = false
    private var holdGesture: FaceGesture?
    private var holdBegan: Double?

    private var scrollAnchor: Vec2?
    private var scrollVelocity = Vec2.zero
    private var scrollRestSince: Double?

    private var dwellOverride: PointerAction?

    private var gazeStableSince: Double?
    private var lastGazePoint: Vec2?

    public init(settings: NodSettings, profiles: [TrackingInput: CalibrationProfile] = [:], environment: EngineEnvironment = .placeholder) {
        self.settings = settings
        self.profiles = profiles
        self.environment = environment
        self.target = environment.mappingDisplay.center
        self.pointer = target
        refreshStatus()
    }

    // MARK: - Configuration

    public func setProfile(_ profile: CalibrationProfile?, for input: TrackingInput) {
        profiles[input] = profile
        directOffset = .zero
        joystickNeutral = nil
        refreshStatus()
    }

    /// Replaces the learned resting face, e.g. after a calibration run.
    public func setGestureBaseline(_ baseline: GestureBaseline?) {
        gestures.setBaseline(baseline)
    }

    public var gestureBaseline: GestureBaseline? { gestures.baseline }

    private func settingsChanged(from old: NodSettings) {
        if old.input != settings.input || old.motion != settings.motion {
            joystickVelocity = .zero
            lastNose = nil
            gazeFilter.reset()
            gazeStableSince = nil
        }
        if !settings.dwell.enabled { dwell.reset() }
        refreshStatus()
    }

    public func setDwellOverride(_ action: PointerAction?) {
        dwellOverride = action == settings.dwell.defaultAction ? nil : action
        dwell.disarm()
        refreshStatus()
    }

    /// Resets motion state, e.g. when tracking is switched on.
    public func reset(cursor: Vec2) {
        softReset()
        pointer = cursor
        target = cursor
        lastPosted = nil
        lastTick = nil
    }

    private func softReset() {
        noseFilter.reset()
        headFilter.reset()
        filteredHead = nil
        gazeFilter.reset()
        filteredNose = nil
        lastNose = nil
        lastSampleTime = nil
        joystickVelocity = .zero
        scrollVelocity = .zero
        dwell.reset()
        gazeStableSince = nil
    }

    // MARK: - Frames

    /// Feeds one camera frame. Pass nil when no face was found.
    public func ingest(_ sample: FaceSample?, time: Double) -> [PointerCommand] {
        guard !suspended else { return [] }
        var out: [PointerCommand] = []

        guard let s = sample else {
            if status.faceVisible, time - lastFaceTime > 0.35 {
                status.faceVisible = false
                out += handle(gestures.reset(at: time), time: time)
                softReset()
                out.append(.feedback(.faceLost))
            }
            // Never leave a button stuck down if the face disappears mid drag.
            if dragButtonDown, time - lastFaceTime > 2.5 {
                out += endDrag()
            }
            refreshStatus()
            return out
        }

        if !status.faceVisible { out.append(.feedback(.faceFound)) }
        status.faceVisible = true
        lastFaceTime = time
        latest = s

        let events = gestures.update(s.metrics, time: time, bindings: settings.gestures)
        out += handle(events, time: time)

        let dt = lastSampleTime.map { (time - $0).clamped(1.0 / 240, 0.25) } ?? (1.0 / 30)
        lastSampleTime = time

        let (mc, beta) = OneEuroFilter2D.parameters(smoothing: settings.smoothing, speedScale: max(s.faceScale, 0.02))
        noseFilter.configure(minCutoff: mc, beta: beta)
        let nose = noseFilter.filter(s.nose, at: time)
        filteredNose = nose
        let (hc, hb) = OneEuroFilter2D.parameters(smoothing: settings.smoothing, speedScale: 0.3)
        headFilter.configure(minCutoff: hc, beta: hb)
        filteredHead = headFilter.filter(s.headAngle, at: time)
        defer { lastNose = nose }

        let frozen = isFrozen(time: time, sample: s)
        status.frozen = frozen

        if status.scrolling {
            updateScroll(nose: nose, sample: s, time: time, out: &out)
            refreshStatus()
            return out
        }
        guard !status.paused else {
            refreshStatus()
            return out
        }

        switch effectiveMode {
        case .relative:
            applyRelative(nose: nose, sample: s, dt: dt, frozen: frozen, time: time)
        case .direct:
            if !frozen, time >= yieldUntil, let p = profiles[.nose] {
                let n = p.mapping.predict(directFeatures(p, nose: nose)) + directOffset
                target = environment.clamp(environment.mappingDisplay.point(atNormalized: n))
            }
        case .joystick:
            applyJoystick(nose: nose, sample: s, frozen: frozen)
        case .eyes:
            if let g = gazeTarget(sample: s, nose: nose, time: time), !frozen, time >= yieldUntil {
                target = g
            }
        case .hybrid:
            applyRelative(nose: nose, sample: s, dt: dt, frozen: frozen, time: time)
            if let g = gazeTarget(sample: s, nose: nose, time: time), !frozen, time >= yieldUntil {
                let jump = settings.hybridJumpDistance * environment.mappingDisplay.width
                if let since = gazeStableSince, time - since >= 0.12, g.distance(to: target) > jump {
                    target = g
                    glideBoostUntil = time + 0.25
                    dwell.reset()
                }
            }
        }
        refreshStatus()
        return out
    }

    private enum Mode { case relative, direct, joystick, eyes, hybrid }

    private var effectiveMode: Mode {
        switch settings.input {
        case .eyes: return .eyes
        case .hybrid: return .hybrid
        case .nose:
            switch settings.motion {
            case .relative: return .relative
            case .direct: return profiles[.nose] == nil ? .relative : .direct
            case .joystick: return .joystick
            }
        }
    }

    private var travel: Vec2 {
        profiles[.nose]?.travel ?? Self.defaultTravel
    }

    /// Overall scale of relative motion at speed 1.
    public static let relativeGain = 0.6

    /// Calibrated travel, made safe. People tilt their heads far less than
    /// they turn them (a real calibration measured 0.12 vs 0.48 interocular
    /// units), which left the vertical axis 2.5 times as sensitive, and as
    /// jittery. The vertical travel is floored relative to the horizontal.
    var effectiveTravel: Vec2 {
        let tr = travel
        let d = environment.mappingDisplay
        let aspect = d.height / max(d.width, 1)
        let x = max(tr.x, 0.25)
        return Vec2(x, max(tr.y, x * aspect * 0.8))
    }

    private var invert: Vec2 {
        Vec2(settings.invertX ? -1 : 1, settings.invertY ? -1 : 1)
    }

    /// Features for the direct nose mapping. Older profiles used the nose
    /// position only; newer ones add the head angle.
    private func directFeatures(_ p: CalibrationProfile, nose: Vec2) -> [Double] {
        guard p.mapping.featureCount >= 4 else { return [nose.x, nose.y] }
        let h = filteredHead ?? .zero
        return [nose.x, nose.y, h.x, h.y]
    }

    private func applyRelative(nose: Vec2, sample s: FaceSample, dt: Double, frozen: Bool, time: Double) {
        guard let prev = lastNose, !frozen, time >= yieldUntil else { return }
        var d = (nose - prev) / max(s.faceScale, 1e-3)
        d = Vec2(d.x * invert.x, d.y * invert.y)
        let tr = effectiveTravel
        let v = d.length / dt
        // A full calibrated sweep per second moves at the base gain; slower
        // is finer, faster travels further.
        let factor = pow(max(v, 1e-6) / tr.x, settings.acceleration).clamped(0.25, 2.2)
        let display = environment.mappingDisplay
        let speed = settings.speed.clamped(0.1, 5)
        let step = Vec2(d.x * display.width / tr.x, d.y * display.height / tr.y) * (speed * factor * Self.relativeGain)
        target = environment.clamp(target + step)
    }

    private func applyJoystick(nose: Vec2, sample s: FaceSample, frozen: Bool) {
        if joystickNeutral == nil {
            joystickNeutral = profiles[.nose]?.neutralNose ?? nose
        }
        guard let neutral = joystickNeutral, !frozen else {
            joystickVelocity = .zero
            return
        }
        var o = (nose - neutral) / max(s.faceScale, 1e-3)
        o = Vec2(o.x * invert.x, o.y * invert.y)
        let half = effectiveTravel / 2
        let unit = Self.joystick(offset: Vec2(o.x / half.x, o.y / half.y), deadzone: settings.deadzone)
        let w = environment.mappingDisplay.width
        joystickVelocity = unit * (settings.joystickSpeed * w * settings.speed.clamped(0.1, 5))
    }

    /// Maps a normalised stick offset (1 = calibrated edge) to a velocity
    /// fraction, with a radial dead zone and a gentle curve for precision.
    public static func joystick(offset o: Vec2, deadzone: Double) -> Vec2 {
        let mag = o.length
        guard mag > deadzone else { return .zero }
        let m = min((mag - deadzone) / max(1 - deadzone, 1e-6), 1)
        return o.normalized * pow(m, 1.6)
    }

    /// Where the eyes are looking, in display points, filtered.
    private func gazeTarget(sample s: FaceSample, nose: Vec2, time: Double) -> Vec2? {
        guard let p = profiles[.eyes] else { return nil }
        // Gaze is meaningless while the eyes are closing.
        if eyesClosing(s) { return nil }
        let raw = p.mapping.predict(s.eyeFeatures) + directOffset
        let (mc, beta) = OneEuroFilter2D.parameters(smoothing: settings.eyeSmoothing, speedScale: 1.0)
        gazeFilter.configure(minCutoff: mc, beta: beta)
        let n = gazeFilter.filter(raw, at: time)
        let point = environment.clamp(environment.mappingDisplay.point(atNormalized: n))
        let still = 0.05 * environment.mappingDisplay.width
        if let last = lastGazePoint, last.distance(to: point) < still {
            if gazeStableSince == nil { gazeStableSince = time }
        } else {
            gazeStableSince = nil
        }
        lastGazePoint = point
        status.gazePoint = point
        return point
    }

    private func eyesClosing(_ s: FaceSample) -> Bool {
        guard let base = gestures.baseline else { return false }
        let cl = GestureDetector.closedness(open: s.metrics.leftEyeOpen, neutral: base.neutral.leftEyeOpen)
        let cr = GestureDetector.closedness(open: s.metrics.rightEyeOpen, neutral: base.neutral.rightEyeOpen)
        return max(cl, cr) > 0.35
    }

    private func isFrozen(time: Double, sample s: FaceSample) -> Bool {
        if time < freezeUntil { return true }
        if settings.input != .nose, eyesClosing(s) { return true }
        guard settings.holdSteadyWhileGesturing else { return false }
        var excluding = Set<FaceGesture>()
        // A held "click and hold" gesture is a drag: let the pointer move
        // once the press has settled.
        if let g = holdGesture, let began = holdBegan, time - began > 0.35 {
            excluding.insert(g)
        }
        return gestures.formingLevel(bindings: settings.gestures, excluding: excluding) >= 0.5
    }

    private func updateScroll(nose: Vec2, sample s: FaceSample, time: Double, out: inout [PointerCommand]) {
        if scrollAnchor == nil { scrollAnchor = nose }
        guard let anchor = scrollAnchor else { return }
        var o = (nose - anchor) / max(s.faceScale, 1e-3)
        o = Vec2(o.x * invert.x, o.y * invert.y)
        let half = effectiveTravel / 2
        let unit = Self.joystick(offset: Vec2(o.x / half.x, o.y / half.y) * 2.5, deadzone: 0.18)
        scrollVelocity = unit * 1800
        // Holding still at the centre for a while ends scroll mode when
        // dwelling is on, so it can be left without any gesture.
        if settings.dwell.enabled {
            if unit == .zero {
                if scrollRestSince == nil { scrollRestSince = time }
                if let since = scrollRestSince, time - since >= settings.dwell.time * 1.5 {
                    out += setScrolling(false)
                }
            } else {
                scrollRestSince = nil
            }
        }
    }

    // MARK: - Clock

    /// Advances the pointer. Call at display rate (about 60 Hz).
    /// - Parameter cursor: where the system cursor actually is right now.
    public func tick(time: Double, cursor: Vec2) -> [PointerCommand] {
        guard !suspended else { return [] }
        let dt = lastTick.map { (time - $0).clamped(0, 0.1) } ?? 0
        lastTick = time
        var out: [PointerCommand] = []

        guard let posted = lastPosted else {
            pointer = cursor
            target = cursor
            lastPosted = cursor
            return out
        }

        // Someone moved the real mouse: step aside instead of fighting.
        if settings.yieldToMouse, cursor.distance(to: posted) > yieldDistance {
            pointer = cursor
            target = cursor
            lastPosted = cursor
            yieldUntil = time + 0.6
            dwell.reset()
            refreshStatus()
            return out
        }

        if status.scrolling, scrollVelocity != .zero, dt > 0 {
            out.append(.scroll(scrollVelocity * dt))
        }

        if status.paused || (!status.faceVisible && !dragButtonDown) {
            status.dwellProgress = 0
            refreshStatus()
            return out
        }

        if effectiveMode == .joystick, !status.frozen, time >= yieldUntil, dt > 0 {
            target = environment.clamp(target + joystickVelocity * dt)
        }

        if dt > 0 {
            let tau = time < glideBoostUntil ? 0.08 : glideTime
            pointer = pointer + (target - pointer) * (1 - exp(-dt / tau))
            if pointer.distance(to: target) < 0.25 { pointer = target }
        }

        if time >= yieldUntil, pointer.distance(to: posted) >= 0.5 {
            out.append(.move(to: pointer, dragging: dragButtonDown))
            lastPosted = pointer
        }

        if settings.dwell.enabled, status.faceVisible, !status.scrolling {
            dwell.dwellTime = settings.dwell.time
            dwell.radius = settings.dwell.radius
            let (progress, fired) = dwell.update(position: pointer, time: time)
            status.dwellProgress = progress
            if fired { out += performDwell(time: time) }
        } else {
            status.dwellProgress = 0
        }
        refreshStatus()
        return out
    }

    // MARK: - Actions

    private func handle(_ events: [GestureEvent], time: Double) -> [PointerCommand] {
        var out: [PointerCommand] = []
        for e in events {
            switch e {
            case let .began(g):
                let action = settings.binding(for: g).action
                dwell.disarm()
                if action == .leftHold {
                    guard !status.paused, !dragButtonDown else { continue }
                    dragButtonDown = true
                    holdGesture = g
                    holdBegan = time
                    out.append(.press(.left, at: pointer))
                    out.append(.feedback(.performed(.leftHold)))
                } else {
                    out += perform(action, time: time)
                }
            case let .ended(g, _):
                if holdGesture == g {
                    holdGesture = nil
                    holdBegan = nil
                    if dragButtonDown {
                        dragButtonDown = false
                        out.append(.release(.left, at: pointer))
                    }
                }
                // Let the face settle before the pointer moves again.
                freezeUntil = max(freezeUntil, time + 0.15)
            }
        }
        return out
    }

    /// Performs an action at the current pointer position.
    public func perform(_ action: PointerAction, time: Double) -> [PointerCommand] {
        if status.paused, action != .pauseToggle, action != .togglePalette { return [] }
        var out: [PointerCommand] = []
        switch action {
        case .none:
            return []
        case .leftClick, .leftHold:
            out.append(.click(.left, count: 1, at: pointer))
        case .rightClick:
            out.append(.click(.right, count: 1, at: pointer))
        case .middleClick:
            out.append(.click(.middle, count: 1, at: pointer))
        case .doubleClick:
            out.append(.click(.left, count: 2, at: pointer))
        case .dragToggle:
            if dragButtonDown {
                return endDrag()
            }
            dragButtonDown = true
            holdGesture = nil
            out.append(.press(.left, at: pointer))
            out.append(.feedback(.dragStarted))
            refreshStatus()
            return out
        case .scrollToggle:
            return setScrolling(!status.scrolling)
        case .pauseToggle:
            status.paused.toggle()
            if status.paused, dragButtonDown { out += endDrag() }
            if status.paused, status.scrolling { out += setScrolling(false) }
            lastNose = nil
            dwell.reset()
            out.append(.feedback(.paused(status.paused)))
            refreshStatus()
            return out
        case .recenter:
            recenter()
        case .togglePalette:
            out.append(.feedback(.paletteToggleRequested))
            return out
        }
        freezeUntil = max(freezeUntil, time + 0.12)
        out.append(.feedback(.performed(action)))
        return out
    }

    private func endDrag() -> [PointerCommand] {
        guard dragButtonDown else { return [] }
        dragButtonDown = false
        holdGesture = nil
        holdBegan = nil
        refreshStatus()
        return [.release(.left, at: pointer), .feedback(.dragEnded)]
    }

    private func setScrolling(_ on: Bool) -> [PointerCommand] {
        guard on != status.scrolling else { return [] }
        status.scrolling = on
        scrollAnchor = on ? filteredNose : nil
        scrollVelocity = .zero
        scrollRestSince = nil
        dwell.reset()
        if !on { lastNose = nil }
        refreshStatus()
        return [.feedback(.scrollMode(on))]
    }

    private func performDwell(time: Double) -> [PointerCommand] {
        // Dwelling on the palette always presses the palette button.
        if let frame = environment.paletteFrame, frame.contains(pointer) {
            return [.click(.left, count: 1, at: pointer)]
        }
        let action = dwellOverride ?? settings.dwell.defaultAction
        let out = perform(action, time: time)
        if action == .dragToggle {
            // Keep "drag" selected until the drop happens.
            if !dragButtonDown, !settings.dwell.stickyChoice { dwellOverride = nil }
        } else if !settings.dwell.stickyChoice {
            dwellOverride = nil
        }
        refreshStatus()
        return out
    }

    /// Puts the pointer back in the middle of the mapping display, or makes the
    /// current head pose the new centre, depending on the mode.
    public func recenter() {
        let display = environment.mappingDisplay
        switch effectiveMode {
        case .relative:
            target = display.center
            pointer = target
        case .joystick:
            joystickNeutral = filteredNose
            joystickVelocity = .zero
        case .direct:
            if let p = profiles[.nose], let nose = filteredNose {
                let n = p.mapping.predict(directFeatures(p, nose: nose))
                directOffset = Vec2(0.5, 0.5) - n
            }
        case .eyes, .hybrid:
            if let p = profiles[.eyes], let s = latest {
                let n = p.mapping.predict(s.eyeFeatures)
                directOffset = Vec2(0.5, 0.5) - n
            }
            target = display.center
            pointer = target
            gazeFilter.reset()
        }
        dwell.reset()
    }

    private func refreshStatus() {
        status.pointer = pointer
        status.dragging = dragButtonDown
        status.activations = gestures.activations
        status.dwellAction = dwellOverride ?? settings.dwell.defaultAction
        switch settings.input {
        case .nose: status.needsCalibration = settings.motion == .direct && profiles[.nose] == nil
        case .eyes, .hybrid: status.needsCalibration = profiles[.eyes] == nil
        }
    }
}
