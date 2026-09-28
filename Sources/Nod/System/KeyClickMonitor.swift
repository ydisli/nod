import AppKit
import NodCore

/// Watches the modifier keys for click taps and holds.
///
/// Other key presses are noticed only as "some other key", so a click key
/// used in a shortcut does not click. Nothing typed is read or kept. Global
/// key monitoring needs the Accessibility permission, which Nod already has
/// for moving the pointer. Runs only while tracking is on.
@MainActor
final class KeyClickMonitor {
    private var monitors: [Any] = []
    private let onEvent: (KeyClickEvent) -> Void
    /// For diagnostics: click key events and other keys seen since start.
    private(set) var seen = 0
    private(set) var others = 0

    init(onEvent: @escaping (KeyClickEvent) -> Void) {
        self.onEvent = onEvent
    }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        // Mouse and trackpad clicks count as "another key": ⌘-clicking a link
        // and then letting go of ⌘ must not click again.
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
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
        // Recording a shortcut: the keys are for the recorder, not clicks.
        guard !HotKeyCenter.shared.isSuspended else { return }
        guard e.type == .flagsChanged else {
            others += 1
            onEvent(.otherKey)
            return
        }
        guard let key = ClickKey(keyCode: e.keyCode) else {
            // fn or Caps Lock: part of a shortcut.
            onEvent(.otherKey)
            return
        }
        seen += 1
        let down = UInt64(e.modifierFlags.rawValue) & key.deviceMask != 0
        onEvent(down ? .down(.modifier(key)) : .up(.modifier(key)))
    }
}

extension ClickTrigger {
    /// Modifiers held while this trigger is down, taken off Nod's own mouse
    /// events so a click never turns into a ⌘ or ⌥ click.
    var eventFlags: CGEventFlags {
        switch self {
        case .off: []
        case let .modifier(k): k.eventFlags
        case let .shortcut(spec): spec.eventFlags
        }
    }
}

extension ClickKey {
    /// Modifier flags a held key adds to events. Taken off Nod's own mouse
    /// events, so holding right ⌘ to drag is a plain drag, not a ⌘ drag.
    var eventFlags: CGEventFlags {
        let device = CGEventFlags(rawValue: deviceMask)
        switch self {
        case .off: return []
        case .rightCommand, .leftCommand: return [.maskCommand, device]
        case .rightOption, .leftOption: return [.maskAlternate, device]
        case .rightShift, .leftShift: return [.maskShift, device]
        case .rightControl, .leftControl: return [.maskControl, device]
        }
    }
}
