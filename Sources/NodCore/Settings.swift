import Foundation

/// What steers the pointer.
public enum TrackingInput: String, Codable, CaseIterable, Sendable, Identifiable, CodingKeyRepresentable {
    case nose
    case eyes
    case hybrid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nose: "Nose"
        case .eyes: "Eyes"
        case .hybrid: "Hybrid"
        }
    }

    public var summary: String {
        switch self {
        case .nose: "Point with your nose. Precise, calm, works in most light."
        case .eyes: "Look where you want to go. Fast but coarse with a webcam."
        case .hybrid: "Eyes jump to the area, your nose places the pointer exactly."
        }
    }

    /// Which calibration profile this input relies on.
    public var calibrationInput: TrackingInput { self == .hybrid ? .eyes : self }
}

/// How nose movement becomes pointer movement.
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
        case .relative: "Moves like a mouse. Small head turns, fine control. Recommended."
        case .direct: "Your nose aims at a spot on screen. Needs calibration."
        case .joystick: "Tilt away from centre to glide. Least neck movement."
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

/// Facial gestures Nod can recognise from a webcam.
public enum FaceGesture: String, Codable, CaseIterable, Sendable, Identifiable, CodingKeyRepresentable {
    case mouthOpen
    case browRaise
    case smile
    case longBlink
    case leftWink
    case rightWink

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mouthOpen: "Open mouth"
        case .browRaise: "Raise eyebrows"
        case .smile: "Smile"
        case .longBlink: "Long blink"
        case .leftWink: "Left wink"
        case .rightWink: "Right wink"
        }
    }

    public var instruction: String {
        switch self {
        case .mouthOpen: "Open your mouth as if saying “ah”"
        case .browRaise: "Raise your eyebrows, surprised"
        case .smile: "Smile wide"
        case .longBlink: "Close both eyes, then open them"
        case .leftWink: "Close only your left eye"
        case .rightWink: "Close only your right eye"
        }
    }

    public var symbol: String {
        switch self {
        case .mouthOpen: "mouth"
        case .browRaise: "eyebrow"
        case .smile: "face.smiling"
        case .longBlink: "eye.slash"
        case .leftWink: "eye"
        case .rightWink: "eye"
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

    public static func defaults(for gesture: FaceGesture) -> GestureBinding {
        switch gesture {
        case .mouthOpen: GestureBinding(enabled: true, action: .leftHold, holdTime: 0.08)
        case .browRaise: GestureBinding(enabled: true, action: .rightClick, holdTime: 0.15)
        case .smile: GestureBinding(enabled: false, action: .doubleClick, holdTime: 0.25)
        case .longBlink: GestureBinding(enabled: true, action: .pauseToggle, holdTime: 0.8)
        case .leftWink: GestureBinding(enabled: false, action: .leftClick, holdTime: 0.25)
        case .rightWink: GestureBinding(enabled: false, action: .rightClick, holdTime: 0.25)
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

    // kVK_ANSI_N = 0x2D, kVK_ANSI_C = 0x08, kVK_ANSI_K = 0x28
    /// A shortcut the user cleared. Stored explicitly so it is not replaced
    /// by the default on the next launch.
    public static let disabled = HotKeySpec(keyCode: .max, carbonModifiers: 0, display: "")
    public var isEnabled: Bool { keyCode != .max }

    public static let defaultToggle = HotKeySpec(keyCode: 0x2D, carbonModifiers: controlKey | optionKey, display: "⌃⌥N")
    public static let defaultRecenter = HotKeySpec(keyCode: 0x08, carbonModifiers: controlKey | optionKey, display: "⌃⌥C")
    public static let defaultCalibrate = HotKeySpec(keyCode: 0x28, carbonModifiers: controlKey | optionKey, display: "⌃⌥K")
}

public enum EfficiencyMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case battery
    case balanced
    case precision

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .battery: "Battery"
        case .balanced: "Balanced"
        case .precision: "Precision"
        }
    }

    public var summary: String {
        switch self {
        case .battery: "15 fps, lowest energy use"
        case .balanced: "24 fps, the sweet spot"
        case .precision: "30 fps at 720p, best for eye tracking"
        }
    }

    public var framesPerSecond: Int {
        switch self {
        case .battery: 15
        case .balanced: 24
        case .precision: 30
        }
    }
    /// Full face detection runs every N frames; landmarks run every frame.
    public var detectEvery: Int {
        switch self {
        case .battery: 4
        case .balanced: 5
        case .precision: 3
        }
    }
}

