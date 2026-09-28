import Foundation

/// How head movement becomes pointer movement.
public enum MotionStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case relative
    case direct
    case joystick

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .relative: "Relative"
        case .direct: "Direct"
        case .joystick: "Joystick"
        }
    }

    public var summary: String {
        switch self {
        case .relative: "Moves like a mouse. Small head turns, fine control."
        case .direct: "Your head aims at a spot on screen. Recentre lines it up."
        case .joystick: "Turn away from centre to glide. Least neck movement."
        }
    }
}

/// Something Nod can do with the pointer.
public enum PointerAction: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case leftClick
    case leftHold
    case rightClick
    case doubleClick
    case middleClick
    case dragToggle
    case scrollToggle
    case pauseToggle
    case recenter
    case togglePalette

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "Nothing"
        case .leftClick: "Left click"
        case .leftHold: "Left click, hold to drag"
        case .rightClick: "Right click"
        case .doubleClick: "Double click"
        case .middleClick: "Middle click"
        case .dragToggle: "Start or drop a drag"
        case .scrollToggle: "Scroll mode on or off"
        case .pauseToggle: "Pause or resume pointer"
        case .recenter: "Recentre pointer"
        case .togglePalette: "Show or hide palette"
        }
    }

    public var shortTitle: String {
        switch self {
        case .none: "None"
        case .leftClick: "Click"
        case .leftHold: "Click & hold"
        case .rightClick: "Right"
        case .doubleClick: "Double"
        case .middleClick: "Middle"
        case .dragToggle: "Drag"
        case .scrollToggle: "Scroll"
        case .pauseToggle: "Pause"
        case .recenter: "Recentre"
        case .togglePalette: "Palette"
        }
    }

    public var symbol: String {
        switch self {
        case .none: "circle.slash"
        case .leftClick: "cursorarrow.click"
        case .leftHold: "hand.point.up.left"
        case .rightClick: "contextualmenu.and.cursorarrow"
        case .doubleClick: "cursorarrow.click.2"
        case .middleClick: "computermouse"
        case .dragToggle: "hand.draw"
        case .scrollToggle: "arrow.up.and.down"
        case .pauseToggle: "pause.circle"
        case .recenter: "scope"
        case .togglePalette: "square.grid.2x2"
        }
    }

    /// Actions that make sense as the dwell action.
    public static let dwellChoices: [PointerAction] = [.leftClick, .rightClick, .doubleClick, .dragToggle, .scrollToggle, .middleClick]
    /// Actions offered for a face gesture.
    public static let gestureChoices: [PointerAction] = [.none, .leftClick, .leftHold, .rightClick, .doubleClick, .middleClick, .dragToggle, .scrollToggle, .pauseToggle, .recenter, .togglePalette]
}

/// Head movements Nod recognises from headphone motion sensors.
public enum HeadGesture: String, Codable, CaseIterable, Sendable, Identifiable, CodingKeyRepresentable {
    case tiltLeft
    case tiltRight
    case nod

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tiltLeft: "Tilt left"
        case .tiltRight: "Tilt right"
        case .nod: "Nod"
        }
    }

    public var instruction: String {
        switch self {
        case .tiltLeft: "Lean your head towards your left shoulder"
        case .tiltRight: "Lean your head towards your right shoulder"
        case .nod: "A quick nod down and back up"
        }
    }

    public var symbol: String {
        switch self {
        case .tiltLeft: "arrow.counterclockwise"
        case .tiltRight: "arrow.clockwise"
        case .nod: "chevron.down.circle"
        }
    }
}

public struct GestureBinding: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var action: PointerAction
    /// 0 = needs a big expression, 1 = triggers on a small one.
    public var sensitivity: Double
    /// Seconds the expression must be held before it counts.
    public var holdTime: Double

    public init(enabled: Bool, action: PointerAction, sensitivity: Double = 0.5, holdTime: Double) {
        self.enabled = enabled
        self.action = action
        self.sensitivity = sensitivity
        self.holdTime = holdTime
    }

    public static func defaults(for gesture: HeadGesture) -> GestureBinding {
        switch gesture {
        case .tiltLeft: GestureBinding(enabled: true, action: .leftHold, holdTime: 0.12)
        case .tiltRight: GestureBinding(enabled: true, action: .rightClick, holdTime: 0.15)
        // Off by default: glancing down at the keyboard looks a lot like a nod.
        case .nod: GestureBinding(enabled: false, action: .doubleClick, holdTime: 0)
        }
    }
}

public struct DwellSettings: Codable, Sendable, Equatable {
    public var enabled: Bool = false
    /// Seconds of stillness before the dwell action fires.
    public var time: Double = 1.0
    /// Radius in points the pointer may wander and still count as still.
    public var radius: Double = 28
    public var defaultAction: PointerAction = .leftClick
    /// Keep a palette choice until another one is picked, instead of one use.
    public var stickyChoice: Bool = false
    public var showPalette: Bool = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DwellSettings()
        enabled = c.value(.enabled, default: d.enabled)
        time = c.value(.time, default: d.time)
        radius = c.value(.radius, default: d.radius)
        defaultAction = c.value(.defaultAction, default: d.defaultAction)
        stickyChoice = c.value(.stickyChoice, default: d.stickyChoice)
        showPalette = c.value(.showPalette, default: d.showPalette)
    }
}

