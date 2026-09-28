import Foundation

/// A right-hand modifier key used on its own. Pressed alone it does nothing
/// in other apps, and the left-hand ones stay free for shortcuts.
public enum ClickKey: String, Codable, CaseIterable, Sendable, Identifiable {
    case off
    case rightCommand
    case rightOption
    case rightShift
    case rightControl

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .rightCommand: "Right ⌘ Command"
        case .rightOption: "Right ⌥ Option"
        case .rightShift: "Right ⇧ Shift"
        case .rightControl: "Right ⌃ Control"
        }
    }

    public var shortTitle: String {
        switch self {
        case .off: "Off"
        case .rightCommand: "right ⌘"
        case .rightOption: "right ⌥"
        case .rightShift: "right ⇧"
        case .rightControl: "right ⌃"
        }
    }

    /// macOS virtual key code (kVK_RightCommand and friends).
    public var keyCode: UInt16? {
        switch self {
        case .off: nil
        case .rightCommand: 0x36
        case .rightOption: 0x3D
        case .rightShift: 0x3C
        case .rightControl: 0x3E
        }
    }

    /// The device-dependent modifier bit that is set while this key is down
    /// (NX_DEVICERCMDKEYMASK and friends in IOLLEvent.h).
    public var deviceMask: UInt64 {
        switch self {
        case .off: 0
        case .rightCommand: 0x10
        case .rightOption: 0x40
        case .rightShift: 0x04
        case .rightControl: 0x2000
        }
    }

    public init?(keyCode: UInt16) {
        guard let k = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = k
    }
}

/// What makes a click: nothing, a lone right-hand modifier, or any shortcut
/// you record (a key on its own, or with ⌘ ⌥ ⌃ ⇧).
///
/// Stored as a plain string for the first two ("off", "rightCommand"), so
/// settings written before shortcuts existed still read correctly.
public enum ClickTrigger: Codable, Sendable, Hashable {
    case off
    case modifier(ClickKey)
    case shortcut(HotKeySpec)

    public var isOff: Bool {
        if case .off = self { return true }
        if case .modifier(.off) = self { return true }
        return false
    }

    public var title: String {
        switch self {
        case .off: "Off"
        case let .modifier(k): k.title
        case let .shortcut(spec): spec.display
        }
    }

    public var shortTitle: String {
        switch self {
        case .off: "Off"
        case let .modifier(k): k.shortTitle
        case let .shortcut(spec): spec.display
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let key = try? c.decode(ClickKey.self) {
            self = key == .off ? .off : .modifier(key)
        } else {
            self = .shortcut(try c.decode(HotKeySpec.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .off: try c.encode(ClickKey.off)
        case let .modifier(k): try c.encode(k)
        case let .shortcut(spec): try c.encode(spec)
        }
    }
}

/// Which key does what. One key, one job.
public struct ClickKeys: Codable, Sendable, Equatable {
    public var enabled = true
    /// Tap to click, tap twice to double click, hold to drag.
    public var leftButton: ClickTrigger = .modifier(.rightCommand)
    public var rightClick: ClickTrigger = .modifier(.rightOption)
    public var doubleClick: ClickTrigger = .off

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClickKeys()
        enabled = c.value(.enabled, default: d.enabled)
        leftButton = c.value(.leftButton, default: d.leftButton)
        rightClick = c.value(.rightClick, default: d.rightClick)
        doubleClick = c.value(.doubleClick, default: d.doubleClick)
    }

    public var all: [ClickTrigger] { [leftButton, rightClick, doubleClick] }

    public func isBound(_ trigger: ClickTrigger) -> Bool {
        !trigger.isOff && all.contains(trigger)
    }

    /// The recorded shortcuts, which the app registers as global hotkeys.
    public var shortcuts: [HotKeySpec] {
        all.compactMap { if case let .shortcut(s) = $0, s.isEnabled { s } else { nil } }
    }
}

public enum KeyClickEvent: Equatable, Sendable {
    case down(ClickTrigger)
    case up(ClickTrigger)
    /// Any other key or modifier: a lone modifier is part of a shortcut.
    case otherKey
}

public enum KeyClickOutput: Equatable, Sendable {
    /// A quick tap of the left button key: press and release.
    case tap
    /// The left button key is held: press now, release on `release`.
    case press
    case release
    case rightClick
    case doubleClick
}

/// Tells a tap or a hold of a click key from a shortcut.
///
/// A tap counts on release. For a lone right-hand modifier, pressing any
/// other key meanwhile turns it into a shortcut, so it never clicks. A
/// recorded shortcut is deliberate, so other keys do not cancel it. Holding
/// the left button key for `holdDelay` presses the button until the key
/// comes up, which is how you drag.
public struct KeyClickDetector: Sendable {
    public static let holdDelay = 0.3
    /// Held longer than this without a drag: probably not meant as a click.
    public static let longestTap = 1.0

    private struct Held: Sendable {
        var trigger: ClickTrigger
        var since: Double
        var spoiled = false
        var pressed = false

        var canBeSpoiled: Bool {
            if case .modifier = trigger { return true }
            return false
        }
    }

    private var held: Held?

    public init() {}

    public var isHoldingButton: Bool { held?.pressed == true }

    /// A click key is down; the clock must keep running to catch a hold.
    public var isWaiting: Bool { held != nil }

    public mutating func handle(_ event: KeyClickEvent, time: Double, keys: ClickKeys) -> [KeyClickOutput] {
        guard keys.enabled else {
            let wasPressed = held?.pressed == true
            held = nil
            return wasPressed ? [.release] : []
        }
        switch event {
        case let .down(t):
            if var h = held {
                // Key repeat of the same key: nothing new.
                if h.trigger == t { return [] }
                // Two click keys at once is a chord, not a click.
                if !h.pressed { h.spoiled = true }
                held = h
                return []
            }
            if keys.isBound(t) { held = Held(trigger: t, since: time) }
        case let .up(t):
            guard let h = held, h.trigger == t else { return [] }
            held = nil
            if h.pressed { return [.release] }
            guard !h.spoiled, time - h.since <= Self.longestTap else { return [] }
            if t == keys.leftButton { return [.tap] }
            if t == keys.rightClick { return [.rightClick] }
            if t == keys.doubleClick { return [.doubleClick] }
        case .otherKey:
            if var h = held, !h.pressed, h.canBeSpoiled {
                h.spoiled = true
                held = h
            }
        }
        return []
    }

    /// Call regularly (the engine's clock) so a hold turns into a press.
    public mutating func tick(time: Double, keys: ClickKeys) -> [KeyClickOutput] {
        guard keys.enabled, var h = held, !h.pressed, !h.spoiled, h.trigger == keys.leftButton,
              time - h.since >= Self.holdDelay else { return [] }
        h.pressed = true
        held = h
        return [.press]
    }
}
