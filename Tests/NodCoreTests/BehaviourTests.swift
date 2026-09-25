import Foundation
import Testing
@testable import NodCore

private let neutral = FaceMetrics(mouthOpen: 0.05, smile: 1.0, browRaise: 0.15, leftEyeOpen: 0.3, rightEyeOpen: 0.3)

private func bindings(_ edit: (inout [FaceGesture: GestureBinding]) -> Void = { _ in }) -> [FaceGesture: GestureBinding] {
    var b = NodSettings().gestures
    edit(&b)
    return b
}

@Suite("Gestures")
struct GestureTests {
    @Test func learnsBaselineThenDetectsMouth() {
        var d = GestureDetector()
        var t = 0.0
        let b = bindings()
        for _ in 0..<20 {
            #expect(d.update(neutral, time: t, bindings: b).isEmpty)
            t += 1.0 / 30
        }
        #expect(d.baseline != nil)

        var open = neutral
        open.mouthOpen = 0.35
        var began = false
        for _ in 0..<10 {
            if d.update(open, time: t, bindings: b).contains(.began(.mouthOpen)) { began = true }
            t += 1.0 / 30
        }
        #expect(began)
        #expect(d.isActive(.mouthOpen))

        var ended = false
        for _ in 0..<5 {
            for e in d.update(neutral, time: t, bindings: b) {
                if case .ended(.mouthOpen, _) = e { ended = true }
            }
            t += 1.0 / 30
        }
        #expect(ended)
    }

    @Test func naturalBlinkIsNotALongBlink() {
        var d = GestureDetector(baseline: GestureBaseline(neutral: neutral))
        let b = bindings()
        var closed = neutral
        closed.leftEyeOpen = 0.02
        closed.rightEyeOpen = 0.02
        var t = 0.0
        var events: [GestureEvent] = []
        // 200 ms blink: well under the 0.8 s hold time.
        for i in 0..<30 {
            events += d.update(i >= 5 && i < 11 ? closed : neutral, time: t, bindings: b)
            t += 1.0 / 30
        }
        #expect(!events.contains(.began(.longBlink)))

        // A deliberate one-second close does count.
        for _ in 0..<32 {
            events += d.update(closed, time: t, bindings: b)
            t += 1.0 / 30
        }
        #expect(events.contains(.began(.longBlink)))
    }

    @Test func winkNeedsTheOtherEyeOpen() {
        let b = bindings { $0[.leftWink]?.enabled = true; $0[.rightWink]?.enabled = true }
        var d = GestureDetector(baseline: GestureBaseline(neutral: neutral))
        var wink = neutral
        wink.leftEyeOpen = 0.02
        var t = 0.0
        var events: [GestureEvent] = []
        for _ in 0..<20 {
            events += d.update(wink, time: t, bindings: b)
            t += 1.0 / 30
        }
        #expect(events.contains(.began(.leftWink)))
        #expect(!events.contains(.began(.rightWink)))
        #expect(!events.contains(.began(.longBlink)))
    }

    @Test func disabledGesturesNeverFire() {
        let b = bindings { $0[.mouthOpen]?.enabled = false }
        var d = GestureDetector(baseline: GestureBaseline(neutral: neutral))
        var open = neutral
        open.mouthOpen = 0.5
        var t = 0.0
        var events: [GestureEvent] = []
        for _ in 0..<20 {
            events += d.update(open, time: t, bindings: b)
            t += 1.0 / 30
        }
        #expect(events.isEmpty)
    }

    @Test func sensitivityMovesTheThreshold() {
        let easy = bindings { $0[.mouthOpen]?.sensitivity = 1.0 }
        let hard = bindings { $0[.mouthOpen]?.sensitivity = 0.0 }
        let d = GestureDetector(baseline: GestureBaseline(neutral: neutral))
        var slight = neutral
        slight.mouthOpen = 0.12
        #expect((d.computeActivations(slight, bindings: easy)[.mouthOpen] ?? 0) >= 1)
        #expect((d.computeActivations(slight, bindings: hard)[.mouthOpen] ?? 0) < 1)
    }

