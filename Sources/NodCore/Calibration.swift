import Foundation

/// One observation gathered while the user looked or pointed at a target.
public struct CalibrationPoint: Sendable, Equatable {
    /// Target position, normalised to the calibration display (0...1, y down).
    public var target: Vec2
    /// The tracking features captured for that target.
    public var features: [Double]

    public init(target: Vec2, features: [Double]) {
        self.target = target
        self.features = features
    }
}

/// How the features are expanded before the linear fit.
public enum CalibrationBasis: String, Codable, Sendable, CaseIterable {
    /// `1, a, b` plus linear terms for any extra features.
    case affine
    /// `1, a, b, a², b², ab` plus linear terms for any extra features.
    /// Captures the curvature of turning a head or rolling an eye.
    case quadratic
}

/// A fitted mapping from tracking features to a normalised screen position.
public struct PointerCalibration: Codable, Sendable, Equatable {
    public var basis: CalibrationBasis
    public var featureMean: [Double]
    public var featureScale: [Double]
    public var coefficientsX: [Double]
    public var coefficientsY: [Double]
    /// Mean fit error, in normalised display units (multiply by width for points).
    public var meanError: Double
    public var sampleCount: Int

    public var featureCount: Int { featureMean.count }

    public init(basis: CalibrationBasis, featureMean: [Double], featureScale: [Double],
                coefficientsX: [Double], coefficientsY: [Double], meanError: Double, sampleCount: Int) {
        self.basis = basis
        self.featureMean = featureMean
        self.featureScale = featureScale
        self.coefficientsX = coefficientsX
        self.coefficientsY = coefficientsY
        self.meanError = meanError
        self.sampleCount = sampleCount
    }

    static func expand(_ z: [Double], basis: CalibrationBasis) -> [Double] {
        var row: [Double] = [1]
        guard z.count >= 2 else { return row + z }
        let a = z[0], b = z[1]
        row.append(a)
        row.append(b)
        if basis == .quadratic {
            row.append(a * a)
            row.append(b * b)
            row.append(a * b)
        }
        if z.count > 2 { row.append(contentsOf: z[2...]) }
        return row
    }

    private func standardize(_ f: [Double]) -> [Double] {
        var z = [Double](repeating: 0, count: featureMean.count)
        for i in 0..<min(f.count, z.count) {
            z[i] = (f[i] - featureMean[i]) / featureScale[i]
        }
        return z
    }

    /// Normalised screen position (0...1 inside the display) for the features.
    public func predict(_ features: [Double]) -> Vec2 {
        let row = Self.expand(standardize(features), basis: basis)
        var x = 0.0, y = 0.0
        for i in 0..<min(row.count, coefficientsX.count) {
            x += row[i] * coefficientsX[i]
            y += row[i] * coefficientsY[i]
        }
        return Vec2(x, y)
    }

    /// Fits a mapping. Performs one outlier rejection pass so a blink or a
    /// glance away during a target does not bend the whole calibration.
    public static func fit(points: [CalibrationPoint], basis: CalibrationBasis, ridge: Double = 1e-3) -> PointerCalibration? {
        guard let n = points.first?.features.count, n >= 2 else { return nil }
        let usable = points.filter { $0.features.count == n && $0.features.allSatisfy(\.isFinite) }
        let needed = expand([Double](repeating: 0, count: n), basis: basis).count
        guard usable.count >= needed + 1 else { return nil }

        var first = fitOnce(usable, basis: basis, ridge: ridge)
        guard var model = first else { return nil }

        let residuals = usable.map { model.predict($0.features).distance(to: $0.target) }
        let median = residuals.sorted()[residuals.count / 2]
        let cutoff = max(median * 3.0, 0.02)
        let kept = zip(usable, residuals).filter { $0.1 <= cutoff }.map(\.0)
        if kept.count < usable.count, kept.count >= needed + 1 {
            first = fitOnce(kept, basis: basis, ridge: ridge)
            if let refit = first { model = refit }
        }
        return model
    }

