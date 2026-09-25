import Foundation

/// Finds the iris inside an eye outline by looking for its darkest pixels.
///
/// Vision's pupil landmark is a good prior but tends to stick to the eye
/// centre. The iris is the darkest blob between the lids, so a weighted
/// centroid of the darkest pixels inside the (slightly shrunk) eye outline
/// follows gaze more faithfully. Costs a few hundred pixel reads per eye.
public enum PupilLocator {
    /// - Parameters:
    ///   - luma: 8-bit grey image, row major.
    ///   - width, height, bytesPerRow: image layout.
    ///   - eye: eye outline in pixel coordinates of this image (y down).
    ///   - darkFraction: share of the eye area treated as iris.
    /// - Returns: the iris centre in pixel coordinates, or nil if the eye is
    ///   too small or closed.
    public static func locate(luma: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int,
                              eye: [Vec2], darkFraction: Double = 0.3) -> Vec2? {
        guard eye.count >= 3 else { return nil }
        // Shrink the outline towards its centre to stay clear of lashes and
        // lid shadows, which are also dark.
        let c = Vec2.centroid(eye)
        let poly = eye.map { c + ($0 - c) * 0.85 }

        let xs = poly.map(\.x), ys = poly.map(\.y)
        let x0 = max(0, Int(xs.min()!.rounded(.down)))
        let x1 = min(width - 1, Int(xs.max()!.rounded(.up)))
        let y0 = max(0, Int(ys.min()!.rounded(.down)))
        let y1 = min(height - 1, Int(ys.max()!.rounded(.up)))
        guard x1 - x0 >= 4, y1 - y0 >= 2 else { return nil }

        var values: [UInt8] = []
        var coords: [(Int, Int)] = []
        values.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))
        for y in y0...y1 {
            let row = luma + y * bytesPerRow
            for x in x0...x1 where contains(poly, Vec2(Double(x) + 0.5, Double(y) + 0.5)) {
                values.append(row[x])
                coords.append((x, y))
            }
        }
        guard values.count >= 12 else { return nil }

        // Threshold at the requested percentile using a histogram (no sort).
        var hist = [Int](repeating: 0, count: 256)
        for v in values { hist[Int(v)] += 1 }
        let want = max(1, Int(Double(values.count) * darkFraction))
        var acc = 0, threshold = 0
        for i in 0..<256 {
            acc += hist[i]
            if acc >= want {
                threshold = i
                break
            }
        }
        // Weight darker pixels more; +1 keeps pixels exactly at the threshold.
        var sx = 0.0, sy = 0.0, sw = 0.0
        for (i, v) in values.enumerated() where Int(v) <= threshold {
            let w = Double(threshold - Int(v) + 1)
            sx += (Double(coords[i].0) + 0.5) * w
            sy += (Double(coords[i].1) + 0.5) * w
            sw += w
        }
        guard sw > 0 else { return nil }
        return Vec2(sx / sw, sy / sw)
    }

    /// Even-odd point in polygon test.
    static func contains(_ poly: [Vec2], _ p: Vec2) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}