    @Test func calibratedPeakScalesThreshold() {
        // Someone who can only open their mouth a little.
        let small = GestureBaseline(neutral: neutral, peaks: [.mouthOpen: 0.13])
        let d = GestureDetector(baseline: small)
        var m = neutral
        m.mouthOpen = 0.10
        #expect((d.computeActivations(m, bindings: bindings())[.mouthOpen] ?? 0) >= 1)
    }
}

@Suite("Dwell")
struct DwellTests {
    @Test func firesOnceWhenStill() {
        var d = DwellDetector(dwellTime: 1.0, radius: 20)
        var t = 0.0
        var fires = 0
        for i in 0..<120 {
            let jitter = Vec2(Double(i % 3), Double(i % 2))
            if d.update(position: Vec2(100, 100) + jitter, time: t).fired { fires += 1 }
            t += 1.0 / 60
        }
        #expect(fires == 1)
    }

    @Test func movingNeverFiresAndRearms() {
        var d = DwellDetector(dwellTime: 0.5, radius: 20)
        var t = 0.0
        var fires = 0
        for i in 0..<120 {
            if d.update(position: Vec2(Double(i) * 5, 0), time: t).fired { fires += 1 }
            t += 1.0 / 60
        }
        #expect(fires == 0)
        for _ in 0..<60 {
            if d.update(position: Vec2(0, 300), time: t).fired { fires += 1 }
            t += 1.0 / 60
        }
        #expect(fires == 1)
        // Leave and come back: armed again.
        _ = d.update(position: Vec2(500, 500), time: t)
        for _ in 0..<60 {
            t += 1.0 / 60
            if d.update(position: Vec2(500, 500), time: t).fired { fires += 1 }
        }
        #expect(fires == 2)
    }
}

@Suite("Pupil and geometry")
struct GeometryTests {
    @Test func pupilLocatorFindsDarkDisc() throws {
        let w = 80, h = 40
        var img = [UInt8](repeating: 200, count: w * h)
        let cx = 47.0, cy = 21.0
        for y in 0..<h {
            for x in 0..<w where pow(Double(x) + 0.5 - cx, 2) + pow(Double(y) + 0.5 - cy, 2) < 36 {
                img[y * w + x] = 30
            }
        }
        let eye = [Vec2(10, 20), Vec2(30, 8), Vec2(55, 8), Vec2(72, 20), Vec2(55, 32), Vec2(30, 32)]
        let p = try #require(img.withUnsafeBufferPointer {
            PupilLocator.locate(luma: $0.baseAddress!, width: w, height: h, bytesPerRow: w, eye: eye, darkFraction: 0.12)
        })
        #expect(abs(p.x - cx) < 1.5)
        #expect(abs(p.y - cy) < 1.5)
    }

    /// Landmarks roughly shaped like the Vision output for a frontal face,
    /// in unmirrored pixel coordinates (y down).
    static func raw(mouthGap: Double = 6, noseShift: Double = 0) -> RawLandmarks {
        func eye(_ cx: Double) -> [Vec2] {
            [Vec2(cx - 15, 200), Vec2(cx - 6, 196), Vec2(cx + 6, 196), Vec2(cx + 15, 200), Vec2(cx + 6, 204), Vec2(cx - 6, 204)]
        }
        let nose = [Vec2(320 + noseShift, 240), Vec2(312 + noseShift, 236), Vec2(328 + noseShift, 236)]
        let inner = [Vec2(305, 270), Vec2(320, 270 - mouthGap / 2), Vec2(335, 270), Vec2(335, 271), Vec2(320, 270 + mouthGap / 2), Vec2(305, 271)]
        let outer = [Vec2(295, 270), Vec2(320, 262), Vec2(345, 270), Vec2(320, 280)]
        return RawLandmarks(
            imageSize: Vec2(640, 480),
            eyeA: eye(290), eyeB: eye(350), pupilA: Vec2(290, 200), pupilB: Vec2(350, 200),
            browA: [Vec2(280, 188), Vec2(300, 186)], browB: [Vec2(340, 186), Vec2(360, 188)],
            nose: nose, noseCrest: [Vec2(320 + noseShift, 215)],
            outerLips: outer, innerLips: inner,
            contour: [Vec2(270, 230), Vec2(320, 300), Vec2(370, 230)], confidence: 0.9
        )
    }

    @Test func geometryIsMirroredAndScaleInvariant() throws {
        let a = try #require(FaceGeometry.sample(from: Self.raw(), time: 0, brightness: 0.5))
        #expect(abs(a.faceScale - 60.0 / 640) < 1e-9)
        // Nose moving to the camera's left = the user's right = positive x.
        let b = try #require(FaceGeometry.sample(from: Self.raw(noseShift: -10), time: 0, brightness: 0.5))
        #expect(b.nose.x > a.nose.x)
        #expect(b.headAngle.x > a.headAngle.x)

        let open = try #require(FaceGeometry.sample(from: Self.raw(mouthGap: 30), time: 0, brightness: 0.5))
        #expect(open.metrics.mouthOpen > a.metrics.mouthOpen + 0.3)
        #expect(a.metrics.leftEyeOpen > 0.2)
    }
}

