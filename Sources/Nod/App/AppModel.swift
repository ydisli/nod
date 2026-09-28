import AppKit
import NodCore
import Observation
import SwiftUI

/// Fast changing values for the head dial and gesture meters. Kept in their
/// own property so only the small views that draw them redraw.
struct LiveMotion: Equatable {
    var offset: Vec2 = .zero
    var lean: Double = 0
    var activations: [HeadGesture: Double] = [:]
}

/// Live state for visuals, kept apart from `AppModel` so a settings screen
/// does not re-render while the head moves. Every property is only written
/// when its value changes, because each write redraws whatever reads it.
@MainActor @Observable
final class LiveState {
    /// Engine state without the fast parts (see `motion`).
    var status = EngineStatus()
    var motion = LiveMotion()
    /// Head poses per second arriving from the headphones.
    var rate: Double = 0
    var processingMs: Double = 0
    var running = false
    var connected = false
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

    /// Tracking switched on by the user.
    private(set) var isEnabled = false
    /// Mirrors the palette window, set by the window manager.
    var isPaletteVisible = false
    let live = LiveState()

    private(set) var accessibilityPermission: PermissionStatus = .denied
    private(set) var motionPermission: PermissionStatus = .notDetermined
    private(set) var headphoneError: String?

    @ObservationIgnored weak var windows: WindowManager?
    @ObservationIgnored private(set) var pipeline: TrackingPipeline!
    @ObservationIgnored private var frameClients: Set<String> = []
    @ObservationIgnored private var previewClients: Set<String> = []
    @ObservationIgnored private var paletteFrame: CGRect?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var permissionWatchers: Set<String> = []
    @ObservationIgnored private let isDemo: Bool
    /// Latest pose regardless of visible views, for diagnostics.
    @ObservationIgnored private var lastHead: HeadPose?
    /// For diagnostics: presses and releases of recorded click shortcuts.
    @ObservationIgnored private(set) var shortcutEvents = 0
    @ObservationIgnored private lazy var keyMonitor = KeyClickMonitor { [weak self] event in
        self?.pipeline.key(event)
    }

