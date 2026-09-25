import Foundation
import NodCore

/// A real Vision landmark set (the author's face, as 76 anonymous points),
/// used for illustrations before the camera is allowed and for the icon.
/// Coordinates are a unit square around the face, mirrored, y down.
enum DemoFace {
    private typealias V = Vec2

    static let base: FaceMesh = {
        var m = FaceMesh()
        m.contour = [V(0.0034, 0.1396), V(0.0000, 0.2753), V(0.0028, 0.4130), V(0.0159, 0.5501), V(0.0586, 0.6803), V(0.1377, 0.7935), V(0.2389, 0.8868), V(0.3578, 0.9556), V(0.4943, 0.9807), V(0.6314, 0.9602), V(0.7511, 0.8908), V(0.8514, 0.7981), V(0.9296, 0.6849), V(0.9727, 0.5552), V(0.9905, 0.4198), V(0.9986, 0.2838), V(1.0000, 0.1502)]
        m.leftEye = [V(0.2144, 0.1399), V(0.2679, 0.1172), V(0.3447, 0.1214), V(0.3982, 0.1442), V(0.3430, 0.1442), V(0.2685, 0.1490)]
        m.rightEye = [V(0.8194, 0.1433), V(0.7682, 0.1192), V(0.6911, 0.1226), V(0.6365, 0.1453), V(0.6920, 0.1468), V(0.7651, 0.1524)]
        m.leftBrow = [V(0.1086, 0.0913), V(0.2673, 0.0193), V(0.4414, 0.0340), V(0.4369, 0.0947), V(0.2742, 0.0850), V(0.1172, 0.1243)]
        m.rightBrow = [V(0.9295, 0.0912), V(0.7793, 0.0210), V(0.6126, 0.0381), V(0.6146, 0.0957), V(0.7716, 0.0853), V(0.9205, 0.1246)]
        m.nose = [V(0.5159, 0.1968), V(0.6331, 0.3049), V(0.6416, 0.4078), V(0.5731, 0.4232), V(0.5068, 0.4465), V(0.4420, 0.4209), V(0.3754, 0.4019), V(0.3879, 0.3006)]
        m.noseCrest = [V(0.5191, 0.1059), V(0.5159, 0.1968), V(0.5128, 0.2910), V(0.5091, 0.3820), V(0.5990, 0.3695), V(0.4198, 0.3666)]
        m.outerLips = [V(0.6792, 0.5495), V(0.6166, 0.5415), V(0.5555, 0.5415), V(0.5051, 0.5501), V(0.4551, 0.5404), V(0.3959, 0.5392), V(0.3339, 0.5427), V(0.2759, 0.5535), V(0.3373, 0.6160), V(0.4181, 0.6564), V(0.5031, 0.6706), V(0.5907, 0.6633), V(0.6738, 0.6263), V(0.7386, 0.5666)]
        m.innerLips = [V(0.5978, 0.5700), V(0.5048, 0.5774), V(0.4135, 0.5660), V(0.4118, 0.6001), V(0.5046, 0.6160), V(0.5984, 0.6058)]
        m.pupils = [V(0.2848, 0.1287), V(0.7461, 0.1305)]
        m.noseTip = V(0.5108, 0.3296)
        return m
    }()

    /// The demo face turned by `yaw`/`pitch` (radians, small), with the mouth
    /// opened by `mouth` (0...1) and eyes closed by `blink` (0...1).
    /// Depth per feature gives a convincing parallax without a 3D model.
    static func posed(yaw: Double, pitch: Double, mouth: Double = 0, blink: Double = 0) -> FaceMesh {
        let c = Vec2(0.5, 0.45)
        func move(_ p: Vec2, depth: Double) -> Vec2 {
            let d = p - c
            return Vec2(c.x + d.x * cos(yaw) + depth * sin(yaw),
                        c.y + d.y * cos(pitch) + depth * sin(pitch))
        }
        func all(_ ps: [Vec2], _ depth: Double) -> [Vec2] { ps.map { move($0, depth: depth) } }

        var m = base
        m.contour = base.contour.map { p in
            // The jaw sits behind the face plane at the sides.
            move(p, depth: -0.12 * (1 - abs(p.x - 0.5) * 2) - 0.02)
        }
        m.leftBrow = all(base.leftBrow, 0.06)
        m.rightBrow = all(base.rightBrow, 0.06)
        m.nose = all(base.nose, 0.18)
        m.noseCrest = base.noseCrest.enumerated().map { i, p in move(p, depth: 0.08 + 0.05 * Double(i)) }
        m.noseTip = move(base.noseTip, depth: 0.24)

        let open = mouth.clamped(0, 1) * 0.09
        func lipDrop(_ ps: [Vec2]) -> [Vec2] {
            let midY = ps.map(\.y).reduce(0, +) / Double(ps.count)
            return ps.map { p in
                let centre = 1 - min(abs(p.x - 0.5) / 0.25, 1)
                return p.y > midY ? Vec2(p.x, p.y + open * centre) : p
            }
        }
        m.outerLips = all(lipDrop(base.outerLips), 0.1)
        m.innerLips = all(lipDrop(base.innerLips), 0.08)

        func blinkEye(_ ps: [Vec2]) -> [Vec2] {
            let midY = ps.map(\.y).reduce(0, +) / Double(ps.count)
            return ps.map { Vec2($0.x, midY + ($0.y - midY) * (1 - blink.clamped(0, 1))) }
        }
        m.leftEye = all(blinkEye(base.leftEye), 0.04)
        m.rightEye = all(blinkEye(base.rightEye), 0.04)
        m.pupils = blink > 0.6 ? [] : all(base.pupils, 0.05)
        return m
    }
}