@Suite("Engine")
struct EngineTests {
    static func sample(nose: Vec2, time: Double, metrics: FaceMetrics = neutral) -> FaceSample {
        FaceSample(time: time, imageSize: Vec2(640, 480), nose: nose, faceScale: 0.1, faceCenter: Vec2(0.5, 0.5),
                   gaze: .zero, headAngle: .zero, metrics: metrics, confidence: 1, brightness: 0.5, mesh: FaceMesh())
    }

    /// Runs frames at 30 fps and ticks at 60 fps, returning all commands.
    static func run(_ engine: PointerEngine, from t0: Double, seconds: Double, cursor: inout Vec2,
                    nose: (Double) -> Vec2, metrics: (Double) -> FaceMetrics = { _ in neutral }) -> [PointerCommand] {
        var out: [PointerCommand] = []
        var t = t0
        var frame = 0
        while t < t0 + seconds {
            if frame % 2 == 0 {
                out += engine.ingest(sample(nose: nose(t), time: t, metrics: metrics(t)), time: t)
            }
            for c in engine.tick(time: t, cursor: cursor) {
                if case let .move(p, _) = c { cursor = p }
                out.append(c)
            }
            t += 1.0 / 60
            frame += 1
        }
        return out
    }

    static func makeEngine(_ edit: (inout NodSettings) -> Void = { _ in }) -> PointerEngine {
        var s = NodSettings()
        s.smoothing = 0
        edit(&s)
        let env = EngineEnvironment(displays: [Rect2(x: 0, y: 0, width: 1600, height: 1000)],
                                    mappingDisplay: Rect2(x: 0, y: 0, width: 1600, height: 1000))
        let e = PointerEngine(settings: s, environment: env)
        e.setGestureBaseline(GestureBaseline(neutral: neutral))
        return e
    }

    @Test func relativeHeadTurnMovesPointerRight() {
        let e = Self.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = Self.run(e, from: 0, seconds: 0.5, cursor: &cursor, nose: { _ in Vec2(0.5, 0.45) })
        let start = cursor
        // Turn right by 0.02 image widths over half a second.
        _ = Self.run(e, from: 0.5, seconds: 0.5, cursor: &cursor, nose: { t in Vec2(0.5 + 0.04 * (t - 0.5), 0.45) })
        _ = Self.run(e, from: 1.0, seconds: 0.3, cursor: &cursor, nose: { _ in Vec2(0.52, 0.45) })
        #expect(cursor.x > start.x + 50)
        #expect(abs(cursor.y - start.y) < 5)
    }

