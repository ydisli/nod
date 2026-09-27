import AppKit
import NodCore

/// Watches the right-hand modifier keys for click taps and holds.
///
/// Other key presses are noticed only as "some other key", so a click key
/// used in a shortcut does not click. Nothing typed is read or kept. Global
/// key monitoring needs the Accessibility permission, which Nod already has
/// for moving the pointer. Runs only while tracking is on.
@MainActor
final class KeyClickMonitor {
    private var monitors: [Any] = []
    private let onEvent: (KeyClickEvent) -> Void
    /// For diagnostics: click key events seen since start.
    private(set) var seen = 0

    init(onEvent: @escaping (KeyClickEvent) -> Void) {
        self.onEvent = onEvent
    }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
        }) {
            monitors.append(m)
        }
        // Global monitors skip Nod's own windows.
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
            return e
        }) {
            monitors.append(m)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(_ e: NSEvent) {
        guard e.type == .flagsChanged else {
            onEvent(.otherKey)
            return
        }
        guard let key = ClickKey(keyCode: e.keyCode) else {
            // A left-hand modifier, fn or Caps Lock: part of a shortcut.
            onEvent(.otherKey)
            return
        }
        seen += 1
        let down = UInt64(e.modifierFlags.rawValue) & key.deviceMask != 0
        onEvent(down ? .down(key) : .up(key))
    }
}

extension ClickKey {
    /// Modifier flags a held key adds to events. Taken off Nod's own mouse
    /// events, so holding right ⌘ to drag is a plain drag, not a ⌘ drag.
    var eventFlags: CGEventFlags {
        let device = CGEventFlags(rawValue: deviceMask)
        switch self {
        case .off: return []
        case .rightCommand: return [.maskCommand, device]
        case .rightOption: return [.maskAlternate, device]
        case .rightShift: return [.maskShift, device]
        case .rightControl: return [.maskControl, device]
        }
    }
}
