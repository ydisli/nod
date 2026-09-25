import AppKit
import CoreVideo
import NodCore
import VideoToolbox

/// Command line helpers for development and bug reports:
///
///     Nod --diagnose-image face.jpg   run the tracker on a photo
enum Diagnostics {
    static func analyzeImage(at path: String) -> Int32 {
        guard let image = NSImage(contentsOfFile: path),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Could not read image at \(path)")
            return 1
        }
        // Scale to webcam size so timings and pixel maths match real use.
        let targetWidth = 640
        let targetHeight = Int(Double(cg.height) * Double(targetWidth) / Double(cg.width))
        guard let buffer = makeCameraBuffer(from: cg, width: targetWidth, height: targetHeight) else {
            print("Could not convert image to a camera frame")
            return 1
        }
        let tracker = FaceTracker()
        var times: [Double] = []
        var sample: FaceSample?
        for i in 0..<30 {
            let t0 = ProcessInfo.processInfo.systemUptime
            sample = tracker.process(buffer, time: Double(i) / 30, detectEvery: 4)
            times.append((ProcessInfo.processInfo.systemUptime - t0) * 1000)
        }
        guard let s = sample else {
            print("No face found.")
            return 2
        }
        let sorted = times.dropFirst().sorted()
        print("frame \(targetWidth)x\(targetHeight)")
        print(String(format: "tracker ms: first %.1f, median %.2f, max %.2f", times[0], sorted[sorted.count / 2], sorted.last ?? 0))
        print("confidence  \(String(format: "%.2f", s.confidence))  brightness \(String(format: "%.2f", s.brightness))")
        print("nose        \(s.nose)   faceScale \(String(format: "%.4f", s.faceScale))")
        print("faceCenter  \(s.faceCenter)")
        print("headAngle   \(s.headAngle)")
        print("gaze        \(s.gaze)")
        let m = s.metrics
        print(String(format: "metrics     mouth %.3f  smile %.3f  brow %.3f  eyes L %.3f R %.3f",
                     m.mouthOpen, m.smile, m.browRaise, m.leftEyeOpen, m.rightEyeOpen))
        print("pupils      \(s.mesh.pupils)")
        print("eyes        L \(Vec2.centroid(s.mesh.leftEye))  R \(Vec2.centroid(s.mesh.rightEye))")
        if CommandLine.arguments.contains("--dump-mesh") { dumpMesh(s) }
        return 0
    }

    /// Prints the mesh as Swift source, re-framed to a unit square around the
    /// face. Used to produce `DemoFace.swift`.
    static func dumpMesh(_ s: FaceSample) {
        let m = s.mesh
        let aspect = s.imageSize.y / s.imageSize.x
        let all = m.contour + m.leftEye + m.rightEye + m.leftBrow + m.rightBrow + m.nose + m.noseCrest + m.outerLips + m.innerLips
        let pts = all.map { Vec2($0.x, $0.y * aspect) }
        let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
        let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
        let size = max(maxX - minX, maxY - minY)
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        func f(_ list: [Vec2]) -> String {
            list.map { p in
                let x = (p.x - cx) / size + 0.5
                let y = (p.y * aspect - cy) / size + 0.5
                return String(format: "V(%.4f, %.4f)", x, y)
            }.joined(separator: ", ")
        }
        print("contour: [\(f(m.contour))]")
        print("leftEye: [\(f(m.leftEye))]")
        print("rightEye: [\(f(m.rightEye))]")
        print("leftBrow: [\(f(m.leftBrow))]")
        print("rightBrow: [\(f(m.rightBrow))]")
        print("nose: [\(f(m.nose))]")
        print("noseCrest: [\(f(m.noseCrest))]")
        print("outerLips: [\(f(m.outerLips))]")
        print("innerLips: [\(f(m.innerLips))]")
        print("pupils: [\(f(m.pupils))]")
        print("noseTip: \(f([m.noseTip]))")
    }

    /// A bi-planar 4:2:0 buffer, the same format the camera delivers.
    static func makeCameraBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var bgra: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs, &bgra)
        guard let bgra else { return nil }
        CVPixelBufferLockBaseAddress(bgra, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(bgra), width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(bgra), space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        ctx?.interpolationQuality = .high
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(bgra, [])

        var yuv: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attrs, &yuv)
        guard let yuv else { return nil }
        var session: VTPixelTransferSession?
        VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session)
        guard let session, VTPixelTransferSessionTransferImage(session, from: bgra, to: yuv) == noErr else { return nil }
        return yuv
    }
}
