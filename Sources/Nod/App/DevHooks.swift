import AppKit
import NodCore

/// Developer remote control, only active when launched with NOD_DEV=1:
///
///     open --env NOD_DEV=1 build/Nod.app
///     scripts/devctl.swift settings clicking
///     scripts/devctl.swift snapshot /tmp/nod-shots
///
/// Lets a script open screens and capture the app's own windows (which needs
/// no Screen Recording permission, since Nod renders its own views).
@MainActor
enum DevHooks {
    static let notification = Notification.Name("com.slipperysign.nod.dev")

    static func installIfRequested(model: AppModel, windows: WindowManager) {
        guard ProcessInfo.processInfo.environment["NOD_DEV"] == "1" else { return }
        DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { run(command, model: model, windows: windows) }
        }
        print("Nod dev hooks active")
    }

    private static func run(_ command: String, model: AppModel, windows: WindowManager) {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts.first {
        case "settings": windows.showSettings(pane: SettingsPane(rawValue: arg) ?? .general)
        case "popover": windows.showPopoverForDev()
        case "close": windows.closeAllForDev()
        case "onboarding": windows.showOnboarding()
        case "palette": windows.togglePalette()
        case "enable": model.setEnabled(true)
        case "disable": model.setEnabled(false)
        case "snapshot": snapshot(to: arg.isEmpty ? NSTemporaryDirectory() + "nod-shots" : arg)
        case "status":
            let line = "enabled=\(model.isEnabled) \(model.debugClients)\n"
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nod-dev.log")
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        case "pause": model.perform(.pauseToggle)
        case "keytest": postRightCommandTap()
        case "otherkeytest": postHarmlessKey()
        case "ctrltap": postLeftControl(withKey: false)
        case "ctrlchord": postLeftControl(withKey: true)
        case "shortcuttest": testShortcut(model: model)
        case "quit": NSApp.terminate(nil)
        default: print("Unknown dev command: \(command)")
        }
    }

    /// Posts a lone right ⌘ press and release, to check that the click key
    /// monitor hears real key events. Pause first, or it clicks.
    private static func postRightCommandTap() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(ClickKey.rightCommand.keyCode ?? 0), keyDown: down) else { continue }
            e.type = .flagsChanged
            e.flags = down ? ClickKey.rightCommand.eventFlags : []
            e.post(tap: .cghidEventTap)
            if down { usleep(80_000) }
        }
    }

    /// Binds F13 to double click for a moment and presses it, to check that
    /// recorded click shortcuts arrive with both press and release. Pause
    /// first, or it double clicks. The previous binding comes back after.
    private static func testShortcut(model: AppModel) {
        let before = model.settings.clickKeys.doubleClick
        model.settings.clickKeys.doubleClick = .shortcut(HotKeySpec(keyCode: 0x69, carbonModifiers: 0, display: "F13"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                CGEvent(keyboardEventSource: source, virtualKey: 0x69, keyDown: down)?.post(tap: .cghidEventTap)
                if down { usleep(80_000) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { model.settings.clickKeys.doubleClick = before }
            }
        }
    }

    /// Posts F13, which no app uses, to check that other keys reach the
    /// monitor (they are what stops a modifier in a shortcut from clicking).
    private static func postHarmlessKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 0x69, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }

    /// Left ⌃ alone, or left ⌃ held around F13 (like ⌃A, minus the A).
    private static func postLeftControl(withKey: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        func flags(_ down: Bool) {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0x3B, keyDown: down) else { return }
            e.type = .flagsChanged
            e.flags = down ? ClickKey.leftControl.eventFlags : []
            e.post(tap: .cghidEventTap)
        }
        flags(true)
        usleep(40_000)
        if withKey {
            for down in [true, false] {
                CGEvent(keyboardEventSource: source, virtualKey: 0x69, keyDown: down)?.post(tap: .cghidEventTap)
            }
            usleep(40_000)
        }
        flags(false)
    }

    private static func snapshot(to dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (i, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = (window.title.isEmpty ? String(describing: type(of: window)) : window.title).replacingOccurrences(of: " ", with: "-")
            let file = url.appendingPathComponent("\(i)-\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
            print("snapshot \(file.path)")
        }
    }
}