/// A global keyboard shortcut, stored as a Carbon key code and modifier mask.
public struct HotKeySpec: Codable, Sendable, Equatable, Hashable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    /// Human readable, for example "⌃⌥N".
    public var display: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }

    // Carbon modifier bits (from HIToolbox Events.h), mirrored here so NodCore
    // does not need Carbon.
    public static let cmdKey: UInt32 = 1 << 8
    public static let shiftKey: UInt32 = 1 << 9
    public static let optionKey: UInt32 = 1 << 11
    public static let controlKey: UInt32 = 1 << 12

    // kVK_ANSI_N = 0x2D, kVK_ANSI_C = 0x08
    /// A shortcut the user cleared. Stored explicitly so it is not replaced
    /// by the default on the next launch.
    public static let disabled = HotKeySpec(keyCode: .max, carbonModifiers: 0, display: "")
    public var isEnabled: Bool { keyCode != .max }

    public static let defaultToggle = HotKeySpec(keyCode: 0x2D, carbonModifiers: controlKey | optionKey, display: "⌃⌥N")
    public static let defaultRecenter = HotKeySpec(keyCode: 0x08, carbonModifiers: controlKey | optionKey, display: "⌃⌥C")
}

public struct NodSettings: Codable, Sendable, Equatable {
    public var motion: MotionStyle = .relative
    /// Pointer speed multiplier, 0.25...3.
    public var speed: Double = 1.0
    /// 0 = linear, 1 = strong acceleration (slow is precise, fast travels far).
    public var acceleration: Double = 0.55
    /// 0 = raw, 1 = very smooth.
    public var smoothing: Double = 0.5
    /// Joystick dead zone, fraction of the head's travel.
    public var deadzone: Double = 0.12
    /// Joystick top speed in screen widths per second.
    public var joystickSpeed: Double = 0.9

    /// Clicks by leaning or nodding.
    public var headGestures: [HeadGesture: GestureBinding] = Dictionary(uniqueKeysWithValues: HeadGesture.allCases.map { ($0, GestureBinding.defaults(for: $0)) })
    /// Freeze the pointer while a tilt forms, so clicks land where aimed.
    public var holdSteadyWhileGesturing: Bool = true
    /// Click with the right-hand modifier keys while the head steers.
    public var clickKeys = ClickKeys()
    public var dwell = DwellSettings()

    public var showHalo: Bool = true
    public var playSounds: Bool = true
    /// Hand the pointer back when the physical mouse or trackpad moves.
    public var yieldToMouse: Bool = true
    public var invertX: Bool = false
    public var invertY: Bool = false
    /// Display used for direct aiming and recentring (CGDirectDisplayID).
    public var displayID: UInt32?

    public var toggleHotKey: HotKeySpec = .defaultToggle
    public var recenterHotKey: HotKeySpec = .defaultRecenter

    public var hasCompletedOnboarding: Bool = false
    /// Bumped when the meaning of `speed` changes, so stored values can be
    /// migrated to keep the same feel.
    public var motionRevision: Int = NodSettings.currentMotionRevision
    public static let currentMotionRevision = 2

    public init() {}

    public func binding(for gesture: HeadGesture) -> GestureBinding {
        headGestures[gesture] ?? .defaults(for: gesture)
    }

    /// Decodes leniently: every missing or unreadable key falls back to its
    /// default, so settings survive app updates that add new options.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NodSettings()
        motion = c.value(.motion, default: d.motion)
        speed = c.value(.speed, default: d.speed)
        acceleration = c.value(.acceleration, default: d.acceleration)
        smoothing = c.value(.smoothing, default: d.smoothing)
        deadzone = c.value(.deadzone, default: d.deadzone)
        joystickSpeed = c.value(.joystickSpeed, default: d.joystickSpeed)
        var h = d.headGestures
        for (k, v) in c.value(.headGestures, default: [HeadGesture: GestureBinding]()) { h[k] = v }
        headGestures = h
        holdSteadyWhileGesturing = c.value(.holdSteadyWhileGesturing, default: d.holdSteadyWhileGesturing)
        clickKeys = c.value(.clickKeys, default: d.clickKeys)
        dwell = c.value(.dwell, default: d.dwell)
        showHalo = c.value(.showHalo, default: d.showHalo)
        playSounds = c.value(.playSounds, default: d.playSounds)
        yieldToMouse = c.value(.yieldToMouse, default: d.yieldToMouse)
        invertX = c.value(.invertX, default: d.invertX)
        invertY = c.value(.invertY, default: d.invertY)
        displayID = c.value(.displayID, default: d.displayID)
        toggleHotKey = c.value(.toggleHotKey, default: d.toggleHotKey)
        recenterHotKey = c.value(.recenterHotKey, default: d.recenterHotKey)
        hasCompletedOnboarding = c.value(.hasCompletedOnboarding, default: d.hasCompletedOnboarding)
        motionRevision = c.value(.motionRevision, default: 1)
        if motionRevision < 2 {
            // Revision 2 made relative motion about 0.45 times as fast at
            // the same speed value; keep the feel the user had chosen.
            speed = (speed / 0.45).clamped(0.25, 3)
            motionRevision = 2
        }
    }
}

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
