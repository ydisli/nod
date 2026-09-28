import Foundation
import Testing
@testable import NodCore

@Suite("AirPods head tracking")
struct HeadTrackingTests {
    static let deg = Double.pi / 180

    static func makeEngine(_ edit: (inout NodSettings) -> Void = { _ in }) -> PointerEngine {
        var s = NodSettings()
        s.smoothing = 0
        edit(&s)
        let env = EngineEnvironment(displays: [Rect2(x: 0, y: 0, width: 1600, height: 1000)],
                                    mappingDisplay: Rect2(x: 0, y: 0, width: 1600, height: 1000))
        return PointerEngine(settings: s, environment: env)
    }

    /// Head poses at 25 Hz (roughly what AirPods send) and ticks at 60 Hz.
    static func run(_ engine: PointerEngine, from t0: Double, seconds: Double, cursor: inout Vec2,
                    pose: (Double) -> HeadPose) -> [PointerCommand] {
        var out: [PointerCommand] = []
        var t = t0
        var nextPose = t0
        while t < t0 + seconds {
            if t >= nextPose {
                out += engine.ingest(head: pose(t), time: t)
                nextPose += 1.0 / 25
            }
            for c in engine.tick(time: t, cursor: cursor) {
                if case let .move(p, _) = c { cursor = p }
                out.append(c)
            }
            t += 1.0 / 60
        }
        return out
    }

    @Test func turningRightAndLookingDownMoveThePointerThatWay() {
        let e = Self.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = Self.run(e, from: 0, seconds: 0.5, cursor: &cursor, pose: { _ in .zero })
        let start = cursor
        // Turn 8 degrees right over half a second, then hold.
        _ = Self.run(e, from: 0.5, seconds: 0.5, cursor: &cursor, pose: { t in HeadPose(yaw: 16 * Self.deg * (t - 0.5), pitch: 0, roll: 0) })
        _ = Self.run(e, from: 1.0, seconds: 0.3, cursor: &cursor, pose: { _ in HeadPose(yaw: 8 * Self.deg, pitch: 0, roll: 0) })
        #expect(cursor.x > start.x + 80)
        #expect(abs(cursor.y - start.y) < 5)

        let mid = cursor
        _ = Self.run(e, from: 1.3, seconds: 0.5, cursor: &cursor, pose: { t in HeadPose(yaw: 8 * Self.deg, pitch: 12 * Self.deg * (t - 1.3), roll: 0) })
        _ = Self.run(e, from: 1.8, seconds: 0.3, cursor: &cursor, pose: { _ in HeadPose(yaw: 8 * Self.deg, pitch: 6 * Self.deg, roll: 0) })
        #expect(cursor.y > mid.y + 50)
        #expect(abs(cursor.x - mid.x) < 5)
    }

    @Test func tiltLeftHoldsTheButtonAndReleasesIt() {
        let e = Self.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        var out = Self.run(e, from: 0, seconds: 0.6, cursor: &cursor, pose: { _ in .zero })
        #expect(!out.contains { if case .press = $0 { true } else { false } })
        // Lean 18 degrees towards the left shoulder for half a second.
        out = Self.run(e, from: 0.6, seconds: 0.5, cursor: &cursor, pose: { _ in HeadPose(yaw: 0, pitch: 0, roll: -18 * Self.deg) })
        #expect(out.contains(.press(.left, at: cursor)))
        #expect(!out.contains { if case .click(.right, _, _) = $0 { true } else { false } })
        out = Self.run(e, from: 1.1, seconds: 0.4, cursor: &cursor, pose: { _ in .zero })
        #expect(out.contains { if case .release(.left, _) = $0 { true } else { false } })
    }

    @Test func tiltRightIsARightClick() {
        let e = Self.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = Self.run(e, from: 0, seconds: 0.6, cursor: &cursor, pose: { _ in .zero })
        let out = Self.run(e, from: 0.6, seconds: 0.5, cursor: &cursor, pose: { _ in HeadPose(yaw: 0, pitch: 0, roll: 18 * Self.deg) })
        #expect(out.contains { if case .click(.right, 1, _) = $0 { true } else { false } })
        #expect(!out.contains { if case .press = $0 { true } else { false } })
    }

