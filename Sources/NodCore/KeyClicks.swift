import Foundation

/// A key that can click. Only the right-hand modifier keys: pressed on their
/// own they do nothing in other apps, and the left-hand ones stay free for
/// shortcuts.
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

/// Which key does what. One key, one job.
public struct ClickKeys: Codable, Sendable, Equatable {
    public var enabled = true
    /// Tap to click, tap twice to double click, hold to drag.
    public var leftButton: ClickKey = .rightCommand
    public var rightClick: ClickKey = .rightOption
    public var doubleClick: ClickKey = .off

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClickKeys()
        enabled = c.value(.enabled, default: d.enabled)
        leftButton = c.value(.leftButton, default: d.leftButton)
        rightClick = c.value(.rightClick, default: d.rightClick)
        doubleClick = c.value(.doubleClick, default: d.doubleClick)
    }

    public func isBound(_ key: ClickKey) -> Bool {
        key != .off && (key == leftButton || key == rightClick || key == doubleClick)
    }
}

public enum KeyClickEvent: Equatable, Sendable {
    case down(ClickKey)
    case up(ClickKey)
    /// Any other key or modifier: the click key is part of a shortcut.
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

/// Tells a lone tap or hold of a click key from a shortcut.
///
/// A tap counts on release, so a shortcut (the key plus another key) never
/// clicks. Holding the left button key for `holdDelay` presses the button
/// until the key comes up, which is how you drag.
public struct KeyClickDetector: Sendable {
    public static let holdDelay = 0.3
    /// Held longer than this without a drag: probably not meant as a click.
    public static let longestTap = 1.0

    private struct Held: Sendable {
        var key: ClickKey
        var since: Double
        var spoiled = false
        var pressed = false
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
        case let .down(k):
            if var h = held {
                // Two click keys at once is a chord, not a click.
                if !h.pressed { h.spoiled = true }
                held = h
                return []
            }
            if keys.isBound(k) { held = Held(key: k, since: time) }
        case let .up(k):
            guard let h = held, h.key == k else { return [] }
            held = nil
            if h.pressed { return [.release] }
            guard !h.spoiled, time - h.since <= Self.longestTap else { return [] }
            if k == keys.leftButton { return [.tap] }
            if k == keys.rightClick { return [.rightClick] }
            if k == keys.doubleClick { return [.doubleClick] }
        case .otherKey:
            if var h = held, !h.pressed {
                h.spoiled = true
                held = h
            }
        }
        return []
    }

    /// Call regularly (the engine's clock) so a hold turns into a press.
    public mutating func tick(time: Double, keys: ClickKeys) -> [KeyClickOutput] {
        guard keys.enabled, var h = held, !h.pressed, !h.spoiled, h.key == keys.leftButton,
              time - h.since >= Self.holdDelay else { return [] }
        h.pressed = true
        held = h
        return [.press]
    }
}
