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
        case "onboarding": windows.showOnboarding()
        case "palette": windows.togglePalette()
        case "calibrate": windows.startCalibration()
        case "enable": model.setEnabled(true)
        case "disable": model.setEnabled(false)
        case "snapshot": snapshot(to: arg.isEmpty ? NSTemporaryDirectory() + "nod-shots" : arg)
        case "status":
            let line = "enabled=\(model.isEnabled) calibrating=\(model.isCalibrating) camera=\(model.live.cameraRunning) \(model.debugClients)\n"
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nod-dev.log")
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        case "quit": NSApp.terminate(nil)
        default: print("Unknown dev command: \(command)")
        }
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
