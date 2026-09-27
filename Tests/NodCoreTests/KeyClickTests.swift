import Foundation
import Testing
@testable import NodCore

@Suite("Click keys")
struct KeyClickTests {
    let keys = ClickKeys()

    @Test func tapClicksOnRelease() {
        var d = KeyClickDetector()
        #expect(d.handle(.down(.rightCommand), time: 0, keys: keys).isEmpty)
        #expect(d.tick(time: 0.1, keys: keys).isEmpty)
        #expect(d.handle(.up(.rightCommand), time: 0.12, keys: keys) == [.tap])
    }

    @Test func holdPressesThenReleases() {
        var d = KeyClickDetector()
        _ = d.handle(.down(.rightCommand), time: 0, keys: keys)
        #expect(d.tick(time: 0.2, keys: keys).isEmpty)
        #expect(d.tick(time: 0.31, keys: keys) == [.press])
        #expect(d.tick(time: 0.5, keys: keys).isEmpty)
        #expect(d.handle(.up(.rightCommand), time: 1.4, keys: keys) == [.release])
    }

    @Test func shortcutsNeverClick() {
        var d = KeyClickDetector()
        _ = d.handle(.down(.rightCommand), time: 0, keys: keys)
        _ = d.handle(.otherKey, time: 0.05, keys: keys)
        #expect(d.tick(time: 0.5, keys: keys).isEmpty)
        #expect(d.handle(.up(.rightCommand), time: 0.6, keys: keys).isEmpty)

        // Two click keys together are a chord too.
        _ = d.handle(.down(.rightCommand), time: 1, keys: keys)
        _ = d.handle(.down(.rightOption), time: 1.02, keys: keys)
        #expect(d.handle(.up(.rightOption), time: 1.05, keys: keys).isEmpty)
        #expect(d.handle(.up(.rightCommand), time: 1.1, keys: keys).isEmpty)
    }

    @Test func rightClickAndDoubleClickKeys() {
        var k = keys
        k.doubleClick = .rightShift
        var d = KeyClickDetector()
        _ = d.handle(.down(.rightOption), time: 0, keys: k)
        #expect(d.tick(time: 0.5, keys: k).isEmpty)
        #expect(d.handle(.up(.rightOption), time: 0.6, keys: k) == [.rightClick])
        _ = d.handle(.down(.rightShift), time: 1, keys: k)
        #expect(d.handle(.up(.rightShift), time: 1.1, keys: k) == [.doubleClick])
        // Unbound keys and disabled keys do nothing.
        _ = d.handle(.down(.rightControl), time: 2, keys: k)
        #expect(d.handle(.up(.rightControl), time: 2.1, keys: k).isEmpty)
        k.enabled = false
        _ = d.handle(.down(.rightCommand), time: 3, keys: k)
        #expect(d.handle(.up(.rightCommand), time: 3.1, keys: k).isEmpty)
    }

    @Test func longRestingPressIsNotAClick() {
        var d = KeyClickDetector()
        _ = d.handle(.down(.rightOption), time: 0, keys: keys)
        #expect(d.handle(.up(.rightOption), time: 1.5, keys: keys).isEmpty)
    }

    @Test func engineTapsCountUpAndHoldDrags() {
        let e = HeadTrackingTests.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = HeadTrackingTests.run(e, from: 0, seconds: 0.5, cursor: &cursor, pose: { _ in .zero })

        var out = e.key(.down(.rightCommand), time: 0.5)
        out += e.key(.up(.rightCommand), time: 0.58)
        #expect(out.contains(.press(.left, at: cursor)))
        #expect(out.contains(.release(.left, at: cursor)))
        #expect(!out.contains { if case .click = $0 { true } else { false } })

        // Held: the button goes down after the delay and stays down while
        // the head turns, then comes up with the key.
        _ = e.key(.down(.rightCommand), time: 1.0)
        out = HeadTrackingTests.run(e, from: 1.0, seconds: 0.4, cursor: &cursor, pose: { _ in .zero })
        #expect(out.contains { if case .press(.left, _) = $0 { true } else { false } })
        #expect(e.status.dragging)
        out = HeadTrackingTests.run(e, from: 1.4, seconds: 0.5, cursor: &cursor, pose: { t in HeadPose(yaw: 0.2 * (t - 1.4), pitch: 0, roll: 0) })
        #expect(out.contains { if case .move(_, true) = $0 { true } else { false } })
        out = e.key(.up(.rightCommand), time: 1.9)
        #expect(out.contains { if case .release(.left, _) = $0 { true } else { false } })
        #expect(!e.status.dragging)
    }

    @Test func settingsWithoutClickKeysGetDefaults() throws {
        let s = try JSONDecoder().decode(NodSettings.self, from: Data(#"{"speed": 1, "motionRevision": 2}"#.utf8))
        #expect(s.clickKeys == ClickKeys())
        #expect(s.clickKeys.leftButton == .rightCommand)
    }
}
