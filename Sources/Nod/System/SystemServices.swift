import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox
import NodCore
import ServiceManagement

// MARK: - Permissions

enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined

    var isGranted: Bool { self == .granted }
}

@MainActor
enum Permissions {
    static var camera: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static var accessibility: PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    static func requestCamera() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
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

    static func openCameraSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
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
/// extra permission (unlike an event tap).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    /// While recording a new shortcut, hotkeys must not fire.
    var isSuspended = false

    func removeAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
    }

    @discardableResult
    func register(_ spec: HotKeySpec, action: @escaping () -> Void) -> Bool {
        guard spec.isEnabled else { return false }
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F_4421), id: id) // "NOD!"
        let status = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        actions[id] = action
        return true
    }

    fileprivate func fire(_ id: UInt32) {
        guard !isSuspended else { return }
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard err == noErr else { return err }
            let id = hk.id
            // Carbon delivers hotkeys on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Converts an AppKit key event into a Carbon hotkey spec for recording.
    static func spec(from event: NSEvent) -> HotKeySpec? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // Require at least one of ⌘ ⌥ ⌃ so plain typing is never swallowed.
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var carbon: UInt32 = 0
        var text = ""
        if flags.contains(.control) { carbon |= HotKeySpec.controlKey; text += "⌃" }
        if flags.contains(.option) { carbon |= HotKeySpec.optionKey; text += "⌥" }
        if flags.contains(.shift) { carbon |= HotKeySpec.shiftKey; text += "⇧" }
        if flags.contains(.command) { carbon |= HotKeySpec.cmdKey; text += "⌘" }
        text += keyName(event)
        return HotKeySpec(keyCode: UInt32(event.keyCode), carbonModifiers: carbon, display: text)
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1...kVK_F12: return "F" + String(fKeyNumber(Int(event.keyCode)))
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }

    private static func fKeyNumber(_ code: Int) -> Int {
        let map = [kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6,
                   kVK_F7: 7, kVK_F8: 8, kVK_F9: 9, kVK_F10: 10, kVK_F11: 11, kVK_F12: 12]
        return map[code] ?? 0
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
        case .faceLost, .faceFound, .paletteToggleRequested: break
        }
    }
}