    @Test func verticalGainIsCappedAgainstShallowCalibration() {
        let e = Self.makeEngine()
        // A real calibration: lots of turning, very little tilting.
        let profile = CalibrationProfile(
            input: .nose, createdAt: Date(), displaySize: Vec2(1600, 1000), displayID: nil,
            mapping: PointerCalibration(basis: .affine, featureMean: [0, 0], featureScale: [1, 1], coefficientsX: [0, 0, 0],
                                        coefficientsY: [0, 0, 0], meanError: 0, sampleCount: 0),
            neutralNose: Vec2(0.5, 0.45), neutralFaceScale: 0.1, travel: Vec2(0.48, 0.12))
        e.setProfile(profile, for: .nose)
        let t = e.effectiveTravel
        let gainX = 1600 / t.x, gainY = 1000 / t.y
        #expect(gainY <= gainX * 1.3)

        // Equal head movement sideways and up/down: comparable pointer travel.
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = Self.run(e, from: 0, seconds: 0.3, cursor: &cursor, nose: { _ in Vec2(0.5, 0.45) })
        let a = cursor
        _ = Self.run(e, from: 0.3, seconds: 0.5, cursor: &cursor, nose: { t in Vec2(0.5 + 0.02 * (t - 0.3), 0.45) })
        _ = Self.run(e, from: 0.8, seconds: 0.3, cursor: &cursor, nose: { _ in Vec2(0.51, 0.45) })
        let dx = cursor.x - a.x
        let b = cursor
        _ = Self.run(e, from: 1.1, seconds: 0.5, cursor: &cursor, nose: { t in Vec2(0.51, 0.45 + 0.02 * (t - 1.1)) })
        _ = Self.run(e, from: 1.6, seconds: 0.3, cursor: &cursor, nose: { _ in Vec2(0.51, 0.46) })
        let dy = cursor.y - b.y
        #expect(dx > 10 && dy > 10)
        #expect(dy < dx * 1.5)
    }

    @Test func mouthHoldClicksWithoutMovingAndDragsWhenHeld() {
        let e = Self.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = Self.run(e, from: 0, seconds: 0.5, cursor: &cursor, nose: { _ in Vec2(0.5, 0.45) })

        var open = neutral
        open.mouthOpen = 0.4
        // Short open with a small head wobble: a click in place.
        let cmds = Self.run(e, from: 0.5, seconds: 0.25, cursor: &cursor,
                            nose: { t in Vec2(0.5 + 0.003 * sin(t * 40), 0.45) }, metrics: { _ in open })
        let after = Self.run(e, from: 0.75, seconds: 0.4, cursor: &cursor, nose: { _ in Vec2(0.5, 0.45) })
        let all = cmds + after
        let presses = all.filter { if case .press(.left, _) = $0 { return true }; return false }
        let releases = all.filter { if case .release(.left, _) = $0 { return true }; return false }
        #expect(presses.count == 1)
        #expect(releases.count == 1)
        if case let .press(_, p) = presses[0], case let .release(_, r) = releases[0] {
            #expect(p.distance(to: r) < 1)
        }

        // Long open while turning: a drag that ends where the head went.
        _ = Self.run(e, from: 1.2, seconds: 0.3, cursor: &cursor, nose: { _ in Vec2(0.5, 0.45) })
        let dragStart = cursor
        let drag = Self.run(e, from: 1.5, seconds: 1.2, cursor: &cursor,
                            nose: { t in Vec2(0.5 + max(0, t - 2.0) * 0.05, 0.45) }, metrics: { _ in open })
        let end = Self.run(e, from: 2.7, seconds: 0.3, cursor: &cursor, nose: { _ in Vec2(0.535, 0.45) })
        let moves = drag.filter { if case .move(_, true) = $0 { return true }; return false }
        #expect(!moves.isEmpty)
        let rel = end.compactMap { c -> Vec2? in if case let .release(.left, p) = c { return p }; return nil }
        #expect(rel.count == 1)
        #expect((rel.first?.x ?? 0) > dragStart.x + 30)
    }

