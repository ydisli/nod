import AppKit
import AVFoundation
import NodCore
import Observation
import SwiftUI

/// High frequency state for live visuals, kept apart from `AppModel` so a
/// settings screen does not re-render 30 times a second.
@MainActor @Observable
final class LiveState {
    var sample: FaceSample?
    var status = EngineStatus()
    var hud = HUDState()
    var fps: Double = 0
    var processingMs: Double = 0
    var detectionsPerSecond: Double = 0
    var cameraRunning = false
    /// AirPods input: the stream is running, the headphones are connected,
    /// and the latest pose (only while a view shows it).
    var headphonesRunning = false
    var headphonesConnected = false
    var head: HeadPose?

    /// The chosen source is running.
    var sourceRunning: Bool { cameraRunning || headphonesRunning }
}

@MainActor @Observable
final class AppModel {
    var settings: NodSettings {
        didSet {
            guard settings != oldValue, !isDemo else { return }
            pipeline.update(settings: settings)
            Store.save(settings, key: Store.settingsKey)
            if settings.hotKeysDiffer(from: oldValue) { registerHotKeys() }
            if settings.displayID != oldValue.displayID { refreshEnvironment() }
            if settings.clickKeys != oldValue.clickKeys { refreshKeyMonitor() }
            windows?.settingsChanged(from: oldValue)
        }
    }
    private(set) var profiles: [TrackingInput: CalibrationProfile]
    private(set) var gestureBaseline: GestureBaseline?

    /// Tracking switched on by the user.
    private(set) var isEnabled = false
    private(set) var isCalibrating = false
    /// Mirrors the palette window, set by the window manager.
    var isPaletteVisible = false
    let live = LiveState()

    private(set) var cameraPermission: PermissionStatus = .notDetermined
    private(set) var accessibilityPermission: PermissionStatus = .denied
    private(set) var motionPermission: PermissionStatus = .notDetermined
    private(set) var cameraError: String?
    private(set) var headphoneError: String?
    private(set) var cameraDevices: [CameraDevice] = []

    @ObservationIgnored weak var windows: WindowManager?
    /// Receives every face sample while a calibration runs.
    @ObservationIgnored var calibrationSink: ((FaceSample?) -> Void)?
    @ObservationIgnored private(set) var pipeline: TrackingPipeline!
    @ObservationIgnored private var frameClients: Set<String> = []
    @ObservationIgnored private var previewClients: Set<String> = []
    @ObservationIgnored private var paletteFrame: CGRect?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var permissionWatchers: Set<String> = []
    @ObservationIgnored private let isDemo: Bool
    /// Latest AirPods pose regardless of visible views, for diagnostics.
    @ObservationIgnored private var lastHead: HeadPose?
    @ObservationIgnored private lazy var keyMonitor = KeyClickMonitor { [weak self] event in
        self?.pipeline.key(event)
    }

