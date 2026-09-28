import AppKit

/// Nod's menu bar icon: the face outline from the app icon with the pointer
/// on the nose, drawn as a template so macOS tints it for light and dark
/// menu bars. Its own shape, so it is never mistaken for the AirPods icon
/// macOS shows while headphones are connected.
@MainActor
enum StatusIcon {
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)

            // The jaw line, an open U.
            let face = CGMutablePath()
            face.move(to: CGPoint(x: 2.8, y: 5.2))
            face.addLine(to: CGPoint(x: 2.8, y: 8.8))
            face.addCurve(to: CGPoint(x: 9, y: 16.4), control1: CGPoint(x: 2.8, y: 13.2), control2: CGPoint(x: 5.8, y: 16.4))
            face.addCurve(to: CGPoint(x: 15.2, y: 8.8), control1: CGPoint(x: 12.2, y: 16.4), control2: CGPoint(x: 15.2, y: 13.2))
            face.addLine(to: CGPoint(x: 15.2, y: 5.2))
            ctx.addPath(face)
            ctx.setLineWidth(1.5)
            ctx.strokePath()

            // Brows.
            ctx.move(to: CGPoint(x: 4.9, y: 4.6)); ctx.addLine(to: CGPoint(x: 7.3, y: 4.1))
            ctx.move(to: CGPoint(x: 10.7, y: 4.1)); ctx.addLine(to: CGPoint(x: 13.1, y: 4.6))
            ctx.setLineWidth(1.3)
            ctx.strokePath()

            // The pointer, tip on the nose, cut clear of the lines around it.
            let pointer = arrow(tip: CGPoint(x: 8.3, y: 6.6), scale: 0.78)
            ctx.setBlendMode(.clear)
            ctx.addPath(pointer)
            ctx.setLineWidth(2.0)
            ctx.strokePath()
            ctx.setBlendMode(.normal)
            ctx.addPath(pointer)
            ctx.fillPath()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Nod"
        return img
    }()

    private static func arrow(tip: CGPoint, scale s: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x, y: tip.y + 8.2 * s))
        p.addLine(to: CGPoint(x: tip.x + 2.0 * s, y: tip.y + 6.2 * s))
        p.addLine(to: CGPoint(x: tip.x + 3.4 * s, y: tip.y + 9.0 * s))
        p.addLine(to: CGPoint(x: tip.x + 4.6 * s, y: tip.y + 8.4 * s))
        p.addLine(to: CGPoint(x: tip.x + 3.3 * s, y: tip.y + 5.7 * s))
        p.addLine(to: CGPoint(x: tip.x + 6.0 * s, y: tip.y + 5.7 * s))
        p.closeSubpath()
        return p
    }
}
