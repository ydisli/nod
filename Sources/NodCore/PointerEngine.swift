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
    /// The headphones stopped or started sending head motion.
    case lost
    case found
    case paletteToggleRequested
}

/// Where the pointer is allowed to go, in global display points (y down,
/// origin at the top left of the main display, like Quartz).
public struct EngineEnvironment: Sendable, Equatable {
    public var displays: [Rect2]
    /// Display used for direct aiming and recentring.
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
    /// Head motion is arriving.
    public var tracking = false
    public var paused = false
    public var dragging = false
    public var scrolling = false
    public var frozen = false
    public var dwellProgress: Double = 0
    public var dwellAction: PointerAction = .leftClick
    /// Tilt and nod strength, 1 at the trigger point.
    public var activations: [HeadGesture: Double] = [:]
    /// The head's recent movement, about -1...1 per axis, for the UI.
    public var headOffset: Vec2 = .zero
    /// Sideways lean from the resting pose, radians, right positive.
    public var headLean: Double = 0

    public init() {}
}

/// The brain of Nod. Consumes head poses from AirPods (about 50 per second),
/// click keys and clock ticks (about 60 per second), and emits pointer
/// commands.
///
/// It is a plain class with no locking: the app confines it to one queue.
public final class PointerEngine {
    public var settings: NodSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    public var environment: EngineEnvironment {
        didSet { target = environment.clamp(target) }
    }
    public private(set) var status = EngineStatus()

    /// While suspended (previews) nothing is emitted, but meters stay live.
    public var suspended = false {
        didSet { if suspended != oldValue { softReset() } }
    }

    // Tunables that are not user settings.
    /// Pointer glide time constant in seconds. Smooths sensor steps into 60+ fps motion.
    public var glideTime = 0.03
    /// Head turn (radians) that crosses the display at speed 1: about 20
    /// degrees across and 13 up and down.
    public static let headTravel = Vec2(0.35, 0.22)
    /// Physical mouse movement bigger than this (points) hands control back to it.
    public var yieldDistance = 12.0
    /// Overall scale of relative motion at speed 1.
    public static let relativeGain = 0.6

    private var gestures = HeadGestureDetector()
    private var keyClicks = KeyClickDetector()
    private var dwell = DwellDetector()
    private var filter = OneEuroFilter2D()

    private var filtered: Vec2?
    private var last: Vec2?
    private var lastSampleTime: Double?
    private var lastSeen = -Double.infinity
    /// Head pose linked to the display centre, for direct aiming.
    private var neutral: Vec2?
    /// Slowly follows the head, so the UI can show recent movement.
    private var centre: Vec2?
    /// Recent pointer targets, so a nod can click where the pointer was
    /// before the head went down.
    private var targetHistory: [(time: Double, point: Vec2)] = []

    private var pointer = Vec2.zero
    private var target = Vec2.zero
    private var lastPosted: Vec2?
    private var yieldUntil = 0.0
    private var freezeUntil = 0.0
    private var lastTick: Double?

    private var joystickNeutral: Vec2?
    private var joystickVelocity = Vec2.zero

    private var dragButtonDown = false
    private var holdGesture: HeadGesture?
    private var holdBegan: Double?

    private var scrollAnchor: Vec2?
    private var scrollVelocity = Vec2.zero
    private var scrollRestSince: Double?

    private var dwellOverride: PointerAction?

    public init(settings: NodSettings, environment: EngineEnvironment = .placeholder) {
        self.settings = settings
        self.environment = environment
        self.target = environment.mappingDisplay.center
        self.pointer = target
        refreshStatus()
    }

    // MARK: - Configuration