    /// - Parameter demo: builds a model with fake live data and no side
    ///   effects (no hotkeys, no stored settings), for screenshots.
    init(demo: Bool = false) {
        isDemo = demo
        settings = demo ? NodSettings() : (Store.load(NodSettings.self, key: Store.settingsKey) ?? NodSettings())
        profiles = Store.load([TrackingInput: CalibrationProfile].self, key: Store.profilesKey) ?? [:]
        gestureBaseline = Store.load(GestureBaseline.self, key: Store.baselineKey)
        pipeline = TrackingPipeline(settings: settings) { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
        pipeline.setProfiles(profiles)
        pipeline.setGestureBaseline(gestureBaseline)
        refreshPermissions()
        refreshCameras()
        refreshEnvironment()
        if demo {
            enterDemoState()
            return
        }
        registerHotKeys()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshEnvironment() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        for name in [NSNotification.Name.AVCaptureDeviceWasConnected, .AVCaptureDeviceWasDisconnected] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshCameras() }
            }
        }
    }

    // MARK: - Tracking on and off

    var wasEnabledLastRun: Bool {
        UserDefaults.standard.bool(forKey: Store.enabledKey)
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        if on, !settings.input.usesCamera {
            // AirPods need no camera; macOS asks for Motion access itself.
            headphoneError = nil
            isEnabled = true
            if !isCalibrating {
                pipeline.setSuspended(false)
                pipeline.start()
            }
        } else if on {
            refreshPermissions()
            switch cameraPermission {
            case .granted:
                break
            case .notDetermined:
                Task {
                    if await Permissions.requestCamera() {
                        self.refreshPermissions()
                        self.setEnabled(true)
                    } else {
                        self.refreshPermissions()
                    }
                }
                return
            case .denied:
                windows?.showSettings(pane: .permissions)
                return
            }
            cameraError = nil
            isEnabled = true
            if !isCalibrating {
                pipeline.setSuspended(false)
                pipeline.start()
            }
        } else {
            isEnabled = false
            if !isCalibrating {
                if isPreviewing {
                    pipeline.setSuspended(true)
                } else {
                    pipeline.stop()
                }
            }
        }
        UserDefaults.standard.set(isEnabled, forKey: Store.enabledKey)
        refreshKeyMonitor()
        windows?.trackingChanged()
    }

    /// Listens for click keys only while tracking is on and keys are wanted.
    private func refreshKeyMonitor() {
        guard !isDemo else { return }
        if isEnabled, settings.clickKeys.enabled {
            keyMonitor.start()
        } else {
            keyMonitor.stop()
        }
    }

    func toggleEnabled() { setEnabled(!isEnabled) }

    // MARK: - Actions

    func perform(_ action: PointerAction) {
        if action == .togglePalette {
            windows?.togglePalette()
            return
        }
        pipeline.perform(action)
    }

    func recenter() { pipeline.perform(.recenter) }

    func chooseDwellAction(_ action: PointerAction) {
        pipeline.setDwellOverride(action)
    }

    func setInput(_ input: TrackingInput) {
        settings.input = input
    }

    // MARK: - Live frames

    /// Views that draw live tracking data register while visible so the
    /// pipeline only produces full rate reports when someone is watching.
    func retainFrames(_ client: String) {
        frameClients.insert(client)
        pipeline.setWantsFrames(true)
    }

    func releaseFrames(_ client: String) {
        frameClients.remove(client)
        if frameClients.isEmpty {
            pipeline.setWantsFrames(false)
            live.sample = nil
        }
    }

    /// Turns the camera on for a preview (gesture meters, camera settings)
    /// even when tracking is off. Pointer control stays suspended. Counted,
    /// because one screen can appear before the previous one disappears.
    func retainPreview(_ client: String) {
        let wasEmpty = previewClients.isEmpty
        previewClients.insert(client)
        guard wasEmpty, !isEnabled, !isCalibrating, !settings.input.usesCamera || cameraPermission == .granted else { return }
        pipeline.setSuspended(true)
        pipeline.start()
    }

    func releasePreview(_ client: String) {
        previewClients.remove(client)
        guard previewClients.isEmpty, !isEnabled, !isCalibrating else { return }
        pipeline.stop()
        pipeline.setSuspended(false)
    }

    private var isPreviewing: Bool { !previewClients.isEmpty }

    var debugClients: String {
        var line = String(format: "input=%@ fps=%.0f ms=%.2f detect/s=%.1f face=%@ ax=%@ ", settings.input.rawValue, live.fps, live.processingMs,
                          live.detectionsPerSecond, live.status.faceVisible ? "yes" : "no", Permissions.accessibility.isGranted ? "yes" : "no")
        if !settings.input.usesCamera {
            let deg = 180 / Double.pi
            line += String(format: "airpods=%@ motion=%@ ", live.headphonesConnected ? "connected" : "no", Permissions.motion.rawValue)
            if let h = lastHead {
                line += String(format: "yaw=%.1f pitch=%.1f roll=%.1f lean=%.1f ", h.yaw * deg, h.pitch * deg, h.roll * deg, live.status.headLean * deg)
            }
            if let e = headphoneError { line += "error=\"\(e)\" " }
        }
        line += "keys=\(keyMonitor.isRunning ? "on" : "off") keyEvents=\(keyMonitor.seen) "
        return line + "frames=\(frameClients.sorted()) previews=\(previewClients.sorted())"
    }

    // MARK: - Calibration

    func beginCalibration() {
        guard cameraPermission == .granted else {
            setEnabled(true)
            return
        }
        isCalibrating = true
        pipeline.setSuspended(true)
        if !isEnabled { pipeline.start() }
    }

    func endCalibration(profile: CalibrationProfile?, baseline: GestureBaseline?) {
        if let profile {
            profiles[profile.input] = profile
            Store.save(profiles, key: Store.profilesKey)
            pipeline.setProfiles(profiles)
            if settings.displayID != profile.displayID { settings.displayID = profile.displayID }
        }
        if let baseline {
            gestureBaseline = baseline
            Store.save(baseline, key: Store.baselineKey)
            pipeline.setGestureBaseline(baseline)
        }
        isCalibrating = false
        if isEnabled {
            pipeline.setSuspended(false)
        } else if profile != nil {
            setEnabled(true)
        } else if !isPreviewing {
            pipeline.stop()
            pipeline.setSuspended(false)
        }
    }

    func forgetCalibration(_ input: TrackingInput) {
        profiles[input] = nil
        Store.save(profiles, key: Store.profilesKey)
        pipeline.setProfiles(profiles)
    }

    func forgetGestureBaseline() {
        gestureBaseline = nil
        Store.remove(Store.baselineKey)
        pipeline.setGestureBaseline(nil)
    }

    // MARK: - Environment

    func paletteMoved(to frame: CGRect?) {
        paletteFrame = frame
        refreshEnvironment()
    }

    func refreshEnvironment() {
        let q = paletteFrame.map { Displays.quartzRect(fromCocoa: $0) }
        pipeline.setEnvironment(Displays.environment(preferred: settings.displayID, paletteFrame: q))
    }

    func refreshCameras() {
        cameraDevices = CameraDevice.available()
    }

    func refreshPermissions() {
        guard !isDemo else { return }
        cameraPermission = Permissions.camera
        accessibilityPermission = Permissions.accessibility
        motionPermission = Permissions.motion
    }

    /// Polls permissions while a screen that shows them is open, because
    /// macOS does not notify when the user flips a switch in System Settings.
    /// Counted per screen, so closing one does not stop another's polling.
    func watchPermissions(_ on: Bool, client: String = "default") {
        if on { permissionWatchers.insert(client) } else { permissionWatchers.remove(client) }
        if permissionWatchers.isEmpty {
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else if permissionTimer == nil {
            refreshPermissions()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPermissions() }
            }
        }
    }

    /// Returns the state actually in effect afterwards.
    @discardableResult
    func setLaunchAtLogin(_ on: Bool) -> Bool {
        try? LaunchAtLogin.set(on)
        return LaunchAtLogin.isEnabled
    }

    // MARK: - Demo

    /// Fake but plausible live data: the demo face, tracking, a gesture half
    /// formed, a calibrated nose.
    private func enterDemoState() {
        isEnabled = true
        cameraPermission = .granted
        accessibilityPermission = .granted
        live.cameraRunning = true
        live.fps = 30
        live.processingMs = 3.8
        var mesh = DemoFace.posed(yaw: -0.12, pitch: 0.05, mouth: 0.45)
        // The demo mesh is a unit square; present it inside a 4:3 frame.
        func place(_ v: Vec2) -> Vec2 { Vec2(0.3 + v.x * 0.4, 0.2 + v.y * 0.4 * 4 / 3) }
        mesh.contour = mesh.contour.map(place); mesh.leftEye = mesh.leftEye.map(place); mesh.rightEye = mesh.rightEye.map(place)
        mesh.leftBrow = mesh.leftBrow.map(place); mesh.rightBrow = mesh.rightBrow.map(place); mesh.nose = mesh.nose.map(place)
        mesh.noseCrest = mesh.noseCrest.map(place); mesh.outerLips = mesh.outerLips.map(place); mesh.innerLips = mesh.innerLips.map(place)
        mesh.pupils = mesh.pupils.map(place); mesh.noseTip = place(mesh.noseTip)
        live.sample = FaceSample(time: 0, imageSize: Vec2(640, 480), nose: mesh.noseTip, faceScale: 0.12, faceCenter: Vec2(0.5, 0.45),
                                 gaze: .zero, headAngle: .zero, metrics: .zero, confidence: 0.95, brightness: 0.5, mesh: mesh)
        var status = EngineStatus()
        status.faceVisible = true
        status.activations = [.mouthOpen: 0.62, .browRaise: 0.18, .longBlink: 0.04]
        live.status = status
        settings.dwell.enabled = true
        profiles[.nose] = CalibrationProfile(
            input: .nose, createdAt: Date().addingTimeInterval(-3600 * 26), displaySize: Vec2(1512, 982), displayID: nil,
            mapping: PointerCalibration(basis: .affine, featureMean: [0, 0], featureScale: [1, 1], coefficientsX: [0, 0, 0],
                                        coefficientsY: [0, 0, 0], meanError: 0.024, sampleCount: 243),
            neutralNose: Vec2(0.5, 0.45), neutralFaceScale: 0.12, travel: Vec2(0.6, 0.45))
    }

    // MARK: - Hotkeys

    func registerHotKeys() {
        let center = HotKeyCenter.shared
        center.removeAll()
        center.register(settings.toggleHotKey) { [weak self] in self?.toggleEnabled() }
        center.register(settings.recenterHotKey) { [weak self] in self?.recenter() }
        center.register(settings.calibrateHotKey) { [weak self] in self?.windows?.startCalibration() }
    }

    // MARK: - Pipeline events

    private func handle(_ event: PipelineEvent) {
        switch event {
        case let .frame(report):
            if !frameClients.isEmpty {
                live.sample = report.sample
                live.head = report.head
            }
            lastHead = report.head
            calibrationSink?(report.sample)
            live.status = report.status
            live.fps = report.fps
            live.processingMs = report.processingMs
            live.detectionsPerSecond = report.detectionsPerSecond
        case let .hud(hud):
            live.hud = hud
            windows?.hudChanged(hud)
        case let .feedback(f):
            if settings.playSounds { Sounds.play(for: f) }
            windows?.feedback(f)
        case let .camera(running, error):
            live.cameraRunning = running
            if let error { cameraError = error }
            if !running { live.sample = nil }
            windows?.trackingChanged()
        case let .headphones(running, connected, error):
            live.headphonesRunning = running
            live.headphonesConnected = connected
            headphoneError = error
            if !running || !connected {
                live.head = nil
                lastHead = nil
            }
            windows?.trackingChanged()
        }
    }
}

extension NodSettings {
    func hotKeysDiffer(from other: NodSettings) -> Bool {
        toggleHotKey != other.toggleHotKey || recenterHotKey != other.recenterHotKey || calibrateHotKey != other.calibrateHotKey
    }
}

/// Tiny JSON-in-UserDefaults store.
enum Store {
    static let settingsKey = "nod.settings.v1"
    static let profilesKey = "nod.profiles.v1"
    static let baselineKey = "nod.baseline.v1"
    static let enabledKey = "nod.enabled"

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func remove(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
