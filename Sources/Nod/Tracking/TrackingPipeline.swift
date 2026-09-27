@preconcurrency import AVFoundation
import Foundation
import NodCore

struct CameraDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String

    static func available() -> [CameraDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }
}

/// A snapshot for the UI, sent after processed frames.
struct FrameReport: Sendable {
    var sample: FaceSample?
    /// Latest AirPods pose, when that is the input.
    var head: HeadPose?
    var status: EngineStatus
    var fps: Double
    var processingMs: Double
    /// Full face detections per second (the expensive step), for diagnostics.
    var detectionsPerSecond: Double = 0
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
    var faceVisible = false
}

enum PipelineEvent: Sendable {
    case frame(FrameReport)
    case hud(HUDState)
    case feedback(EngineFeedback)
    case camera(running: Bool, error: String?)
    case headphones(running: Bool, connected: Bool, error: String?)
}

/// Owns the camera, Vision, the AirPods motion stream and the pointer engine.
///
/// Everything inside runs on one serial queue: camera frames and head poses
/// arrive on it, the 60 Hz pointer clock fires on it, and public methods hop
/// onto it. Results go out through `sink`, which the app forwards to the main
/// actor. Only one source runs at a time, picked by the input setting.
final class TrackingPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.slipperysign.nod.tracking", qos: .userInteractive)
    /// Exposed for preview layers only; configured on the tracking queue.
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private let tracker = FaceTracker()
    private let engine: PointerEngine
    private let driver = MouseDriver()
    private let sink: @Sendable (PipelineEvent) -> Void

    // Queue-confined state.
    private var settings: NodSettings
    private var running = false
    private var clock: DispatchSourceTimer?
    private var wantsFrames = false
    private var processedTimes: [Double] = []
    private var processingAverage = 0.0
    private var lastProcessed = 0.0
    private var lastFaceSeen = 0.0
    private var frameIndex = 0
    private var lastHUD = HUDState()
    private var lastQuietReport = 0.0
    private var runtimeErrorObserver: NSObjectProtocol?
    private var detectionMark: (time: Double, count: Int) = (0, 0)
    private var detectionRate = 0.0
    private var headphones: HeadphoneMotion?
    private var usingHeadphones = false
    private var headConnected = false
    private var lastHeadTime = 0.0
    private var lastHeadCheck = 0.0

    init(settings: NodSettings, sink: @escaping @Sendable (PipelineEvent) -> Void) {
        self.settings = settings
        self.engine = PointerEngine(settings: settings)
        self.sink = sink
        super.init()
        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { [weak self] note in
            let err = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.sink(.camera(running: false, error: err?.localizedDescription ?? "The camera stopped unexpectedly."))
        }
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
            let old = self.settings
            self.settings = new
            self.engine.settings = new
            if self.running, old.input.usesCamera != new.input.usesCamera {
                // Swap camera and AirPods without stopping pointer control.
                self.stopSources()
                self.startSource()
                return
            }
            let cameraChanged = old.cameraID != new.cameraID || old.efficiency != new.efficiency
            if self.running, cameraChanged, new.input.usesCamera {
                do {
                    try self.configureSession()
                } catch {
                    self.sink(.camera(running: self.session.isRunning, error: error.localizedDescription))
                }
            }
        }
    }

    func setProfiles(_ profiles: [TrackingInput: CalibrationProfile]) {
        queue.async {
            for input in TrackingInput.allCases where input != .hybrid {
                self.engine.setProfile(profiles[input], for: input)
            }
        }
    }

    func setGestureBaseline(_ baseline: GestureBaseline?) {
        queue.async { self.engine.setGestureBaseline(baseline) }
    }

    func setEnvironment(_ env: EngineEnvironment) {
        queue.async { self.engine.environment = env }
    }

    /// Full rate reports with face samples, for visible UI. Otherwise the
    /// pipeline only sends a short status twice a second.
    func setWantsFrames(_ on: Bool) {
        queue.async { self.wantsFrames = on }
    }

    /// Suspends pointer control (calibration) while the camera keeps running.
    func setSuspended(_ on: Bool) {
        queue.async {
            if on { self.driver.releaseAll() }
            self.engine.suspended = on
            if !on { self.engine.reset(cursor: MouseDriver.cursorLocation()) }
        }
    }

    func perform(_ action: PointerAction) {
        queue.async {
            self.execute(self.engine.perform(action, time: Self.now()))
            self.publishHUD()
        }
    }

    /// A click key went down or up, or another key was pressed.
    func key(_ event: KeyClickEvent) {
        queue.async {
            guard self.running else { return }
            let button = self.settings.clickKeys.leftButton
            switch event {
            case let .down(k) where k == button: self.driver.suppressedFlags = k.eventFlags
            case let .up(k) where k == button: self.driver.suppressedFlags = []
            default: break
            }
            self.execute(self.engine.key(event, time: Self.now()))
            self.publishHUD()
        }
    }

    func setDwellOverride(_ action: PointerAction?) {
        queue.async {
            self.engine.setDwellOverride(action)
            self.publishHUD()
        }
    }

    // MARK: - Camera

    private func startOnQueue() {
        guard !running else { return }
        running = true
        guard startSource() else {
            running = false
            return
        }
        engine.reset(cursor: MouseDriver.cursorLocation())
        startClock()
    }

    /// Starts the camera or the AirPods stream, whichever the input needs.
    @discardableResult
    private func startSource() -> Bool {
        processedTimes.removeAll()
        if settings.input.usesCamera {
            do {
                try configureSession()
            } catch {
                sink(.camera(running: false, error: error.localizedDescription))
                return false
            }
            session.startRunning()
            guard session.isRunning else {
                sink(.camera(running: false, error: "The camera could not be started. Another app may be using it."))
                return false
            }
            tracker.reset()
            lastFaceSeen = Self.now()
            sink(.camera(running: true, error: nil))
        } else {
            if headphones == nil {
                headphones = HeadphoneMotion(queue: queue) { [weak self] event in self?.headphoneEvent(event) }
            }
            usingHeadphones = true
            lastHeadTime = 0
            headphones?.start()
            sink(.headphones(running: true, connected: headConnected, error: nil))
        }
        return true
    }

    private func stopSources() {
        if session.isRunning {
            session.stopRunning()
            sink(.camera(running: false, error: nil))
        }
        if usingHeadphones {
            headphones?.stop()
            usingHeadphones = false
            sink(.headphones(running: false, connected: headConnected, error: nil))
        }
        // Nothing is tracked any more: let gestures end and buttons go up.
        execute(engine.trackingStopped(time: Self.now()))
    }

    private func stopOnQueue() {
        clock?.cancel()
        clock = nil
        stopSources()
        running = false
        driver.releaseAll()
        processedTimes.removeAll()
        lastHUD = HUDState()
        sink(.hud(lastHUD))
    }

    private enum CameraError: LocalizedError {
        case noCamera
        case cannotAdd
        var errorDescription: String? {
            switch self {
            case .noCamera: "No camera found. Connect one or pick another in Settings."
            case .cannotAdd: "The camera is busy or not supported."
            }
        }
    }

    private func configureSession() throws {
        let device = settings.cameraID.flatMap { AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video)
        guard let device else { throw CameraError.noCamera }

        session.beginConfiguration()
        let preset: AVCaptureSession.Preset = settings.efficiency == .precision ? .hd1280x720 : .vga640x480
        session.sessionPreset = session.canSetSessionPreset(preset) ? preset : .medium

        if input?.device.uniqueID != device.uniqueID {
            if let old = input { session.removeInput(old) }
            let newInput = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(newInput) else {
                session.commitConfiguration()
                throw CameraError.cannotAdd
            }
            session.addInput(newInput)
            input = newInput
        }
        if !session.outputs.contains(output) {
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                throw CameraError.cannotAdd
            }
            session.addOutput(output)
        }
        // Ask for exactly what the camera produces. Requesting another format
        // (even 420f versus the native 420v) makes AVFoundation convert every
        // frame through Core Image, which cost more CPU than Vision itself.
        let native = CMFormatDescriptionGetMediaSubType(device.activeFormat.formatDescription)
        let biPlanar: Set<OSType> = [kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        let format = biPlanar.contains(native) ? native : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: format]
        session.commitConfiguration()

        // Pin the frame rate when the camera supports it; otherwise frames
        // are thinned out in software.
        let fps = Double(settings.efficiency.framesPerSecond)
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= fps && fps <= $0.maxFrameRate }),
           (try? device.lockForConfiguration()) != nil {
            let d = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = d
            device.activeVideoMaxFrameDuration = d
            device.unlockForConfiguration()
        }
    }

    // MARK: - Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard running, !usingHeadphones, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = Self.now()
        frameIndex += 1

        // Nobody in front of the camera for a while: look only every third
        // frame until someone comes back.
        if now - lastFaceSeen > 3, frameIndex % 3 != 0 { return }
        let interval = 1.0 / Double(settings.efficiency.framesPerSecond)
        if now - lastProcessed < interval * 0.8 { return }
        lastProcessed = now

        let started = Self.now()
        let sample = tracker.process(pixelBuffer, time: now, detectEvery: settings.efficiency.detectEvery)
        execute(engine.ingest(sample, time: now))
        let ms = (Self.now() - started) * 1000
        processingAverage = processingAverage == 0 ? ms : processingAverage * 0.9 + ms * 0.1

        if sample != nil { lastFaceSeen = now }
        processedTimes.append(now)
        processedTimes.removeAll { now - $0 > 1 }

        if now - detectionMark.time >= 2 {
            detectionRate = Double(tracker.detections - detectionMark.count) / (now - detectionMark.time)
            detectionMark = (now, tracker.detections)
        }

        if wantsFrames || now - lastQuietReport > 0.5 {
            lastQuietReport = now
            sink(.frame(FrameReport(sample: wantsFrames ? sample : nil, status: engine.status,
                                    fps: Double(processedTimes.count), processingMs: processingAverage,
                                    detectionsPerSecond: detectionRate)))
        }
    }

    // MARK: - AirPods

    private func headphoneEvent(_ event: HeadphoneMotion.Event) {
        guard usingHeadphones else { return }
        switch event {
        case let .pose(pose):
            if !headConnected {
                headConnected = true
                sink(.headphones(running: true, connected: true, error: nil))
            }
            let now = Self.now()
            lastHeadTime = now
            let started = Self.now()
            execute(engine.ingest(head: pose, time: now))
            let ms = (Self.now() - started) * 1000
            processingAverage = processingAverage == 0 ? ms : processingAverage * 0.9 + ms * 0.1
            processedTimes.append(now)
            processedTimes.removeAll { now - $0 > 1 }
            if wantsFrames || now - lastQuietReport > 0.5 {
                lastQuietReport = now
                sink(.frame(FrameReport(sample: nil, head: pose, status: engine.status,
                                        fps: Double(processedTimes.count), processingMs: processingAverage)))
            }
        case let .connected(on):
            headConnected = on
            if on, Self.now() - lastHeadTime > 1 {
                // Ask again: a request made before the headphones connected
                // may never start sending.
                headphones?.restartMotion()
            }
            sink(.headphones(running: true, connected: on, error: nil))
        case let .failed(message):
            // The next pose that arrives clears the error.
            headConnected = false
            sink(.headphones(running: true, connected: false, error: message))
        }
    }

    /// AirPods send nothing when they leave the ears. Tell the engine, so the
    /// pointer stops and a held button is released in time.
    private func checkHeadphonesQuiet(now: Double) {
        guard usingHeadphones, now - lastHeadCheck > 0.1 else { return }
        lastHeadCheck = now
        guard now - lastHeadTime > 0.4 else { return }
        execute(engine.ingest(head: nil, time: now))
        if now - lastQuietReport > 0.5 {
            lastQuietReport = now
            processedTimes.removeAll()
            sink(.frame(FrameReport(sample: nil, head: nil, status: engine.status, fps: 0, processingMs: processingAverage)))
        }
    }

    // MARK: - Clock

    private func startClock() {
        clock?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(16_666_667), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        clock = timer
    }

    private func tick() {
        guard running else { return }
        let now = Self.now()
        checkHeadphonesQuiet(now: now)
        execute(engine.tick(time: now, cursor: MouseDriver.cursorLocation()))
        publishHUD()
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
        if usingHeadphones {
            for g in [HeadGesture.tiltLeft, .tiltRight] where settings.binding(for: g).enabled {
                level = max(level, s.headActivations[g] ?? 0)
            }
        } else {
            for (g, b) in settings.gestures where b.enabled {
                level = max(level, s.activations[g] ?? 0)
            }
        }
        let hud = HUDState(
            dwellProgress: (s.dwellProgress * 60).rounded() / 60,
            dwellAction: s.dwellAction,
            dragging: s.dragging,
            scrolling: s.scrolling,
            paused: s.paused,
            frozen: s.frozen,
            gestureLevel: (min(level, 1.2) * 20).rounded() / 20,
            faceVisible: s.faceVisible
        )
        if hud != lastHUD {
            lastHUD = hud
            sink(.hud(hud))
        }
    }

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }
}