public struct NodSettings: Codable, Sendable, Equatable {
    public var input: TrackingInput = .nose
    public var motion: MotionStyle = .relative
    /// Pointer speed multiplier, 0.25...3.
    public var speed: Double = 1.0
    /// 0 = linear, 1 = strong acceleration (slow is precise, fast travels far).
    public var acceleration: Double = 0.55
    /// 0 = raw, 1 = very smooth.
    public var smoothing: Double = 0.5
    /// Eye tracking smoothing, separate because gaze is far noisier.
    public var eyeSmoothing: Double = 0.75
    /// Joystick dead zone, fraction of the calibrated range.
    public var deadzone: Double = 0.12
    /// Joystick top speed in screen widths per second.
    public var joystickSpeed: Double = 0.9
    /// Hybrid: how far (fraction of screen width) the gaze must land from the
    /// pointer before the pointer jumps there.
    public var hybridJumpDistance: Double = 0.2

    public var gestures: [FaceGesture: GestureBinding] = Dictionary(uniqueKeysWithValues: FaceGesture.allCases.map { ($0, GestureBinding.defaults(for: $0)) })
    /// Freeze the pointer while a face gesture forms, so clicks land where aimed.
    public var holdSteadyWhileGesturing: Bool = true
    public var dwell = DwellSettings()

    public var showHalo: Bool = true
    public var playSounds: Bool = true
    /// Hand the pointer back when the physical mouse or trackpad moves.
    public var yieldToMouse: Bool = true
    public var cameraID: String?
    public var efficiency: EfficiencyMode = .balanced
    public var invertX: Bool = false
    public var invertY: Bool = false
    /// Display used for direct mapping and calibration (CGDirectDisplayID).
    public var displayID: UInt32?

    public var toggleHotKey: HotKeySpec = .defaultToggle
    public var recenterHotKey: HotKeySpec = .defaultRecenter
    public var calibrateHotKey: HotKeySpec = .defaultCalibrate

    public var hasCompletedOnboarding: Bool = false
    /// Bumped when the meaning of `speed` changes, so stored values can be
    /// migrated to keep the same feel.
    public var motionRevision: Int = NodSettings.currentMotionRevision
    public static let currentMotionRevision = 2

    public init() {}

    public func binding(for gesture: FaceGesture) -> GestureBinding {
        gestures[gesture] ?? .defaults(for: gesture)
    }

    /// Decodes leniently: every missing or unreadable key falls back to its
    /// default, so settings survive app updates that add new options.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NodSettings()
        input = c.value(.input, default: d.input)
        motion = c.value(.motion, default: d.motion)
        speed = c.value(.speed, default: d.speed)
        acceleration = c.value(.acceleration, default: d.acceleration)
        smoothing = c.value(.smoothing, default: d.smoothing)
        eyeSmoothing = c.value(.eyeSmoothing, default: d.eyeSmoothing)
        deadzone = c.value(.deadzone, default: d.deadzone)
        joystickSpeed = c.value(.joystickSpeed, default: d.joystickSpeed)
        hybridJumpDistance = c.value(.hybridJumpDistance, default: d.hybridJumpDistance)
        var g = d.gestures
        for (k, v) in c.value(.gestures, default: [FaceGesture: GestureBinding]()) { g[k] = v }
        gestures = g
        holdSteadyWhileGesturing = c.value(.holdSteadyWhileGesturing, default: d.holdSteadyWhileGesturing)
        dwell = c.value(.dwell, default: d.dwell)
        showHalo = c.value(.showHalo, default: d.showHalo)
        playSounds = c.value(.playSounds, default: d.playSounds)
        yieldToMouse = c.value(.yieldToMouse, default: d.yieldToMouse)
        cameraID = c.value(.cameraID, default: d.cameraID)
        efficiency = c.value(.efficiency, default: d.efficiency)
        invertX = c.value(.invertX, default: d.invertX)
        invertY = c.value(.invertY, default: d.invertY)
        displayID = c.value(.displayID, default: d.displayID)
        toggleHotKey = c.value(.toggleHotKey, default: d.toggleHotKey)
        recenterHotKey = c.value(.recenterHotKey, default: d.recenterHotKey)
        calibrateHotKey = c.value(.calibrateHotKey, default: d.calibrateHotKey)
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
