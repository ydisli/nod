import NodCore
import SwiftUI

/// Maps mesh coordinates (x in 0...1 of image width, y in 0...1 of image
/// height) into a view.
struct FaceFraming {
    let scale: CGFloat
    let offset: CGPoint
    let aspect: Double

    func point(_ v: Vec2) -> CGPoint {
        CGPoint(x: offset.x + CGFloat(v.x) * scale, y: offset.y + CGFloat(v.y * aspect) * scale)
    }

    /// Centres on the face and sizes by eye distance, which does not change
    /// with expressions, so the face stays put while the mouth opens.
    static func face(_ mesh: FaceMesh, aspect: Double, in size: CGSize, fill: CGFloat = 0.8, centreDrop: Double = 0.95) -> FaceFraming {
        let l = Vec2.centroid(mesh.leftEye), r = Vec2.centroid(mesh.rightEye)
        let li = Vec2(l.x, l.y * aspect), ri = Vec2(r.x, r.y * aspect)
        let iod = max(li.distance(to: ri), 1e-4)
        let centre = (li + ri) / 2 + Vec2(0, iod * centreDrop)
        let s = min(size.width, size.height) * fill / CGFloat(iod * 2.75)
        return FaceFraming(
            scale: s,
            offset: CGPoint(x: size.width / 2 - CGFloat(centre.x) * s, y: size.height / 2 - CGFloat(centre.y) * s),
            aspect: aspect
        )
    }
}

/// Draws the face drawing in Nod's mark: a soft glow pass, crisp lines,
/// landmark dots, pupils and the nose tip.
enum MeshRenderer {
    struct Style {
        var line: Color = Theme.teal
        var lineWidth: CGFloat = 1.3
        var dots = true
        var glow = true
        var noseColor: Color = Theme.gold
        var noseRadius: CGFloat = 4.5
        var opacity: Double = 1
    }

    static func draw(_ mesh: FaceMesh, framing f: FaceFraming, in ctx: inout GraphicsContext,
                     style: Style = Style()) {
        func path(_ pts: [Vec2], closed: Bool) -> Path {
            var p = Path()
            guard let first = pts.first else { return p }
            p.move(to: f.point(first))
            for v in pts.dropFirst() { p.addLine(to: f.point(v)) }
            if closed { p.closeSubpath() }
            return p
        }
        let lines: [(Path, Double)] = [
            (path(mesh.contour, closed: false), 0.55),
            (path(mesh.leftBrow, closed: true), 0.8),
            (path(mesh.rightBrow, closed: true), 0.8),
            (path(mesh.leftEye, closed: true), 1),
            (path(mesh.rightEye, closed: true), 1),
            (path(mesh.nose, closed: false), 0.8),
            (path(Array(mesh.noseCrest.prefix(4)), closed: false), 0.8),
            (path(mesh.outerLips, closed: true), 0.9),
            (path(mesh.innerLips, closed: true), 0.9),
        ]

        ctx.opacity = style.opacity

        if style.glow {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: style.lineWidth * 3))
                for (p, a) in lines {
                    layer.stroke(p, with: .color(style.line.opacity(0.55 * a)), style: StrokeStyle(lineWidth: style.lineWidth * 2.2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        for (p, a) in lines {
            ctx.stroke(p, with: .color(style.line.opacity(a)), style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, lineJoin: .round))
        }

        if style.dots {
            let all = mesh.contour + mesh.leftEye + mesh.rightEye + mesh.leftBrow + mesh.rightBrow + mesh.nose + mesh.outerLips
            let r = max(style.lineWidth * 0.9, 1)
            for v in all {
                let c = f.point(v)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.75)))
            }
        }

        for v in mesh.pupils {
            let c = f.point(v)
            let r = style.lineWidth * 1.6
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white))
        }

        let tip = f.point(mesh.noseTip)
        let nr = style.noseRadius
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: nr * 1.2))
            layer.fill(Path(ellipseIn: CGRect(x: tip.x - nr * 2, y: tip.y - nr * 2, width: nr * 4, height: nr * 4)), with: .color(style.noseColor.opacity(0.7)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - nr, y: tip.y - nr, width: nr * 2, height: nr * 2)), with: .color(style.noseColor))
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - nr * 0.4, y: tip.y - nr * 0.4, width: nr * 0.8, height: nr * 0.8)), with: .color(.white))
    }
}

