import AppKit
import ApplicationServices
import Carbon.HIToolbox
import NodCore
import ServiceManagement

// MARK: - Permissions

enum PermissionStatus: String, Equatable {
    case granted
    case denied
    case notDetermined

    var isGranted: Bool { self == .granted }
}

@MainActor
enum Permissions {
    /// Headphone motion, for the AirPods input. macOS asks the first time
    /// Nod starts reading it.
    static var motion: PermissionStatus {
        switch HeadphoneMotion.authorization {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static var accessibility: PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Shows the system prompt that leads to the Accessibility list.
    static func promptAccessibility() {
        // The constant kAXTrustedCheckOptionPrompt is a mutable global, which
        // Swift 6 rejects; its value is this string.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openPrivacySettings() {
        open("x-apple.systempreferences:com.apple.preference.security")
    }

    private static func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Launch at login

@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Only a real app bundle can register itself.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func set(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

// MARK: - Global hotkeys

/// System-wide shortcuts through Carbon's RegisterEventHotKey, which needs no
/// extra permission (unlike an event tap). A registered shortcut is taken
/// before any app sees it, so it never types into anything.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Entry {
        let spec: HotKeySpec
        let group: String
        let onPress: () -> Void
        let onRelease: (() -> Void)?
        var ref: EventHotKeyRef?
    }

    private var entries: [UInt32: Entry] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    /// While a new shortcut is being recorded, every hotkey steps aside so
    /// the recorder can see the keys, and click keys do not click.
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            for id in entries.keys {
                if isSuspended {
                    if let ref = entries[id]?.ref { UnregisterEventHotKey(ref) }
                    entries[id]?.ref = nil
                } else if let spec = entries[id]?.spec {
                    entries[id]?.ref = Self.install(spec, id: id)
                }
            }
        }
    }

    /// Removes the shortcuts of one group ("app" for Nod's own shortcuts,
    /// "click" for click keys).
    func removeAll(group: String = "app") {
        for (id, e) in entries where e.group == group {
            if let ref = e.ref { UnregisterEventHotKey(ref) }
            entries[id] = nil
        }
    }

    @discardableResult
    func register(_ spec: HotKeySpec, group: String = "app", onRelease: (() -> Void)? = nil, action: @escaping () -> Void) -> Bool {
        guard spec.isEnabled else { return false }
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        let ref = isSuspended ? nil : Self.install(spec, id: id)
        guard isSuspended || ref != nil else { return false }
        entries[id] = Entry(spec: spec, group: group, onPress: action, onRelease: onRelease, ref: ref)
        return true
    }

    private static func install(_ spec: HotKeySpec, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F_4421), id: id) // "NOD!"
        let status = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        return status == noErr ? ref : nil
    }

    fileprivate func fire(_ id: UInt32, pressed: Bool) {
        guard !isSuspended, let e = entries[id] else { return }
        if pressed { e.onPress() } else { e.onRelease?() }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard err == noErr else { return err }
            let id = hk.id
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            // Carbon delivers hotkeys on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.fire(id, pressed: pressed) }
            return noErr
        }, specs.count, &specs, nil, nil)
    }

    /// Converts an AppKit key event into a Carbon hotkey spec for recording.
    /// - Parameter allowPlain: accept a key without ⌘ ⌥ ⌃. Nod's own
    ///   shortcuts need one so plain typing is never swallowed; a click key
    ///   may be any key the user picks.
    static func spec(from event: NSEvent, allowPlain: Bool = false) -> HotKeySpec? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if !allowPlain, flags.intersection([.command, .option, .control]).isEmpty { return nil }
        var carbon: UInt32 = 0
        var text = ""
        if flags.contains(.control) { carbon |= HotKeySpec.controlKey; text += "⌃" }
        if flags.contains(.option) { carbon |= HotKeySpec.optionKey; text += "⌥" }
        if flags.contains(.shift) { carbon |= HotKeySpec.shiftKey; text += "⇧" }
        if flags.contains(.command) { carbon |= HotKeySpec.cmdKey; text += "⌘" }
        text += keyName(event)
        return HotKeySpec(keyCode: UInt32(event.keyCode), carbonModifiers: carbon, display: text)
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        // Function key codes are not in order (F1 is 0x7A, F2 0x78, F3 0x63).
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static func keyName(_ event: NSEvent) -> String {
        namedKeys[Int(event.keyCode)] ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

extension HotKeySpec {
    /// The modifier flags this shortcut holds down while it is pressed.
    var eventFlags: CGEventFlags {
        var f: CGEventFlags = []
        if carbonModifiers & HotKeySpec.cmdKey != 0 { f.insert(.maskCommand) }
        if carbonModifiers & HotKeySpec.optionKey != 0 { f.insert(.maskAlternate) }
        if carbonModifiers & HotKeySpec.controlKey != 0 { f.insert(.maskControl) }
        if carbonModifiers & HotKeySpec.shiftKey != 0 { f.insert(.maskShift) }
        return f
    }
}

// MARK: - Sounds

@MainActor
enum Sounds {
    private static var cache: [String: NSSound] = [:]

    static func play(_ name: String, volume: Float = 0.35) {
        let sound = cache[name] ?? NSSound(named: NSSound.Name(name))
        cache[name] = sound
        guard let sound else { return }
        sound.stop()
        sound.volume = volume
        sound.play()
    }

    static func play(for feedback: EngineFeedback) {
        switch feedback {
        case let .performed(action):
            switch action {
            case .leftClick, .leftHold, .middleClick: play("Tink", volume: 0.25)
            case .rightClick: play("Pop", volume: 0.3)
            case .doubleClick: play("Tink", volume: 0.3)
            case .recenter: play("Morse", volume: 0.25)
            default: break
            }
        case .dragStarted: play("Pop", volume: 0.3)
        case .dragEnded: play("Bottle", volume: 0.25)
        case let .scrollMode(on): play(on ? "Purr" : "Bottle", volume: 0.25)
        case let .paused(on): play(on ? "Submarine" : "Glass", volume: 0.3)
        case .lost, .found, .paletteToggleRequested: break
        }
    }
}