    @Test func dwellClicksAndPaletteChoiceIsOneShot() {
        let e = Self.makeEngine { $0.dwell.enabled = true; $0.dwell.time = 0.6 }
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = Self.run(e, from: 0, seconds: 0.3, cursor: &cursor, nose: { _ in Vec2(0.5, 0.45) })
        // Picking from the palette disarms dwell until the pointer moves on,
        // so the palette button itself is not pressed twice.
        e.setDwellOverride(.rightClick)
        let idle = Self.run(e, from: 0.3, seconds: 1.0, cursor: &cursor, nose: { _ in Vec2(0.5, 0.45) })
        #expect(!idle.contains { if case .click = $0 { return true }; return false })
        _ = Self.run(e, from: 1.3, seconds: 0.3, cursor: &cursor, nose: { t in Vec2(0.5 - (t - 1.3) * 0.1, 0.45) })
        let first = Self.run(e, from: 1.6, seconds: 1.0, cursor: &cursor, nose: { _ in Vec2(0.47, 0.45) })
        #expect(first.contains { if case .click(.right, 1, _) = $0 { return true }; return false })
        #expect(e.status.dwellAction == .leftClick)
        // Move away and rest again: back to a plain left click.
        _ = Self.run(e, from: 2.6, seconds: 0.4, cursor: &cursor, nose: { t in Vec2(0.47 + (t - 2.6) * 0.1, 0.45) })
        let second = Self.run(e, from: 3.0, seconds: 1.0, cursor: &cursor, nose: { _ in Vec2(0.51, 0.45) })
        #expect(second.contains { if case .click(.left, 1, _) = $0 { return true }; return false })
    }

    @Test func noClicksWhileFaceIsAway() {
        let e = Self.makeEngine { $0.dwell.enabled = true; $0.dwell.time = 0.3 }
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        var out: [PointerCommand] = []
        var t = 0.0
        for _ in 0..<120 {
            out += e.ingest(nil, time: t)
            out += e.tick(time: t, cursor: cursor)
            t += 1.0 / 60
        }
        #expect(!out.contains { if case .click = $0 { return true }; return false })
    }

    @Test func physicalMouseTakesOver() {
        let e = Self.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = Self.run(e, from: 0, seconds: 0.3, cursor: &cursor, nose: { _ in Vec2(0.5, 0.45) })
        // The user grabs the trackpad and moves far away.
        let moved = Vec2(100, 100)
        let cmds = e.tick(time: 0.31, cursor: moved)
        #expect(!cmds.contains { if case .move = $0 { return true }; return false })
        // Head keeps turning during the grace period: no fighting.
        var c2 = moved
        let during = Self.run(e, from: 0.32, seconds: 0.3, cursor: &c2, nose: { t in Vec2(0.5 + t * 0.05, 0.45) })
        #expect(!during.contains { if case .move = $0 { return true }; return false })
    }

    @Test func pauseStopsPointerButGesturesStillResume() {
        let e = Self.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = e.perform(.pauseToggle, time: 0)
        #expect(e.status.paused)
        let cmds = Self.run(e, from: 0, seconds: 0.5, cursor: &cursor, nose: { t in Vec2(0.5 + t * 0.1, 0.45) })
        #expect(!cmds.contains { if case .move = $0 { return true }; return false })
        #expect(e.perform(.leftClick, time: 1).isEmpty)
        _ = e.perform(.pauseToggle, time: 1)
        #expect(!e.status.paused)
    }

    @Test func scrollModeScrollsWithHeadTilt() {
        let e = Self.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = Self.run(e, from: 0, seconds: 0.3, cursor: &cursor, nose: { _ in Vec2(0.5, 0.45) })
        _ = e.perform(.scrollToggle, time: 0.3)
        let cmds = Self.run(e, from: 0.3, seconds: 0.6, cursor: &cursor, nose: { _ in Vec2(0.5, 0.47) })
        let scrolled = cmds.compactMap { c -> Double? in if case let .scroll(v) = c { return v.y }; return nil }.reduce(0, +)
        #expect(scrolled > 20)
        #expect(!cmds.contains { if case .move = $0 { return true }; return false })
    }
}
