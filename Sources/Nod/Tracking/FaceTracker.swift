import CoreVideo
import Foundation
import NodCore
import Vision

/// Runs Vision on camera frames and turns the result into a `FaceSample`.
///
/// Full face detection is the expensive part (about 5 ms), landmarks on a
/// known face box cost about 1 ms. So detection runs every few frames and in
/// between the previous box is carried along with the landmarks.
/// Not thread safe: used only on the tracking queue.
final class FaceTracker {
    private let sequence = VNSequenceRequestHandler()
    // Requests are built once. Creating one per frame and setting its revision
    // made Vision resolve its model files every time, a measurable CPU cost.
    private let rectangles: VNDetectFaceRectanglesRequest = {
        let r = VNDetectFaceRectanglesRequest()
        r.revision = VNDetectFaceRectanglesRequestRevision3
        return r
    }()
    private let landmarks: VNDetectFaceLandmarksRequest = {
        let r = VNDetectFaceLandmarksRequest()
        r.revision = VNDetectFaceLandmarksRequestRevision3
        r.constellation = .constellation76Points
        return r
    }()
    /// Full detections run so far, for diagnostics.
    private(set) var detections = 0
    private var trackedFace: VNFaceObservation?
    private var detectCentroid: CGPoint?
    private var detectBox: CGRect = .zero
    private var framesSinceDetect = 0

    /// Blend between Vision's pupil landmark (0) and the dark-pixel iris
    /// estimate (1). Vision's point tends to stick to the eye centre.
    var irisWeight = 0.6

    func reset() {
        trackedFace = nil
        detectCentroid = nil
        framesSinceDetect = 0
    }

    func process(_ pixelBuffer: CVPixelBuffer, time: Double, detectEvery: Int) -> FaceSample? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var face = trackedFace
        if face == nil || framesSinceDetect >= max(detectEvery, 1) {
            face = detect(pixelBuffer)
            framesSinceDetect = 0
            detectCentroid = nil
            if let f = face { detectBox = f.boundingBox }
        } else {
            framesSinceDetect += 1
        }
        guard let faceBox = face else {
            trackedFace = nil
            return nil
        }

        let request = landmarks
        request.inputFaceObservations = [faceBox]
        do {
            try sequence.perform([request], on: pixelBuffer, orientation: .up)
        } catch {
            trackedFace = nil
            return nil
        }
        guard let obs = request.results?.first, let lm = obs.landmarks, lm.confidence > 0.35 else {
            trackedFace = nil
            return nil
        }

        let size = CGSize(width: width, height: height)
        // Vision returns image coordinates with y up; NodCore wants y down.
        func pts(_ r: VNFaceLandmarkRegion2D?) -> [Vec2] {
            guard let r else { return [] }
            return r.pointsInImage(imageSize: size).map { Vec2(Double($0.x), Double(height) - Double($0.y)) }
        }
        let eyeA = pts(lm.leftEye), eyeB = pts(lm.rightEye)
        var pupilA = pts(lm.leftPupil).first
        var pupilB = pts(lm.rightPupil).first

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let luma = LumaPlane(pixelBuffer)
        if let luma {
            pupilA = refine(pupilA, eye: eyeA, luma: luma)
            pupilB = refine(pupilB, eye: eyeB, luma: luma)
        }
        let box = obs.boundingBox
        let brightness = luma?.meanBrightness(in: CGRect(
            x: box.minX * CGFloat(width), y: (1 - box.maxY) * CGFloat(height),
            width: box.width * CGFloat(width), height: box.height * CGFloat(height)
        )) ?? 0.5

        let raw = RawLandmarks(
            imageSize: Vec2(Double(width), Double(height)),
            eyeA: eyeA, eyeB: eyeB, pupilA: pupilA, pupilB: pupilB,
            browA: pts(lm.leftEyebrow), browB: pts(lm.rightEyebrow),
            nose: pts(lm.nose), noseCrest: pts(lm.noseCrest),
            outerLips: pts(lm.outerLips), innerLips: pts(lm.innerLips),
            contour: pts(lm.faceContour), confidence: Double(lm.confidence)
        )

