import Foundation

/// Face landmarks exactly as the camera sees them: pixel coordinates,
/// x to the right, y DOWN, not mirrored. Produced by the Vision layer.
public struct RawLandmarks: Sendable {
    public var imageSize: Vec2
    public var eyeA: [Vec2]
    public var eyeB: [Vec2]
    public var pupilA: Vec2?
    public var pupilB: Vec2?
    public var browA: [Vec2]
    public var browB: [Vec2]
    public var nose: [Vec2]
    public var noseCrest: [Vec2]
    public var outerLips: [Vec2]
    public var innerLips: [Vec2]
    public var contour: [Vec2]
    public var confidence: Double

    public init(imageSize: Vec2, eyeA: [Vec2], eyeB: [Vec2], pupilA: Vec2?, pupilB: Vec2?,
                browA: [Vec2], browB: [Vec2], nose: [Vec2], noseCrest: [Vec2],
                outerLips: [Vec2], innerLips: [Vec2], contour: [Vec2], confidence: Double) {
        self.imageSize = imageSize
        self.eyeA = eyeA
        self.eyeB = eyeB
        self.pupilA = pupilA
        self.pupilB = pupilB
        self.browA = browA
        self.browB = browB
        self.nose = nose
        self.noseCrest = noseCrest
        self.outerLips = outerLips
        self.innerLips = innerLips
        self.contour = contour
        self.confidence = confidence
    }
}

/// Expression measurements, all scale and roll invariant (interocular units
/// or ratios), so they do not change when you lean in or tilt your head.
public struct FaceMetrics: Sendable, Codable, Equatable {
    /// Gap between the inner lips.
    public var mouthOpen: Double
    /// Mouth corner to corner width.
    public var smile: Double
    /// Height of the eyebrows above the eyes.
    public var browRaise: Double
    /// Lid opening over eye width, from the user's point of view.
    public var leftEyeOpen: Double
    public var rightEyeOpen: Double

    public init(mouthOpen: Double, smile: Double, browRaise: Double, leftEyeOpen: Double, rightEyeOpen: Double) {
        self.mouthOpen = mouthOpen
        self.smile = smile
        self.browRaise = browRaise
        self.leftEyeOpen = leftEyeOpen
        self.rightEyeOpen = rightEyeOpen
    }

    public static let zero = FaceMetrics(mouthOpen: 0, smile: 0, browRaise: 0, leftEyeOpen: 0, rightEyeOpen: 0)
}

/// Normalised landmark polylines for drawing, mirrored like a mirror,
/// x in 0...1 of image width and y in 0...1 of image height.
public struct FaceMesh: Sendable, Equatable {
    public var contour: [Vec2] = []
    public var leftEye: [Vec2] = []
    public var rightEye: [Vec2] = []
    public var leftBrow: [Vec2] = []
    public var rightBrow: [Vec2] = []
    public var nose: [Vec2] = []
    public var noseCrest: [Vec2] = []
    public var outerLips: [Vec2] = []
    public var innerLips: [Vec2] = []
    public var pupils: [Vec2] = []
    public var noseTip: Vec2 = .zero

    public init() {}
}

/// Everything Nod needs from one camera frame.
public struct FaceSample: Sendable, Equatable {
    public var time: Double
    public var imageSize: Vec2
    /// Nose position in image pixels divided by image width (isotropic),
    /// mirrored so moving your head right increases x. y grows downward.
    public var nose: Vec2
    /// Interocular distance as a fraction of image width. Shrinks as you move away.
    public var faceScale: Double
    /// Face centre, 0...1 in both axes, mirrored.
    public var faceCenter: Vec2
    /// Pupil offset from the eye centre, in eye widths, averaged over both eyes.
    public var gaze: Vec2
    /// Nose offset from between the eyes in interocular units: a head
    /// rotation estimate that ignores translation.
    public var headAngle: Vec2
    public var metrics: FaceMetrics
    public var confidence: Double
    /// Mean brightness of the face, 0...1.
    public var brightness: Double
    public var mesh: FaceMesh

