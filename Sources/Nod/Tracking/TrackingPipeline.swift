import Foundation
import NodCore

/// A snapshot for the UI.
struct FrameReport: Sendable {
    var head: HeadPose?
    var status: EngineStatus
    /// Head poses per second arriving from the headphones.
    var rate: Double
    var processingMs: Double
    var keyDecisions = 0
}

/// What the on-screen halo around the pointer needs to show.
struct HUDState: Sendable, Equatable {
    var dwellProgress: Double = 0
    var dwellAction: PointerAction = .leftClick
    var dragging = false
    var scrolling = false
    var paused = false
    var frozen = false
    var gestureLevel: Double = 0
    var tracking = false
}

enum PipelineEvent: Sendable {
    case frame(FrameReport)
    case hud(HUDState)
    case feedback(EngineFeedback)
    case headphones(running: Bool, connected: Bool, error: String?)
}

/// Owns the AirPods motion stream and the pointer engine.
///
/// Everything inside runs on one serial queue: head poses arrive on it, the
/// pointer clock fires on it, and public methods hop onto it. Results go out
/// through `sink`, which the app forwards to the main actor.
///
/// Kept deliberately cheap: the clock runs at 60 Hz only while head motion
/// arrives (4 Hz otherwise), and the UI hears from it at most 10 times a
/// second while something on screen shows live data, twice a second if not.
final class TrackingPipeline: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.slipperysign.nod.tracking", qos: .userInteractive)
    private let engine: PointerEngine
    private let driver = MouseDriver()
    private let sink: @Sendable (PipelineEvent) -> Void

    // Queue-confined state.
    private var settings: NodSettings
    private var running = false
    private var clock: DispatchSourceTimer?
    private var clockFast = false
    private var wantsFrames = false
    private var arrivals: [Double] = []
    private var processingAverage = 0.0
    private var lastReport = 0.0
    private var lastHUD = HUDState()
    private var headphones: HeadphoneMotion?
    private var simulator: DispatchSourceTimer?
    private var connected = false
    private var lastHeadTime = 0.0
    private var lastHeadCheck = 0.0

    /// Developer option: `NOD_SIMULATE_HEAD=1` feeds made-up head motion
    /// instead of AirPods, to measure CPU use without wearing them.
    private static let simulate = ProcessInfo.processInfo.environment["NOD_SIMULATE_HEAD"] == "1"

    init(settings: NodSettings, sink: @escaping @Sendable (PipelineEvent) -> Void) {
        self.settings = settings
        self.engine = PointerEngine(settings: settings)
        self.sink = sink
    }

    // MARK: - Control (callable from any thread)

    func start() {
        queue.async { self.startOnQueue() }
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    /// Stops and waits, so no mouse button is left pressed when the app quits.
    func stopAndWait() {
        queue.sync { self.stopOnQueue() }
    }

    func update(settings new: NodSettings) {
        queue.async {
            self.settings = new
            self.engine.settings = new
        }
    }

    func setEnvironment(_ env: EngineEnvironment) {
        queue.async { self.engine.environment = env }
    }

    /// Live reports for visible UI (meters, the head dial).
    func setWantsFrames(_ on: Bool) {
        queue.async { self.wantsFrames = on }
    }

    /// Suspends pointer control (previews) while head motion keeps flowing.
    func setSuspended(_ on: Bool) {
        queue.async {
            if on { self.driver.releaseAll() }
            self.engine.suspended = on
            if !on { self.engine.reset(cursor: self.driver.cursorLocation()) }
        }
    }

    func perform(_ action: PointerAction) {
        queue.async {
            // Off means off: no toast or sound for a pointer that is not moving.
            guard self.running else { return }
            self.execute(self.engine.perform(action, time: Self.now()))
            self.publishHUD()
        }
    }

    func setDwellOverride(_ action: PointerAction?) {
        queue.async {
            self.engine.setDwellOverride(action)
            self.publishHUD()
        }
    }

    /// A click key went down or up, or another key was pressed.
    func key(_ event: KeyClickEvent) {
        queue.async {
            guard self.running else { return }
            if case let .down(t) = event { self.driver.suppressedFlags = t.eventFlags }
            self.execute(self.engine.key(event, time: Self.now()))
            // Only now: a tap clicks on release, with the keys still held.
            if case .up = event { self.driver.suppressedFlags = [] }
            // A key held down must be watched closely to turn into a drag.
            self.setClock(fast: true)
            self.publishHUD()
        }
    }

    // MARK: - Source

    private func startOnQueue() {
        guard !running else { return }
        running = true
        lastHeadTime = 0
        arrivals.removeAll()
        engine.reset(cursor: driver.cursorLocation())
        if Self.simulate {
            startSimulator()
        } else {
            if headphones == nil {
                headphones = HeadphoneMotion(queue: queue) { [weak self] event in self?.headphoneEvent(event) }
            }
            headphones?.start()
        }
        setClock(fast: false)
        sink(.headphones(running: true, connected: connected, error: nil))
    }

    private func stopOnQueue() {
        guard running else { return }
        clock?.cancel()
        clock = nil
        simulator?.cancel()
        simulator = nil
        headphones?.stop()
        running = false
        // Nothing is tracked any more: let gestures end and buttons go up.
        execute(engine.trackingStopped(time: Self.now()))
        driver.releaseAll()
        arrivals.removeAll()
        lastHUD = HUDState()
        sink(.hud(lastHUD))
        sink(.headphones(running: false, connected: connected, error: nil))
    }

    private func headphoneEvent(_ event: HeadphoneMotion.Event) {
        guard running else { return }
        switch event {
        case let .pose(p):
            received(p)
        case let .connected(on):
            connected = on
            if on, Self.now() - lastHeadTime > 1 {
                // Ask again: a request made before the headphones connected
                // may never start sending.
                headphones?.restartMotion()
            }
            sink(.headphones(running: true, connected: on, error: nil))
        case let .failed(message):
            // The next pose that arrives clears the error.
            connected = false
            sink(.headphones(running: true, connected: false, error: message))
        }
    }

    private func received(_ pose: HeadPose) {
        let now = Self.now()
        if !connected {
            connected = true
            sink(.headphones(running: true, connected: true, error: nil))
        }
        lastHeadTime = now
        setClock(fast: true)
        let started = Self.now()
        execute(engine.ingest(head: pose, time: now))
        let ms = (Self.now() - started) * 1000
        processingAverage = processingAverage == 0 ? ms : processingAverage * 0.95 + ms * 0.05
        arrivals.append(now)
        if arrivals.count > 120 { arrivals.removeFirst(arrivals.count - 120) }
        report(pose, now: now)
    }

    private func report(_ pose: HeadPose?, now: Double) {
        let interval = wantsFrames ? 0.1 : 0.5
        guard now - lastReport >= interval else { return }
        lastReport = now
        let recent = arrivals.filter { now - $0 <= 1 }.count
        sink(.frame(FrameReport(head: pose, status: engine.status, rate: Double(recent), processingMs: processingAverage,
                                keyDecisions: engine.keyDecisions)))
    }

    /// AirPods send nothing when they leave the ears. Tell the engine, so the
    /// pointer stops and a held button is released in time.
    private func checkQuiet(now: Double) {
        guard now - lastHeadCheck > 0.1 else { return }
        lastHeadCheck = now
        guard now - lastHeadTime > 0.4 else { return }
        execute(engine.ingest(head: nil, time: now))
        report(nil, now: now)
    }

    // MARK: - Simulation

    private func startSimulator() {
        let t0 = Self.now()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            let t = Self.now() - t0
            // Slow looks around the screen with a little sensor noise.
            let yaw = 0.12 * sin(t * 0.7) + 0.05 * sin(t * 1.9) + Double.random(in: -0.002...0.002)
            let pitch = 0.06 * sin(t * 0.5 + 1) + Double.random(in: -0.002...0.002)
            let roll = 0.03 * sin(t * 0.3) + Double.random(in: -0.002...0.002)
            self?.received(HeadPose(yaw: yaw, pitch: pitch, roll: roll))
        }
        timer.resume()
        simulator = timer
    }

    // MARK: - Clock

    /// 60 Hz while the pointer can move, 4 Hz while nothing arrives.
    private func setClock(fast: Bool) {
        guard running, clock == nil || fast != clockFast else { return }
        clock?.cancel()
        clockFast = fast
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval: DispatchTimeInterval = fast ? .nanoseconds(16_666_667) : .milliseconds(250)
        timer.schedule(deadline: .now(), repeating: interval, leeway: fast ? .milliseconds(2) : .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        clock = timer
    }

    private func tick() {
        guard running else { return }
        let now = Self.now()
        checkQuiet(now: now)
        execute(engine.tick(time: now, cursor: driver.cursorLocation()))
        publishHUD()
        if clockFast, engine.isIdle, now - lastHeadTime > 1 { setClock(fast: false) }
    }

    private func execute(_ commands: [PointerCommand]) {
        for c in commands {
            if case let .feedback(f) = c {
                sink(.feedback(f))
            } else {
                driver.execute(c)
            }
        }
    }

    private func publishHUD() {
        let s = engine.status
        var level = 0.0
        for g in [HeadGesture.tiltLeft, .tiltRight] where settings.binding(for: g).enabled {
            level = max(level, s.activations[g] ?? 0)
        }
        // Coarse steps: the halo only needs to look right, and every change
        // costs a redraw on the main thread.
        let hud = HUDState(
            dwellProgress: (s.dwellProgress * 30).rounded() / 30,
            dwellAction: s.dwellAction,
            dragging: s.dragging,
            scrolling: s.scrolling,
            paused: s.paused,
            frozen: s.frozen,
            gestureLevel: (min(level, 1.2) * 10).rounded() / 10,
            tracking: s.tracking
        )
        if hud != lastHUD {
            lastHUD = hud
            sink(.hud(hud))
        }
    }

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }
}