/// The classic arrow pointer, tip at the top left of its rect.
struct CursorArrow: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        var path = Path()
        path.move(to: p(0, 0))
        path.addLine(to: p(0, 0.86))
        path.addLine(to: p(0.25, 0.655))
        path.addLine(to: p(0.415, 1.0))
        path.addLine(to: p(0.57, 0.93))
        path.addLine(to: p(0.405, 0.6))
        path.addLine(to: p(0.72, 0.6))
        path.closeSubpath()
        return path
    }
}

/// The Nod mark: a face constellation whose nose is the tip of the pointer.
/// Used in the UI and rendered into the app icon.
struct NodMark: View {
    var size: CGFloat
    /// Draws the face mesh; off for tiny sizes where it would be mush.
    var detailed = true
    /// App icon style: squircle inset on a transparent canvas with a shadow.
    var iconCanvas = false

    var body: some View {
        let inset: CGFloat = iconCanvas ? size * 0.098 : 0
        let s = size - inset * 2
        ZStack {
            if iconCanvas {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(.black.opacity(0.35))
                    .frame(width: s, height: s)
                    .blur(radius: size * 0.012)
                    .offset(y: size * 0.01)
            }
            mark(s)
                .frame(width: s, height: s)
                .clipShape(RoundedRectangle(cornerRadius: s * 0.225, style: .continuous))
        }
        .frame(width: size, height: size)
    }

    private func mark(_ s: CGFloat) -> some View {
        let mesh = DemoFace.posed(yaw: -0.22, pitch: 0.06)
        return ZStack {
            LinearGradient(colors: [Color(hex: 0x1D2536), Color(hex: 0x0A0D14)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.blue.opacity(0.35), .clear], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: s * 0.7)
            Canvas { ctx, size in
                let f = FaceFraming.face(mesh, aspect: 1, in: size, fill: 0.68, centreDrop: 0.7)
                let tip = f.point(mesh.noseTip)
                let unit = size.width
                if detailed {
                    var style = MeshRenderer.Style()
                    style.lineWidth = max(unit / 170, 0.8)
                    style.line = Theme.teal
                    style.dots = unit > 120
                    style.opacity = 0.7
                    style.noseRadius = 0
                    MeshRenderer.draw(mesh, framing: f, in: &ctx, style: style)
                    ctx.opacity = 1

                    // Close the face with a dotted forehead: Vision has no
                    // forehead points, and without it the face reads as a shield.
                    if let a = mesh.contour.first, let b = mesh.contour.last {
                        let pa = f.point(a), pb = f.point(b)
                        let centre = CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
                        let rx = abs(pb.x - pa.x) / 2
                        var arc = Path()
                        arc.addArc(center: .zero, radius: 1, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                        arc = arc.applying(CGAffineTransform(translationX: centre.x, y: centre.y).scaledBy(x: rx, y: rx * 0.72))
                        ctx.stroke(arc, with: .color(Theme.teal.opacity(0.45)),
                                   style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, dash: [0.1, style.lineWidth * 4.2]))
                    }
                }
                // Tracking rings around the nose tip, anodized.
                let ringColors: [Color] = [Theme.violet, Theme.blue, Theme.teal]
                for (i, color) in ringColors.enumerated() {
                    let r = unit * (0.15 - CGFloat(i) * 0.037)
                    let rect = CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.5 + 0.2 * Double(i))),
                               lineWidth: max(unit * 0.011, 0.8))
                }
                let core = unit * 0.036
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: core * 1.1))
                    l.fill(Path(ellipseIn: CGRect(x: tip.x - core * 2, y: tip.y - core * 2, width: core * 4, height: core * 4)), with: .color(Theme.teal))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - core, y: tip.y - core, width: core * 2, height: core * 2)), with: .color(Theme.teal))
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - core * 0.4, y: tip.y - core * 0.4, width: core * 0.8, height: core * 0.8)), with: .color(.white))

                // The pointer, its tip on the nose. Bigger when the face is
                // not drawn so small icons stay legible.
                let aw = unit * (detailed ? 0.2 : 0.34), ah = aw * 1.42
                let arrowRect = CGRect(x: tip.x + unit * 0.004, y: tip.y + unit * 0.004, width: aw, height: ah)
                let arrow = CursorArrow().path(in: arrowRect)
                ctx.drawLayer { l in
                    l.addFilter(.shadow(color: .black.opacity(0.6), radius: unit * 0.02, x: 0, y: unit * 0.01))
                    l.fill(arrow, with: .color(.white))
                }
                ctx.stroke(arrow, with: .color(Color(hex: 0x0A0D14)), style: StrokeStyle(lineWidth: max(unit * 0.008, 0.6), lineJoin: .round))
            }
            RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                              lineWidth: max(s * 0.01, 0.5))
        }
    }
}