    public init(time: Double, imageSize: Vec2, nose: Vec2, faceScale: Double, faceCenter: Vec2, gaze: Vec2,
                headAngle: Vec2, metrics: FaceMetrics, confidence: Double, brightness: Double, mesh: FaceMesh) {
        self.time = time
        self.imageSize = imageSize
        self.nose = nose
        self.faceScale = faceScale
        self.faceCenter = faceCenter
        self.gaze = gaze
        self.headAngle = headAngle
        self.metrics = metrics
        self.confidence = confidence
        self.brightness = brightness
        self.mesh = mesh
    }

    /// Features used to calibrate and drive the eye pointer.
    public var eyeFeatures: [Double] {
        [gaze.x, gaze.y, (metrics.leftEyeOpen + metrics.rightEyeOpen) / 2, nose.x, nose.y]
    }

    /// Features used to calibrate and drive the direct nose pointer: where
    /// the nose is, plus the head angle, which carries the vertical signal
    /// far better than position alone.
    public var noseFeatures: [Double] { [nose.x, nose.y, headAngle.x, headAngle.y] }

    public func features(for input: TrackingInput) -> [Double] {
        input == .nose ? noseFeatures : eyeFeatures
    }
}

public enum FaceGeometry {
    /// Converts raw landmarks into a `FaceSample`.
    /// - Parameter mirror: true for a normal user-facing camera.
    public static func sample(from raw: RawLandmarks, time: Double, brightness: Double, mirror: Bool = true, flipVertical: Bool = false) -> FaceSample? {
        let w = raw.imageSize.x, h = raw.imageSize.y
        guard w > 0, h > 0, raw.eyeA.count >= 4, raw.eyeB.count >= 4, !raw.nose.isEmpty else { return nil }

        func m(_ p: Vec2) -> Vec2 { Vec2(mirror ? w - p.x : p.x, flipVertical ? h - p.y : p.y) }
        func mm(_ ps: [Vec2]) -> [Vec2] { ps.map(m) }

        // Assign eyes by where they appear in the mirrored image: the user's
        // left eye shows on the left, exactly like a mirror.
        var eyeL = mm(raw.eyeA), eyeR = mm(raw.eyeB)
        var pupilL = raw.pupilA.map(m), pupilR = raw.pupilB.map(m)
        var browL = mm(raw.browA), browR = mm(raw.browB)
        if Vec2.centroid(eyeL).x > Vec2.centroid(eyeR).x {
            swap(&eyeL, &eyeR)
            swap(&pupilL, &pupilR)
        }
        if !browL.isEmpty, !browR.isEmpty, Vec2.centroid(browL).x > Vec2.centroid(browR).x {
            swap(&browL, &browR)
        }

        let cL = Vec2.centroid(eyeL), cR = Vec2.centroid(eyeR)
        let iod = cL.distance(to: cR)
        guard iod > 4 else { return nil }
        let mid = (cL + cR) / 2
        let roll = atan2(cR.y - cL.y, cR.x - cL.x)

        // Face frame: origin between the eyes, x along the eye line, y down,
        // one unit = interocular distance.
        func f(_ p: Vec2) -> Vec2 { (p - mid).rotated(by: -roll) / iod }
        func ff(_ ps: [Vec2]) -> [Vec2] { ps.map(f) }

        let noseAll = mm(raw.nose + raw.noseCrest)
        let noseTip = Vec2.centroid(noseAll)

        let eyeLF = ff(eyeL), eyeRF = ff(eyeR)
        let openL = eyeOpenness(eyeLF), openR = eyeOpenness(eyeRF)

        var gazes: [Vec2] = []
        if let p = pupilL, let g = pupilOffset(eye: eyeLF, pupil: f(p)) { gazes.append(g) }
        if let p = pupilR, let g = pupilOffset(eye: eyeRF, pupil: f(p)) { gazes.append(g) }
        let gaze = Vec2.centroid(gazes)

        let innerF = ff(mm(raw.innerLips))
        let outerF = ff(mm(raw.outerLips))
        let mouthOpen = lipGap(innerF)
        let smile = spanX(outerF)

        var brow = 0.0
        if !browL.isEmpty, !browR.isEmpty {
            let bl = f(Vec2.centroid(browL)), br = f(Vec2.centroid(browR))
            let el = f(cL), er = f(cR)
            brow = ((el.y - bl.y) + (er.y - br.y)) / 2
        }

        let contourAll = mm(raw.contour)
        let faceCentre: Vec2 = {
            let pts = contourAll + eyeL + eyeR + noseAll
            let c = Vec2.centroid(pts)
            return Vec2(c.x / w, c.y / h)
        }()

        func n(_ p: Vec2) -> Vec2 { Vec2(p.x / w, p.y / h) }
        var mesh = FaceMesh()
        mesh.contour = contourAll.map(n)
        mesh.leftEye = eyeL.map(n)
        mesh.rightEye = eyeR.map(n)
        mesh.leftBrow = browL.map(n)
        mesh.rightBrow = browR.map(n)
        mesh.nose = mm(raw.nose).map(n)
        mesh.noseCrest = mm(raw.noseCrest).map(n)
        mesh.outerLips = mm(raw.outerLips).map(n)
        mesh.innerLips = mm(raw.innerLips).map(n)
        mesh.pupils = [pupilL, pupilR].compactMap { $0 }.map(n)
        mesh.noseTip = n(noseTip)

        return FaceSample(
            time: time,
            imageSize: raw.imageSize,
            nose: noseTip / w,
            faceScale: iod / w,
            faceCenter: faceCentre,
            gaze: gaze,
            headAngle: f(noseTip),
            metrics: FaceMetrics(mouthOpen: mouthOpen, smile: smile, browRaise: brow, leftEyeOpen: openL, rightEyeOpen: openR),
            confidence: raw.confidence,
            brightness: brightness,
            mesh: mesh
        )
    }