    private func settingsChanged(from old: NodSettings) {
        if old.motion != settings.motion {
            joystickVelocity = .zero
            joystickNeutral = nil
            last = nil
            neutral = nil
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
        filter.reset()
        filtered = nil
        last = nil
        lastSampleTime = nil
        joystickVelocity = .zero
        scrollVelocity = .zero
        dwell.reset()
        neutral = nil
        centre = nil
        targetHistory.removeAll()
    }

    // MARK: - Head motion

    /// Feeds one head pose. Pass nil when the headphones are not sending
    /// (out of the ears, disconnected).
    public func ingest(head pose: HeadPose?, time: Double) -> [PointerCommand] {
        guard !suspended else {
            // Previews still show live gesture meters.
            if let pose {
                _ = gestures.update(pose, time: time, bindings: settings.headGestures)
                status.activations = gestures.activations
                status.headLean = gestures.lean
            }
            return []
        }
        guard let pose else { return trackingLost(time: time) }
        var out = trackingFound(time: time)

        out += handle(gestures.update(pose, time: time, bindings: settings.headGestures), time: time)

        let dt = lastSampleTime.map { (time - $0).clamped(1.0 / 240, 0.25) } ?? (1.0 / 50)
        lastSampleTime = time

        let (mc, beta) = OneEuroFilter2D.parameters(smoothing: settings.smoothing, speedScale: 0.6)
        filter.configure(minCutoff: mc, beta: beta)
        let point = filter.filter(pose.point, at: time)
        filtered = point
        defer { last = point }

        let c = centre.map { $0 + (point - $0) * (1 - exp(-dt / 2.5)) } ?? point
        centre = c
        let half = effectiveTravel / 2
        status.headOffset = Vec2(((point.x - c.x) / half.x).clamped(-1, 1), ((point.y - c.y) / half.y).clamped(-1, 1))
        status.headLean = gestures.lean

        let frozen = isFrozen(time: time)
        status.frozen = frozen

        if status.scrolling {
            updateScroll(point, time: time, out: &out)
            refreshStatus()
            return out
        }
        guard !status.paused else {
            refreshStatus()
            return out
        }

        switch settings.motion {
        case .relative:
            applyRelative(point, dt: dt, frozen: frozen, time: time)
        case .direct:
            if !frozen, time >= yieldUntil { target = directTarget(point) }
        case .joystick:
            applyJoystick(point, frozen: frozen)
        }
        targetHistory.append((time, target))
        targetHistory.removeAll { time - $0.time > 1.5 }
        refreshStatus()
        return out
    }

    /// Tracking was stopped on purpose (switched off): end gestures and let
    /// go of any held button straight away.
    public func trackingStopped(time: Double) -> [PointerCommand] {
        lastSeen = -.infinity
        return trackingLost(time: time)
    }

    private func trackingFound(time: Double) -> [PointerCommand] {
        let found = !status.tracking
        status.tracking = true
        lastSeen = time
        return found ? [.feedback(.found)] : []
    }

    private func trackingLost(time: Double) -> [PointerCommand] {
        var out: [PointerCommand] = []
        if status.tracking, time - lastSeen > 0.35 {
            status.tracking = false
            out += handle(gestures.reset(at: time), time: time)
            softReset()
            out.append(.feedback(.lost))
        }
        // Never leave a button stuck down if tracking stops mid drag.
        if dragButtonDown, time - lastSeen > 2.5 {
            out += endDrag()
        }
        refreshStatus()
        return out
    }

    /// Travel made safe: people tilt their heads far less than they turn
    /// them, so the vertical travel is floored relative to the horizontal.
    var effectiveTravel: Vec2 {
        let tr = Self.headTravel
        let d = environment.mappingDisplay
        let aspect = d.height / max(d.width, 1)
        let x = max(tr.x, 0.25)
        return Vec2(x, max(tr.y, x * aspect * 0.8))
    }

    private var invert: Vec2 {
        Vec2(settings.invertX ? -1 : 1, settings.invertY ? -1 : 1)
    }

    private func applyRelative(_ p: Vec2, dt: Double, frozen: Bool, time: Double) {
        guard let prev = last, !frozen, time >= yieldUntil else { return }
        var d = p - prev
        d = Vec2(d.x * invert.x, d.y * invert.y)
        let tr = effectiveTravel
        let v = d.length / dt
        // A full sweep per second moves at the base gain; slower is finer,
        // faster travels further.
        let factor = pow(max(v, 1e-6) / tr.x, settings.acceleration).clamped(0.25, 2.2)
        let display = environment.mappingDisplay
        let speed = settings.speed.clamped(0.1, 5)
        let step = Vec2(d.x * display.width / tr.x, d.y * display.height / tr.y) * (speed * factor * Self.relativeGain)
        target = environment.clamp(target + step)
    }

    /// Direct aiming needs no calibration: the head pose is linked to
    /// wherever the pointer is when aiming starts (so nothing jumps), and
    /// Recentre links the current pose to the display centre.
    private func directTarget(_ p: Vec2) -> Vec2 {
        let d = environment.mappingDisplay
        let tr = effectiveTravel / settings.speed.clamped(0.25, 5)
        if neutral == nil {
            let n = d.normalized(target) - Vec2(0.5, 0.5)
            neutral = p - Vec2(n.x * invert.x * tr.x, n.y * invert.y * tr.y)
        }
        let o = p - (neutral ?? p)
        let u = Vec2(o.x * invert.x / tr.x, o.y * invert.y / tr.y)
        return environment.clamp(d.point(atNormalized: Vec2(0.5, 0.5) + u))
    }

    private func applyJoystick(_ p: Vec2, frozen: Bool) {
        if joystickNeutral == nil { joystickNeutral = p }
        guard let n = joystickNeutral, !frozen else {
            joystickVelocity = .zero
            return
        }
        var o = p - n
        o = Vec2(o.x * invert.x, o.y * invert.y)
        let half = effectiveTravel / 2
        let unit = Self.joystick(offset: Vec2(o.x / half.x, o.y / half.y), deadzone: settings.deadzone)
        let w = environment.mappingDisplay.width
        joystickVelocity = unit * (settings.joystickSpeed * w * settings.speed.clamped(0.1, 5))
    }

    /// Maps a normalised stick offset (1 = edge of travel) to a velocity
    /// fraction, with a radial dead zone and a gentle curve for precision.
    public static func joystick(offset o: Vec2, deadzone: Double) -> Vec2 {
        let mag = o.length
        guard mag > deadzone else { return .zero }
        let m = min((mag - deadzone) / max(1 - deadzone, 1e-6), 1)
        return o.normalized * pow(m, 1.6)
    }

    private func isFrozen(time: Double) -> Bool {
        if time < freezeUntil { return true }
        guard settings.holdSteadyWhileGesturing else { return false }
        var excluding = Set<HeadGesture>()
        // A held "click and hold" tilt is a drag: let the pointer move once
        // the press has settled.
        if let g = holdGesture, let began = holdBegan, time - began > 0.35 {
            excluding.insert(g)
        }
        return gestures.formingLevel(bindings: settings.headGestures, excluding: excluding) >= 0.5
    }

    private func updateScroll(_ p: Vec2, time: Double, out: inout [PointerCommand]) {
        if scrollAnchor == nil { scrollAnchor = p }
        guard let anchor = scrollAnchor else { return }
        var o = p - anchor
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

    // MARK: - Keys

    /// Feeds a click key. The pointer does not move while you press a key,
    /// which is what makes keys the steadiest way to click.
    public func key(_ event: KeyClickEvent, time: Double) -> [PointerCommand] {
        guard !suspended else { return [] }
        return performKeys(keyClicks.handle(event, time: time, keys: settings.clickKeys), time: time)
    }

    /// For diagnostics: click key decisions made, even while paused.
    public private(set) var keyDecisions = 0

    private func performKeys(_ outputs: [KeyClickOutput], time: Double) -> [PointerCommand] {
        guard !outputs.isEmpty else { return [] }
        keyDecisions += outputs.count
        var out: [PointerCommand] = []
        for o in outputs {
            switch o {
            case .tap:
                // A tap drops a drag that a gesture or the palette started.
                if dragButtonDown {
                    out += endDrag()
                    continue
                }
                guard !status.paused else { continue }
                // Press and release rather than a click, so two quick taps
                // count up into a real double click.
                out += [.press(.left, at: pointer), .release(.left, at: pointer), .feedback(.performed(.leftClick))]
                // Keep the spot still long enough for a second tap to land on it.
                freezeUntil = max(freezeUntil, time + 0.25)
            case .press:
                guard !status.paused, !dragButtonDown else { continue }
                dragButtonDown = true
                holdGesture = nil
                holdBegan = nil
                out += [.press(.left, at: pointer), .feedback(.dragStarted)]
            case .release:
                out += endDrag()
            case .rightClick:
                out += perform(.rightClick, time: time)
            case .doubleClick:
                out += perform(.doubleClick, time: time)
            case .dragToggle:
                out += perform(.dragToggle, time: time)
            }
        }
        refreshStatus()
        return out
    }

    // MARK: - Clock

    /// Advances the pointer. Call at display rate (about 60 Hz).
    /// - Parameter cursor: where the system cursor actually is right now.
    public func tick(time: Double, cursor: Vec2) -> [PointerCommand] {
        guard !suspended else { return [] }
        let dt = lastTick.map { (time - $0).clamped(0, 0.1) } ?? 0
        lastTick = time
        var out = performKeys(keyClicks.tick(time: time, keys: settings.clickKeys), time: time)

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
            neutral = nil
            dwell.reset()
            refreshStatus()
            return out
        }

        if status.scrolling, scrollVelocity != .zero, dt > 0 {
            out.append(.scroll(scrollVelocity * dt))
        }

        if status.paused || (!status.tracking && !dragButtonDown) {
            status.dwellProgress = 0
            refreshStatus()
            return out
        }

        if settings.motion == .joystick, !status.frozen, time >= yieldUntil, dt > 0 {
            target = environment.clamp(target + joystickVelocity * dt)
        }

        if dt > 0 {
            pointer = pointer + (target - pointer) * (1 - exp(-dt / glideTime))
            if pointer.distance(to: target) < 0.25 { pointer = target }
        }

        if time >= yieldUntil, pointer.distance(to: posted) >= 0.5 {
            out.append(.move(to: pointer, dragging: dragButtonDown))
            lastPosted = pointer
        }

        if settings.dwell.enabled, status.tracking, !status.scrolling {
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

    /// True when a tick would do nothing: no head motion, no held button, no
    /// scrolling and no key waiting to become a hold. The app slows its
    /// clock down then.
    public var isIdle: Bool {
        !status.tracking && !dragButtonDown && !status.scrolling && !keyClicks.isWaiting
    }

    // MARK: - Actions

    private func handle(_ events: [HeadGestureEvent], time: Double) -> [PointerCommand] {
        var out: [PointerCommand] = []
        for e in events {
            switch e {
            case let .began(g, startedAt):
                if g == .nod {
                    // The head went down and up again; put the pointer back
                    // where it was before the dip, then act there.
                    if let back = targetHistory.last(where: { $0.time <= startedAt })?.point ?? targetHistory.first?.point {
                        target = back
                        pointer = back
                        lastPosted = back
                        out.append(.move(to: back, dragging: dragButtonDown))
                    }
                    freezeUntil = max(freezeUntil, time + 0.2)
                }
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
                // Let the head settle before the pointer moves again.
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
            last = nil
            neutral = nil
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
        scrollAnchor = on ? filtered : nil
        scrollVelocity = .zero
        scrollRestSince = nil
        dwell.reset()
        if !on { last = nil }
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

    /// Puts the pointer back in the middle of the main display. In direct
    /// and joystick motion, the current head pose becomes the centre.
    public func recenter() {
        let display = environment.mappingDisplay
        switch settings.motion {
        case .relative:
            target = display.center
            pointer = target
        case .direct:
            neutral = filtered
            target = display.center
            pointer = target
        case .joystick:
            joystickNeutral = filtered
            joystickVelocity = .zero
        }
        dwell.reset()
    }

    private func refreshStatus() {
        status.pointer = pointer
        status.dragging = dragButtonDown
        status.activations = gestures.activations
        status.dwellAction = dwellOverride ?? settings.dwell.defaultAction
    }
}