    private static func fitOnce(_ points: [CalibrationPoint], basis: CalibrationBasis, ridge: Double) -> PointerCalibration? {
        let n = points[0].features.count
        var mean = [Double](repeating: 0, count: n)
        for p in points { for i in 0..<n { mean[i] += p.features[i] } }
        mean = mean.map { $0 / Double(points.count) }
        var scale = [Double](repeating: 0, count: n)
        for p in points { for i in 0..<n { scale[i] += pow(p.features[i] - mean[i], 2) } }
        scale = scale.map { max(($0 / Double(points.count)).squareRoot(), 1e-9) }

        let rows = points.map { p -> [Double] in
            let z = (0..<n).map { (p.features[$0] - mean[$0]) / scale[$0] }
            return expand(z, basis: basis)
        }
        guard let cx = LeastSquares.ridge(rows: rows, targets: points.map(\.target.x), ridge: ridge),
              let cy = LeastSquares.ridge(rows: rows, targets: points.map(\.target.y), ridge: ridge)
        else { return nil }

        var model = PointerCalibration(
            basis: basis, featureMean: mean, featureScale: scale,
            coefficientsX: cx, coefficientsY: cy, meanError: 0, sampleCount: points.count
        )
        let err = points.map { model.predict($0.features).distance(to: $0.target) }
        model.meanError = err.reduce(0, +) / Double(err.count)
        return model
    }
}

/// Everything a finished calibration run produces for one input method.
public struct CalibrationProfile: Codable, Sendable, Equatable {
    public var input: TrackingInput
    public var createdAt: Date
    /// Size of the calibration display in points.
    public var displaySize: Vec2
    public var displayID: UInt32?
    /// Direct mapping from features to the display.
    public var mapping: PointerCalibration
    /// Resting nose position (image units, see `FaceSample.nose`).
    public var neutralNose: Vec2
    /// Interocular distance at rest, as a fraction of image width.
    public var neutralFaceScale: Double
    /// Nose travel, in interocular units, needed to cross the whole display.
    /// Drives the gain of relative and joystick motion.
    public var travel: Vec2

    public init(input: TrackingInput, createdAt: Date, displaySize: Vec2, displayID: UInt32?,
                mapping: PointerCalibration, neutralNose: Vec2, neutralFaceScale: Double, travel: Vec2) {
        self.input = input
        self.createdAt = createdAt
        self.displaySize = displaySize
        self.displayID = displayID
        self.mapping = mapping
        self.neutralNose = neutralNose
        self.neutralFaceScale = neutralFaceScale
        self.travel = travel
    }

    /// Mean error in display points.
    public var meanErrorPoints: Double { mapping.meanError * max(displaySize.x, displaySize.y) }

    /// Estimates how far (in interocular units) the nose moves to sweep the
    /// display, from nose positions recorded at known targets.
    /// Uses the regression slope per axis, which is robust to a noisy target.
    public static func estimateTravel(targets: [Vec2], noses: [Vec2], faceScale: Double) -> Vec2 {
        func slope(_ t: [Double], _ f: [Double]) -> Double {
            let mt = t.reduce(0, +) / Double(t.count)
            let mf = f.reduce(0, +) / Double(f.count)
            var cov = 0.0, varT = 0.0
            for i in 0..<t.count {
                cov += (t[i] - mt) * (f[i] - mf)
                varT += (t[i] - mt) * (t[i] - mt)
            }
            return varT > 1e-12 ? cov / varT : 0
        }
        guard targets.count == noses.count, targets.count >= 2, faceScale > 0 else { return Vec2(0.5, 0.35) }
        // Feature change per full display width, converted to interocular units.
        let sx = abs(slope(targets.map(\.x), noses.map(\.x))) / faceScale
        let sy = abs(slope(targets.map(\.y), noses.map(\.y))) / faceScale
        // Fall back to sensible defaults if a sweep was barely performed.
        return Vec2(sx > 0.02 ? sx : 0.5, sy > 0.02 ? sy : 0.35)
    }
}

/// The standard 9 point layout (3 by 3), inset from the display edges.
public enum CalibrationLayout {
    public static func targets(count: Int = 9, inset: Double = 0.08) -> [Vec2] {
        let lo = inset, mid = 0.5, hi = 1 - inset
        let nine = [
            Vec2(mid, mid),
            Vec2(lo, lo), Vec2(mid, lo), Vec2(hi, lo),
            Vec2(hi, mid), Vec2(hi, hi), Vec2(mid, hi),
            Vec2(lo, hi), Vec2(lo, mid),
        ]
        if count <= 5 {
            return [Vec2(mid, mid), Vec2(lo, lo), Vec2(hi, lo), Vec2(hi, hi), Vec2(lo, hi)]
        }
        return nine
    }
}
