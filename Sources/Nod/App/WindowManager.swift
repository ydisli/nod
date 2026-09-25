import AppKit
import NodCore
import SwiftUI

/// Owns every window and the menu bar item.
@MainActor
final class WindowManager: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let model: AppModel
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let router = SettingsRouter()
    private let halo = HaloController()
    private lazy var palette = PaletteController(model: model)
    private lazy var calibration = CalibrationController(model: model)

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func setUp() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Nod")
        }
        let host = NSHostingController(rootView: MenuPanel().environment(model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        calibration.onClose = { [weak self] in self?.refreshOverlays() }
        halo.enabled = model.settings.showHalo
        updateStatusIcon()
    }

    // MARK: Menu bar

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showQuickMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func showPopoverForDev() {
        if !popover.isShown { togglePopover() }
    }

    private func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    private func showQuickMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: model.isEnabled ? "Stop Nod" : "Start Nod", action: #selector(menuToggle), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let calibrate = NSMenuItem(title: "Calibrate…", action: #selector(menuCalibrate), keyEquivalent: "")
        calibrate.target = self
        menu.addItem(calibrate)
        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Nod", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuToggle() { model.toggleEnabled() }
    @objc private func menuCalibrate() { startCalibration() }
    @objc private func menuSettings() { showSettings(pane: nil) }

    private var statusSymbol = ""
    private var statusAlpha: CGFloat = 0

    func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let s = model.live.status
        let symbol: String
        var alpha: CGFloat = 1
        if model.cameraError != nil && model.isEnabled {
            symbol = "exclamationmark.triangle"
        } else if !model.isEnabled {
            symbol = "nose"
            alpha = 0.55
        } else if s.paused {
            symbol = "pause.circle"
        } else if s.faceVisible {
            symbol = "nose.fill"
        } else {
            symbol = "nose"
        }
        // Called on every HUD change; only touch the button when it changes.
        guard symbol != statusSymbol || alpha != statusAlpha else { return }
        statusSymbol = symbol
        statusAlpha = alpha
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Nod")
        image?.isTemplate = true
        button.image = image
        button.alphaValue = alpha
        button.toolTip = model.isEnabled ? "Nod is on" : "Nod is off"
    }

    func popoverDidClose(_ notification: Notification) {}

    // MARK: Windows

    func showSettings(pane: SettingsPane?) {
        closePopover()
        if let pane { router.pane = pane }
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(router: router).environment(model))
            let w = NSWindow(contentViewController: host)
            w.title = "Nod Settings"
            // A plain title bar: content starts below it, nothing is clipped.
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(CGSize(width: 820, height: 600))
            w.minSize = CGSize(width: 760, height: 540)
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("NodSettings")
            w.delegate = self
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        closePopover()
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView { [weak self] calibrate in
                self?.finishOnboarding(calibrate: calibrate)
            }.environment(model))
            let w = NSWindow(contentViewController: host)
            w.title = "Welcome to Nod"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.center()
            w.delegate = self
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding(calibrate: Bool) {
        model.settings.hasCompletedOnboarding = true
        onboardingWindow?.close()
        if calibrate {
            startCalibration()
        } else {
            model.setEnabled(true)
        }
    }

    func startCalibration(input: TrackingInput? = nil, gesturesOnly: Bool = false) {
        closePopover()
        guard !calibration.isRunning else { return }
        guard model.cameraPermission == .granted else {
            showSettings(pane: .permissions)
            return
        }
        halo.hide()
        palette.hide()
        let kind: CalibrationSession.Kind = gesturesOnly ? .gestures : .movement(input ?? model.settings.input.calibrationInput)
        calibration.start(kind)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === onboardingWindow, !model.settings.hasCompletedOnboarding {
            // Closing the tour still leaves a usable app.
            model.settings.hasCompletedOnboarding = true
        }
    }

    // MARK: Overlays

    var isPaletteVisible: Bool { palette.isVisible }

    func togglePalette() {
        closePopover()
        palette.toggle()
    }

    func hudChanged(_ hud: HUDState) {
        guard !calibration.isRunning else { return }
        halo.update(hud)
        updateStatusIcon()
    }

    func feedback(_ f: EngineFeedback) {
        switch f {
        case let .performed(action):
            halo.toast(action.shortTitle, symbol: action.symbol)
        case .dragStarted: halo.toast("Drag", symbol: "hand.draw.fill")
        case .dragEnded: halo.toast("Dropped", symbol: "arrow.down.to.line")
        case let .scrollMode(on): halo.toast(on ? "Scroll mode" : "Scroll off", symbol: "arrow.up.and.down")
        case let .paused(on): halo.toast(on ? "Paused" : "Resumed", symbol: on ? "pause.fill" : "play.fill")
        case .paletteToggleRequested: togglePalette()
        case .faceLost, .faceFound: updateStatusIcon()
        }
    }

    func trackingChanged() {
        updateStatusIcon()
        refreshOverlays()
    }

    func settingsChanged(from old: NodSettings) {
        halo.enabled = model.settings.showHalo
        if old.dwell != model.settings.dwell { refreshOverlays() }
    }

    /// Shows the palette automatically while tracking with dwell on.
    private func refreshOverlays() {
        let d = model.settings.dwell
        let wantPalette = model.isEnabled && d.enabled && d.showPalette && !calibration.isRunning
        if wantPalette, !palette.isVisible {
            palette.show()
        } else if !wantPalette, palette.isVisible, !model.isEnabled || !d.enabled {
            palette.hide()
        }
        if !model.isEnabled { halo.hide() }
    }
}
