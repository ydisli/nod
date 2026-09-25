import Foundation

/// A small 2D vector used everywhere in the tracking maths.
/// Kept independent of CoreGraphics so NodCore stays portable and testable.
public struct Vec2: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public var length: Double { (x * x + y * y).squareRoot() }
    public var lengthSquared: Double { x * x + y * y }

    public var normalized: Vec2 {
        let l = length
        return l > 1e-12 ? Vec2(x / l, y / l) : .zero
    }

    public func distance(to other: Vec2) -> Double { (self - other).length }

    public func rotated(by angle: Double) -> Vec2 {
        let c = cos(angle), s = sin(angle)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    public func clamped(minX: Double, maxX: Double, minY: Double, maxY: Double) -> Vec2 {
        Vec2(Swift.min(Swift.max(x, minX), maxX), Swift.min(Swift.max(y, minY), maxY))
    }

    public var description: String { String(format: "(%.4f, %.4f)", x, y) }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func * (s: Double, a: Vec2) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func / (a: Vec2, s: Double) -> Vec2 { Vec2(a.x / s, a.y / s) }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    public static func -= (a: inout Vec2, b: Vec2) { a = a - b }

    public static func lerp(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 { a + (b - a) * t }

    public static func centroid(_ points: [Vec2]) -> Vec2 {
        guard !points.isEmpty else { return .zero }
        var sum = Vec2.zero
        for p in points { sum += p }
        return sum / Double(points.count)
    }
}

/// An axis-aligned rectangle in the same coordinate space as `Vec2`.
public struct Rect2: Hashable, Codable, Sendable {
    public var origin: Vec2
    public var size: Vec2

    public init(x: Double, y: Double, width: Double, height: Double) {
        origin = Vec2(x, y)
        size = Vec2(width, height)
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.x }
    public var maxY: Double { origin.y + size.y }
    public var width: Double { size.x }
    public var height: Double { size.y }
    public var center: Vec2 { Vec2(origin.x + size.x / 2, origin.y + size.y / 2) }

    public func contains(_ p: Vec2) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    public func clamp(_ p: Vec2) -> Vec2 {
        // Keep the point strictly inside so it maps to a real pixel on this display.
        p.clamped(minX: minX, maxX: maxX - 1, minY: minY, maxY: maxY - 1)
    }

    public func union(_ other: Rect2) -> Rect2 {
        let x0 = Swift.min(minX, other.minX), y0 = Swift.min(minY, other.minY)
        let x1 = Swift.max(maxX, other.maxX), y1 = Swift.max(maxY, other.maxY)
        return Rect2(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Point for a normalised (0...1) position inside the rectangle.
    public func point(atNormalized n: Vec2) -> Vec2 {
        Vec2(minX + n.x * width, minY + n.y * height)
    }

    /// Normalised (0...1) position of a point inside the rectangle.
    public func normalized(_ p: Vec2) -> Vec2 {
        Vec2((p.x - minX) / Swift.max(width, 1e-9), (p.y - minY) / Swift.max(height, 1e-9))
    }
}

public extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}

/// Classic smoothstep, 0 below `edge0`, 1 above `edge1`.
public func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = ((x - edge0) / (edge1 - edge0)).clamped(0, 1)
    return t * t * (3 - 2 * t)
}