    /// - Parameter demo: builds a model with fake live data and no side
    ///   effects (no hotkeys, no stored settings), for screenshots.
    init(demo: Bool = false) {
        isDemo = demo
        settings = demo ? NodSettings() : (Store.load(NodSettings.self, key: Store.settingsKey) ?? NodSettings())
        pipeline = TrackingPipeline(settings: settings) { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
        refreshPermissions()
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
    }

    // MARK: - Tracking on and off

    var wasEnabledLastRun: Bool {
        UserDefaults.standard.bool(forKey: Store.enabledKey)
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if on {
            // macOS asks for Motion access itself the first time.
            headphoneError = nil
            pipeline.setSuspended(false)
            pipeline.start()
        } else if isPreviewing {
            pipeline.setSuspended(true)
        } else {
            pipeline.stop()
        }
        UserDefaults.standard.set(isEnabled, forKey: Store.enabledKey)
        refreshKeyMonitor()
        windows?.trackingChanged()
    }

    func toggleEnabled() { setEnabled(!isEnabled) }

    /// Listens for click keys only while tracking is on and keys are wanted.
    /// Recorded click shortcuts are global hotkeys, registered only then too.
    private func refreshKeyMonitor() {
        guard !isDemo else { return }
        let center = HotKeyCenter.shared
        center.removeAll(group: "click")
        guard isEnabled, settings.clickKeys.enabled else {
            keyMonitor.stop()
            return
        }
        keyMonitor.start()
        for spec in settings.clickKeys.shortcuts {
            let trigger = ClickTrigger.shortcut(spec)
            center.register(spec, group: "click", onRelease: { [weak self] in
                self?.shortcutEvents += 1
                self?.pipeline.key(.up(trigger))
            }) { [weak self] in
                self?.shortcutEvents += 1
                self?.pipeline.key(.down(trigger))
            }
        }
    }

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

    // MARK: - Live frames

    /// Views that draw live data register while visible so the pipeline only
    /// sends frequent reports when someone is watching.
    func retainFrames(_ client: String) {
        frameClients.insert(client)
        pipeline.setWantsFrames(true)
    }

    func releaseFrames(_ client: String) {
        frameClients.remove(client)
        if frameClients.isEmpty { pipeline.setWantsFrames(false) }
    }

    /// Reads the AirPods for a preview (gesture meters) even when tracking is
    /// off. Pointer control stays suspended. Counted, because one screen can
    /// appear before the previous one disappears.
    func retainPreview(_ client: String) {
        let wasEmpty = previewClients.isEmpty
        previewClients.insert(client)
        guard wasEmpty, !isEnabled else { return }
        pipeline.setSuspended(true)
        pipeline.start()
    }

    func releasePreview(_ client: String) {
        previewClients.remove(client)
        guard previewClients.isEmpty, !isEnabled else { return }
        pipeline.stop()
        pipeline.setSuspended(false)
    }

    private var isPreviewing: Bool { !previewClients.isEmpty }

    var debugClients: String {
        let deg = 180 / Double.pi
        var line = String(format: "rate=%.0f ms=%.3f tracking=%@ ax=%@ airpods=%@ motion=%@ ", live.rate, live.processingMs,
                          live.status.tracking ? "yes" : "no", Permissions.accessibility.isGranted ? "yes" : "no",
                          live.connected ? "connected" : "no", Permissions.motion.rawValue)
        if let h = lastHead {
            line += String(format: "yaw=%.1f pitch=%.1f roll=%.1f ", h.yaw * deg, h.pitch * deg, h.roll * deg)
        }
        if let e = headphoneError { line += "error=\"\(e)\" " }
        line += "keys=\(keyMonitor.isRunning ? "on" : "off") keyEvents=\(keyMonitor.seen) shortcutEvents=\(shortcutEvents) "
        return line + "frames=\(frameClients.sorted()) previews=\(previewClients.sorted())"
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

    func refreshPermissions() {
        guard !isDemo else { return }
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

    /// Fake but plausible live data, for screenshots.
    private func enterDemoState() {
        isEnabled = true
        accessibilityPermission = .granted
        motionPermission = .granted
        live.running = true
        live.connected = true
        live.rate = 50
        live.processingMs = 0.01
        live.motion = LiveMotion(offset: Vec2(0.38, -0.22), lean: -0.12, activations: [.tiltLeft: 0.66, .tiltRight: 0])
        var status = EngineStatus()
        status.tracking = true
        live.status = status
        settings.dwell.enabled = true
    }

    // MARK: - Hotkeys

    func registerHotKeys() {
        let center = HotKeyCenter.shared
        center.removeAll(group: "app")
        center.register(settings.toggleHotKey) { [weak self] in self?.toggleEnabled() }
        center.register(settings.recenterHotKey) { [weak self] in self?.recenter() }
    }

    // MARK: - Pipeline events

    private func handle(_ event: PipelineEvent) {
        switch event {
        case let .frame(report):
            lastHead = report.head
            // The slow parts of the status, written only when they change.
            var coarse = report.status
            coarse.pointer = .zero
            coarse.dwellProgress = 0
            coarse.activations = [:]
            coarse.headOffset = .zero
            coarse.headLean = 0
            if live.status != coarse { live.status = coarse }
            let rate = report.rate.rounded()
            if live.rate != rate { live.rate = rate }
            let ms = (report.processingMs * 100).rounded() / 100
            if live.processingMs != ms { live.processingMs = ms }
            guard !frameClients.isEmpty else { return }
            let s = report.status
            let motion = LiveMotion(offset: s.headOffset, lean: s.headLean, activations: s.activations)
            if live.motion != motion { live.motion = motion }
        case let .hud(hud):
            windows?.hudChanged(hud)
        case let .feedback(f):
            if settings.playSounds { Sounds.play(for: f) }
            windows?.feedback(f)
        case let .headphones(running, connected, error):
            if live.running != running { live.running = running }
            if live.connected != connected { live.connected = connected }
            if headphoneError != error { headphoneError = error }
            if !running || !connected { lastHead = nil }
            windows?.trackingChanged()
        }
    }
}

extension NodSettings {
    func hotKeysDiffer(from other: NodSettings) -> Bool {
        toggleHotKey != other.toggleHotKey || recenterHotKey != other.recenterHotKey
    }
}

/// Tiny JSON-in-UserDefaults store.
enum Store {
    static let settingsKey = "nod.settings.v1"
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
}
