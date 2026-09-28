import Foundation
import Testing
@testable import NodCore

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

@Suite("Engine")
struct EngineTests {
    typealias H = HeadTrackingTests

    static func turn(_ yaw: Double, _ pitch: Double = 0) -> HeadPose { HeadPose(yaw: yaw, pitch: pitch, roll: 0) }

    @Test func dwellClicksAndPaletteChoiceIsOneShot() {
        let e = H.makeEngine { $0.dwell.enabled = true; $0.dwell.time = 0.6 }
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = H.run(e, from: 0, seconds: 0.3, cursor: &cursor, pose: { _ in .zero })
        // Picking from the palette disarms dwell until the pointer moves on,
        // so the palette button itself is not pressed twice.
        e.setDwellOverride(.rightClick)
        let idle = H.run(e, from: 0.3, seconds: 1.0, cursor: &cursor, pose: { _ in .zero })
        #expect(!idle.contains { if case .click = $0 { return true }; return false })
        _ = H.run(e, from: 1.3, seconds: 0.3, cursor: &cursor, pose: { t in Self.turn(-(t - 1.3) * 0.3) })
        let first = H.run(e, from: 1.6, seconds: 1.0, cursor: &cursor, pose: { _ in Self.turn(-0.09) })
        #expect(first.contains { if case .click(.right, 1, _) = $0 { return true }; return false })
        #expect(e.status.dwellAction == .leftClick)
        // Move away and rest again: back to a plain left click.
        _ = H.run(e, from: 2.6, seconds: 0.4, cursor: &cursor, pose: { t in Self.turn(-0.09 + (t - 2.6) * 0.3) })
        let second = H.run(e, from: 3.0, seconds: 1.0, cursor: &cursor, pose: { _ in Self.turn(0.03) })
        #expect(second.contains { if case .click(.left, 1, _) = $0 { return true }; return false })
    }

    @Test func noClicksWhileHeadphonesAreQuiet() {
        let e = H.makeEngine { $0.dwell.enabled = true; $0.dwell.time = 0.3 }
        let cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        var out: [PointerCommand] = []
        var t = 0.0
        for _ in 0..<120 {
            out += e.ingest(head: nil, time: t)
            out += e.tick(time: t, cursor: cursor)
            t += 1.0 / 60
        }
        #expect(!out.contains { if case .click = $0 { return true }; return false })
        #expect(e.isIdle)
    }

    @Test func physicalMouseTakesOver() {
        let e = H.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = H.run(e, from: 0, seconds: 0.3, cursor: &cursor, pose: { _ in .zero })
        // The user grabs the trackpad and moves far away.
        let moved = Vec2(100, 100)
        let cmds = e.tick(time: 0.31, cursor: moved)
        #expect(!cmds.contains { if case .move = $0 { return true }; return false })
        // Head keeps turning during the grace period: no fighting.
        var c2 = moved
        let during = H.run(e, from: 0.32, seconds: 0.3, cursor: &c2, pose: { t in Self.turn(t * 0.2) })
        #expect(!during.contains { if case .move = $0 { return true }; return false })
    }

    @Test func pauseStopsPointer() {
        let e = H.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = e.perform(.pauseToggle, time: 0)
        #expect(e.status.paused)
        let cmds = H.run(e, from: 0, seconds: 0.5, cursor: &cursor, pose: { t in Self.turn(t * 0.3) })
        #expect(!cmds.contains { if case .move = $0 { return true }; return false })
        #expect(e.perform(.leftClick, time: 1).isEmpty)
        _ = e.perform(.pauseToggle, time: 1)
        #expect(!e.status.paused)
    }

    @Test func scrollModeScrollsWithHeadTilt() {
        let e = H.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = H.run(e, from: 0, seconds: 0.3, cursor: &cursor, pose: { _ in .zero })
        _ = e.perform(.scrollToggle, time: 0.3)
        let cmds = H.run(e, from: 0.3, seconds: 0.6, cursor: &cursor, pose: { _ in Self.turn(0, 0.06) })
        let scrolled = cmds.compactMap { c -> Double? in if case let .scroll(v) = c { return v.y }; return nil }.reduce(0, +)
        #expect(scrolled > 20)
        #expect(!cmds.contains { if case .move = $0 { return true }; return false })
    }
}