    @Test func smallLeanWhileTurningDoesNotClick() {
        let e = Self.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        let out = Self.run(e, from: 0, seconds: 2, cursor: &cursor, pose: { t in
            HeadPose(yaw: 10 * Self.deg * sin(t * 3), pitch: 5 * Self.deg * sin(t * 2), roll: 4 * Self.deg * sin(t * 3))
        })
        #expect(!out.contains { if case .click = $0 { true } else if case .press = $0 { true } else { false } })
    }

    @Test func nodClicksWhereThePointerWasBeforeTheDip() throws {
        let e = Self.makeEngine { $0.headGestures[.nod] = GestureBinding(enabled: true, action: .leftClick, holdTime: 0) }
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = Self.run(e, from: 0, seconds: 0.6, cursor: &cursor, pose: { _ in .zero })
        let before = cursor
        // Down 15 degrees and back within 0.4 s.
        let out = Self.run(e, from: 0.6, seconds: 0.8, cursor: &cursor, pose: { t in
            let u = (t - 0.6) / 0.4
            return HeadPose(yaw: 0, pitch: u < 1 ? 15 * Self.deg * sin(.pi * u) : 0, roll: 0)
        })
        let clicks = out.compactMap { c -> Vec2? in if case let .click(.left, 1, at) = c { at } else { nil } }
        #expect(clicks.count == 1)
        let at = try #require(clicks.first)
        #expect(at.distance(to: before) < 15)
    }

    @Test func glancingDownAndStayingIsNotANod() {
        let e = Self.makeEngine { $0.headGestures[.nod] = GestureBinding(enabled: true, action: .leftClick, holdTime: 0) }
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = Self.run(e, from: 0, seconds: 0.6, cursor: &cursor, pose: { _ in .zero })
        let out = Self.run(e, from: 0.6, seconds: 1.5, cursor: &cursor, pose: { t in
            HeadPose(yaw: 0, pitch: min((t - 0.6) / 0.3, 1) * 20 * Self.deg, roll: 0)
        })
        #expect(!out.contains { if case .click = $0 { true } else { false } })
    }

    @Test func directAimingStartsWithoutAJumpAndRecentres() {
        let e = Self.makeEngine { $0.motion = .direct }
        var cursor = Vec2(300, 200)
        e.reset(cursor: cursor)
        // The headphones start at some arbitrary angle.
        let resting = HeadPose(yaw: 1.2, pitch: -0.3, roll: 0)
        _ = Self.run(e, from: 0, seconds: 0.5, cursor: &cursor, pose: { _ in resting })
        #expect(cursor.distance(to: Vec2(300, 200)) < 3)

        // Turning right by a tenth of the travel moves a tenth of the screen.
        let turned = HeadPose(yaw: 1.2 + PointerEngine.headTravel.x / 10, pitch: -0.3, roll: 0)
        _ = Self.run(e, from: 0.5, seconds: 0.6, cursor: &cursor, pose: { _ in turned })
        #expect(abs(cursor.x - 460) < 5)

        e.recenter()
        _ = Self.run(e, from: 1.1, seconds: 0.4, cursor: &cursor, pose: { _ in turned })
        #expect(cursor.distance(to: Vec2(800, 500)) < 3)
    }

    @Test func pointerStopsWhenTheHeadphonesGoQuiet() {
        let e = Self.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = Self.run(e, from: 0, seconds: 0.5, cursor: &cursor, pose: { _ in .zero })
        #expect(e.status.tracking)
        for i in 0..<30 {
            _ = e.ingest(head: nil, time: 0.5 + Double(i) / 25)
        }
        #expect(!e.status.tracking)
    }

    @Test func settingsWithoutHeadGesturesGetDefaults() throws {
        let old = #"{"speed": 1.2, "motionRevision": 2, "gestures": {"smile": {"enabled": true, "action": "doubleClick", "sensitivity": 0.5, "holdTime": 0.3}}}"#
        let s = try JSONDecoder().decode(NodSettings.self, from: Data(old.utf8))
        #expect(s.headGestures.count == HeadGesture.allCases.count)
        #expect(s.binding(for: .tiltLeft).action == .leftHold)
        #expect(!s.binding(for: .nod).enabled)
        let back = try JSONDecoder().decode(NodSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}
