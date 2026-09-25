import Foundation

/// Fires once when the pointer rests inside a small circle for long enough.
/// After firing it stays disarmed until the pointer leaves the circle, so
/// resting on a button never produces a burst of clicks.
public struct DwellDetector: Sendable {
    public var dwellTime: Double
    public var radius: Double
    /// Stillness shorter than this is not shown, so the ring does not flicker
    /// on every tiny pause.
    public var showDelay: Double = 0.15

    private var anchor: Vec2?
    private var anchorTime: Double = 0
    private var armed = true

    public init(dwellTime: Double = 1.0, radius: Double = 28) {
        self.dwellTime = dwellTime
        self.radius = radius
    }

    public var isArmed: Bool { armed }

    public mutating func reset() {
        anchor = nil
        armed = true
    }

    /// Prevents firing until the pointer moves away, e.g. after a gesture click.
    public mutating func disarm() {
        armed = false
    }

    /// Returns the visible progress (0...1) and whether the dwell fired now.
    public mutating func update(position: Vec2, time: Double) -> (progress: Double, fired: Bool) {
        guard let a = anchor else {
            anchor = position
            anchorTime = time
            return (0, false)
        }
        if position.distance(to: a) > radius {
            anchor = position
            anchorTime = time
            armed = true
            return (0, false)
        }
        guard armed else { return (0, false) }
        let held = time - anchorTime
        let span = max(dwellTime - showDelay, 0.05)
        let progress = ((held - showDelay) / span).clamped(0, 1)
        if held >= dwellTime {
            armed = false
            return (1, true)
        }
        return (progress, false)
    }
}
