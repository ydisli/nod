import Foundation
import Testing
@testable import NodCore

@Suite("Filters and maths")
struct CoreMathTests {
    @Test func oneEuroConvergesAndSmooths() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.0)
        var t = 0.0
        var out = 0.0
        for _ in 0..<300 {
            out = f.filter(10, at: t)
            t += 1.0 / 30
        }
        #expect(abs(out - 10) < 1e-6)

        // Alternating noise must come out much quieter than it went in.
        var g = OneEuroFilter(minCutoff: 1.0, beta: 0.0)
        var maxDev = 0.0
        t = 0
        for i in 0..<300 {
            let v = (i % 2 == 0) ? 1.0 : -1.0
            let y = g.filter(v, at: t)
            if i > 30 { maxDev = max(maxDev, abs(y)) }
            t += 1.0 / 30
        }
        #expect(maxDev < 0.5)
    }

    @Test func oneEuroFollowsFastMotionWithBeta() {
        // With beta the filter must lag a fast ramp far less than without.
        func lag(beta: Double) -> Double {
            var f = OneEuroFilter(minCutoff: 0.5, beta: beta)
            var t = 0.0, y = 0.0, v = 0.0
            for _ in 0..<60 {
                v += 1.0 / 30 * 5 // 5 units per second
                y = f.filter(v, at: t)
                t += 1.0 / 30
            }
            return v - y
        }
        #expect(lag(beta: 2.0) < lag(beta: 0.0) * 0.5)
    }

    @Test func displayClampAvoidsHoles() {
        // A big display with a smaller one to its right, top aligned.
        let env = EngineEnvironment(
            displays: [Rect2(x: 0, y: 0, width: 1000, height: 800), Rect2(x: 1000, y: 0, width: 500, height: 300)],
            mappingDisplay: Rect2(x: 0, y: 0, width: 1000, height: 800)
        )
        // Below the small display there is no screen.
        let p = env.clamp(Vec2(1200, 700))
        #expect(env.displays.contains { $0.contains(p) })
        #expect(env.clamp(Vec2(10, 10)) == Vec2(10, 10))
    }

    @Test func joystickDeadzoneAndCurve() {
        #expect(PointerEngine.joystick(offset: Vec2(0.05, 0), deadzone: 0.1) == .zero)
        let full = PointerEngine.joystick(offset: Vec2(1, 0), deadzone: 0.1)
        #expect(abs(full.x - 1) < 1e-9)
        let half = PointerEngine.joystick(offset: Vec2(0.55, 0), deadzone: 0.1)
        #expect(half.x > 0 && half.x < 0.5)
    }

    @Test func settingsDecodeLenientlyAndRoundTrip() throws {
        var s = NodSettings()
        s.speed = 1.7
        s.headGestures[.nod] = GestureBinding(enabled: true, action: .doubleClick, holdTime: 0)
        s.toggleHotKey = .disabled
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(NodSettings.self, from: data)
        #expect(back == s)
        #expect(!back.toggleHotKey.isEnabled)

        // Older or partial files keep their values and default the rest.
        // Keys from the camera era ("input", "gestures") are simply ignored.
        let partial = #"{"speed": 2.5, "motionRevision": 2, "input": "eyes", "gestures": {}, "unknownFutureKey": 1, "dwell": {"enabled": true}}"#
        let p = try JSONDecoder().decode(NodSettings.self, from: Data(partial.utf8))
        #expect(p.speed == 2.5)
        #expect(p.dwell.enabled)
        #expect(p.dwell.time == DwellSettings().time)
        #expect(p.headGestures.count == HeadGesture.allCases.count)
    }

    @Test func speedFromOlderMotionModelIsMigrated() throws {
        // Written before revision 2: speed 0.49 felt right back then.
        let old = #"{"speed": 0.49, "input": "nose"}"#
        let s = try JSONDecoder().decode(NodSettings.self, from: Data(old.utf8))
        #expect(abs(s.speed - 0.49 / 0.45) < 1e-9)
        #expect(s.motionRevision == NodSettings.currentMotionRevision)
        // Re-reading migrated settings must not migrate twice.
        let again = try JSONDecoder().decode(NodSettings.self, from: JSONEncoder().encode(s))
        #expect(again.speed == s.speed)
    }
}