        carryFaceBox(landmarks: lm, box: obs.boundingBox, pose: faceBox)
        return FaceGeometry.sample(from: raw, time: time, brightness: brightness)
    }

    private func detect(_ pixelBuffer: CVPixelBuffer) -> VNFaceObservation? {
        detections += 1
        let request = rectangles
        try? sequence.perform([request], on: pixelBuffer, orientation: .up)
        // The biggest face is the person sitting at the Mac.
        return request.results?.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
    }

    /// Shifts the detected face box along with the landmarks so the next
    /// frame can skip detection.
    private func carryFaceBox(landmarks lm: VNFaceLandmarks2D, box b: CGRect, pose: VNFaceObservation) {
        guard let all = lm.allPoints else {
            trackedFace = nil
            return
        }
        // Landmark points are normalised to the face box; convert to image space.
        let pts = all.normalizedPoints
        guard !pts.isEmpty else { return }
        var cx: CGFloat = 0, cy: CGFloat = 0
        for p in pts {
            cx += b.minX + p.x * b.width
            cy += b.minY + p.y * b.height
        }
        let c = CGPoint(x: cx / CGFloat(pts.count), y: cy / CGFloat(pts.count))
        if detectCentroid == nil { detectCentroid = c }
        guard let c0 = detectCentroid else { return }
        // Re-detect only if the face centre walks off the frame. A box that
        // merely pokes past an edge (a big face, or a forehead cut off by the
        // top of the frame) is normal; dropping it forced a full detection on
        // every frame.
        guard (0...1).contains(c.x), (0...1).contains(c.y) else {
            trackedFace = nil
            return
        }
        let moved = detectBox.offsetBy(dx: c.x - c0.x, dy: c.y - c0.y)
        trackedFace = VNFaceObservation(requestRevision: VNDetectFaceRectanglesRequestRevision3, boundingBox: moved,
                                        roll: pose.roll, yaw: pose.yaw, pitch: pose.pitch)
    }

    private func refine(_ visionPupil: Vec2?, eye: [Vec2], luma: LumaPlane) -> Vec2? {
        guard let iris = luma.withPointer({ PupilLocator.locate(luma: $0, width: luma.width, height: luma.height,
                                                                bytesPerRow: luma.bytesPerRow, eye: eye) })
        else { return visionPupil }
        guard let v = visionPupil else { return iris }
        return Vec2.lerp(v, iris, irisWeight)
    }
}

/// Read access to the luma (Y) plane of a locked camera frame.
struct LumaPlane {
    let base: UnsafeMutableRawPointer
    let width: Int
    let height: Int
    let bytesPerRow: Int
    /// Video range luma runs 16...235 instead of 0...255.
    let videoRange: Bool

    /// Supports the bi-planar 4:2:0 formats the camera is configured for.
    init?(_ pb: CVPixelBuffer) {
        let format = CVPixelBufferGetPixelFormatType(pb)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              let b = CVPixelBufferGetBaseAddressOfPlane(pb, 0)
        else { return nil }
        base = b
        width = CVPixelBufferGetWidthOfPlane(pb, 0)
        height = CVPixelBufferGetHeightOfPlane(pb, 0)
        bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        videoRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    func withPointer<T>(_ body: (UnsafePointer<UInt8>) -> T) -> T {
        body(UnsafePointer(base.assumingMemoryBound(to: UInt8.self)))
    }

    /// Mean brightness 0...1 inside a rectangle (pixels, y down), sampled sparsely.
    func meanBrightness(in rect: CGRect) -> Double {
        let x0 = max(0, Int(rect.minX)), x1 = min(width - 1, Int(rect.maxX))
        let y0 = max(0, Int(rect.minY)), y1 = min(height - 1, Int(rect.maxY))
        guard x1 > x0, y1 > y0 else { return 0.5 }
        let p = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, n = 0
        for y in stride(from: y0, through: y1, by: 6) {
            let row = p + y * bytesPerRow
            for x in stride(from: x0, through: x1, by: 6) {
                sum += Int(row[x])
                n += 1
            }
        }
        guard n > 0 else { return 0.5 }
        let mean = Double(sum) / Double(n)
        return videoRange ? ((mean - 16) / 219).clamped(0, 1) : mean / 255
    }
}
