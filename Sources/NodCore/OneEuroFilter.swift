import Foundation

/// The 1€ filter (Casiez, Roussel & Vogel, CHI 2012).
///
/// A low-pass filter whose cutoff rises with speed: when the head is still it
/// smooths hard (no jitter), when the head moves fast it barely smooths (no lag).
/// That trade-off is exactly what a head or eye pointer needs.
public struct OneEuroFilter: Sendable {
    /// Cutoff at rest, in Hz. Lower = steadier but laggier.
    public var minCutoff: Double
    /// How quickly the cutoff opens up with speed.
    public var beta: Double
    /// Cutoff for the derivative estimate, in Hz.
    public var derivativeCutoff: Double

    private var lastValue: Double?
    private var lastDerivative: Double = 0
    private var lastTime: Double?

    public init(minCutoff: Double = 1.0, beta: Double = 0.007, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    public mutating func reset() {
        lastValue = nil
        lastTime = nil
        lastDerivative = 0
    }

    public mutating func filter(_ value: Double, at time: Double) -> Double {
        guard let prev = lastValue, let prevTime = lastTime else {
            lastValue = value
            lastTime = time
            return value
        }
        // Guard against duplicate or out of order timestamps.
        let dt = max(time - prevTime, 1e-3)
        let rawDerivative = (value - prev) / dt
        let aD = Self.alpha(cutoff: derivativeCutoff, dt: dt)
        let derivative = lastDerivative + aD * (rawDerivative - lastDerivative)
        let cutoff = minCutoff + beta * abs(derivative)
        let a = Self.alpha(cutoff: cutoff, dt: dt)
        let result = prev + a * (value - prev)
        lastValue = result
        lastDerivative = derivative
        lastTime = time
        return result
    }
}

/// Two independent 1€ filters, one per axis.
public struct OneEuroFilter2D: Sendable {
    private var fx: OneEuroFilter
    private var fy: OneEuroFilter

    public init(minCutoff: Double = 1.0, beta: Double = 0.007, derivativeCutoff: Double = 1.0) {
        fx = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
        fy = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
    }

    public mutating func configure(minCutoff: Double, beta: Double) {
        fx.minCutoff = minCutoff
        fy.minCutoff = minCutoff
        fx.beta = beta
        fy.beta = beta
    }

    public mutating func reset() {
        fx.reset()
        fy.reset()
    }

    public mutating func filter(_ v: Vec2, at time: Double) -> Vec2 {
        Vec2(fx.filter(v.x, at: time), fy.filter(v.y, at: time))
    }
}

public extension OneEuroFilter2D {
    /// Maps the user-facing "smoothing" slider (0 = raw, 1 = very smooth) onto
    /// filter parameters. The units of `beta` depend on the signal, so callers
    /// pass a `speedScale` that is roughly "one typical fast movement per second".
    static func parameters(smoothing: Double, speedScale: Double) -> (minCutoff: Double, beta: Double) {
        let s = smoothing.clamped(0, 1)
        // 8 Hz (almost raw) down to 0.35 Hz (very steady) at rest.
        let minCutoff = 8.0 * pow(0.35 / 8.0, s)
        // A fast movement (speedScale units per second) opens the cutoff by
        // 4 to 7 Hz, so moving never feels laggy even at heavy smoothing.
        let beta = (7.0 - 3.0 * s) / max(speedScale, 1e-6)
        return (minCutoff, beta)
    }
}