    /// Corners are the two points furthest apart along x; lids are the rest.
    static func corners(_ eye: [Vec2]) -> (Vec2, Vec2, [Vec2]) {
        let sorted = eye.enumerated().sorted { $0.element.x < $1.element.x }
        let a = sorted.first!.element, b = sorted.last!.element
        let rest = sorted.dropFirst().dropLast().map(\.element)
        return (a, b, rest)
    }

    /// Lid opening divided by corner to corner width.
    static func eyeOpenness(_ eye: [Vec2]) -> Double {
        guard eye.count >= 4 else { return 0 }
        let (a, b, lids) = corners(eye)
        let width = a.distance(to: b)
        guard width > 1e-9 else { return 0 }
        // Distance of each lid point from the corner line; upper lids sit at
        // negative y (y grows downward), lower lids at positive y.
        let dir = (b - a).normalized
        let normal = Vec2(-dir.y, dir.x)
        var upper: [Double] = [], lower: [Double] = []
        for p in lids {
            let d = (p - a).x * normal.x + (p - a).y * normal.y
            if d < 0 { upper.append(d) } else { lower.append(d) }
        }
        let up = upper.isEmpty ? 0 : upper.reduce(0, +) / Double(upper.count)
        let lo = lower.isEmpty ? 0 : lower.reduce(0, +) / Double(lower.count)
        return max(0, lo - up) / width
    }

    /// Pupil position relative to the midpoint of the eye corners, in eye widths.
    static func pupilOffset(eye: [Vec2], pupil: Vec2) -> Vec2? {
        guard eye.count >= 4 else { return nil }
        let (a, b, _) = corners(eye)
        let width = a.distance(to: b)
        guard width > 1e-9 else { return nil }
        return (pupil - (a + b) / 2) / width
    }

    /// Vertical gap between the middle of the upper and lower inner lip.
    /// The corners barely move when the mouth opens, so only the points
    /// nearest the centre line are used; they carry the whole signal.
    static func lipGap(_ inner: [Vec2]) -> Double {
        guard inner.count >= 4 else { return 0 }
        let meanY = inner.map(\.y).reduce(0, +) / Double(inner.count)
        let meanX = inner.map(\.x).reduce(0, +) / Double(inner.count)
        let upper = inner.filter { $0.y < meanY }
        let lower = inner.filter { $0.y >= meanY }
        guard let u = upper.min(by: { abs($0.x - meanX) < abs($1.x - meanX) }),
              let l = lower.min(by: { abs($0.x - meanX) < abs($1.x - meanX) })
        else { return 0 }
        return max(0, l.y - u.y)
    }

    static func spanX(_ pts: [Vec2]) -> Double {
        guard let lo = pts.map(\.x).min(), let hi = pts.map(\.x).max() else { return 0 }
        return hi - lo
    }
}
