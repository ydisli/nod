import Foundation
import Testing
@testable import NodCore

@Suite("Click keys")
struct KeyClickTests {
    let keys = ClickKeys()

    @Test func tapClicksOnRelease() {
        var d = KeyClickDetector()
        #expect(d.handle(.down(.modifier(.rightCommand)), time: 0, keys: keys).isEmpty)
        #expect(d.tick(time: 0.1, keys: keys).isEmpty)
        #expect(d.handle(.up(.modifier(.rightCommand)), time: 0.12, keys: keys) == [.tap])
    }

    @Test func holdPressesThenReleases() {
        var d = KeyClickDetector()
        _ = d.handle(.down(.modifier(.rightCommand)), time: 0, keys: keys)
        #expect(d.tick(time: 0.2, keys: keys).isEmpty)
        #expect(d.tick(time: 0.31, keys: keys) == [.press])
        #expect(d.tick(time: 0.5, keys: keys).isEmpty)
        #expect(d.handle(.up(.modifier(.rightCommand)), time: 1.4, keys: keys) == [.release])
    }

    @Test func shortcutsNeverClick() {
        var d = KeyClickDetector()
        _ = d.handle(.down(.modifier(.rightCommand)), time: 0, keys: keys)
        _ = d.handle(.otherKey, time: 0.05, keys: keys)
        #expect(d.tick(time: 0.5, keys: keys).isEmpty)
        #expect(d.handle(.up(.modifier(.rightCommand)), time: 0.6, keys: keys).isEmpty)

        // Two click keys together are a chord too.
        _ = d.handle(.down(.modifier(.rightCommand)), time: 1, keys: keys)
        _ = d.handle(.down(.modifier(.rightOption)), time: 1.02, keys: keys)
        #expect(d.handle(.up(.modifier(.rightOption)), time: 1.05, keys: keys).isEmpty)
        #expect(d.handle(.up(.modifier(.rightCommand)), time: 1.1, keys: keys).isEmpty)
    }

    @Test func rightClickAndDoubleClickKeys() {
        var k = keys
        k.doubleClick = .modifier(.rightShift)
        var d = KeyClickDetector()
        _ = d.handle(.down(.modifier(.rightOption)), time: 0, keys: k)
        #expect(d.tick(time: 0.5, keys: k).isEmpty)
        #expect(d.handle(.up(.modifier(.rightOption)), time: 0.6, keys: k) == [.rightClick])
        _ = d.handle(.down(.modifier(.rightShift)), time: 1, keys: k)
        #expect(d.handle(.up(.modifier(.rightShift)), time: 1.1, keys: k) == [.doubleClick])
        // Unbound keys and disabled keys do nothing.
        _ = d.handle(.down(.modifier(.rightControl)), time: 2, keys: k)
        #expect(d.handle(.up(.modifier(.rightControl)), time: 2.1, keys: k).isEmpty)
        k.enabled = false
        _ = d.handle(.down(.modifier(.rightCommand)), time: 3, keys: k)
        #expect(d.handle(.up(.modifier(.rightCommand)), time: 3.1, keys: k).isEmpty)
    }

    @Test func longRestingPressIsNotAClick() {
        var d = KeyClickDetector()
        _ = d.handle(.down(.modifier(.rightOption)), time: 0, keys: keys)
        #expect(d.handle(.up(.modifier(.rightOption)), time: 1.5, keys: keys).isEmpty)
    }

    @Test func engineTapsCountUpAndHoldDrags() {
        let e = HeadTrackingTests.makeEngine()
        var cursor = Vec2(800, 500)
        e.reset(cursor: cursor)
        _ = HeadTrackingTests.run(e, from: 0, seconds: 0.5, cursor: &cursor, pose: { _ in .zero })

        var out = e.key(.down(.modifier(.rightCommand)), time: 0.5)
        out += e.key(.up(.modifier(.rightCommand)), time: 0.58)
        #expect(out.contains(.press(.left, at: cursor)))
        #expect(out.contains(.release(.left, at: cursor)))
        #expect(!out.contains { if case .click = $0 { true } else { false } })

        // Held: the button goes down after the delay and stays down while
        // the head turns, then comes up with the key.
        _ = e.key(.down(.modifier(.rightCommand)), time: 1.0)
        out = HeadTrackingTests.run(e, from: 1.0, seconds: 0.4, cursor: &cursor, pose: { _ in .zero })
        #expect(out.contains { if case .press(.left, _) = $0 { true } else { false } })
        #expect(e.status.dragging)
        out = HeadTrackingTests.run(e, from: 1.4, seconds: 0.5, cursor: &cursor, pose: { t in HeadPose(yaw: 0.2 * (t - 1.4), pitch: 0, roll: 0) })
        #expect(out.contains { if case .move(_, true) = $0 { true } else { false } })
        out = e.key(.up(.modifier(.rightCommand)), time: 1.9)
        #expect(out.contains { if case .release(.left, _) = $0 { true } else { false } })
        #expect(!e.status.dragging)
    }

    @Test func settingsWithoutClickKeysGetDefaults() throws {
        let s = try JSONDecoder().decode(NodSettings.self, from: Data(#"{"speed": 1, "motionRevision": 2}"#.utf8))
        #expect(s.clickKeys == ClickKeys())
        #expect(s.clickKeys.leftButton == .modifier(.rightCommand))
    }

    @Test func keysSavedBeforeShortcutsStillRead() throws {
        let old = #"{"enabled": true, "leftButton": "rightOption", "rightClick": "off", "doubleClick": "rightShift"}"#
        let k = try JSONDecoder().decode(ClickKeys.self, from: Data(old.utf8))
        #expect(k.leftButton == .modifier(.rightOption))
        #expect(k.rightClick.isOff)
        #expect(k.doubleClick == .modifier(.rightShift))
    }

    @Test func recordedShortcutsRoundTrip() throws {
        var k = ClickKeys()
        k.rightClick = .shortcut(HotKeySpec(keyCode: 0x60, carbonModifiers: 0, display: "F5"))
        let back = try JSONDecoder().decode(ClickKeys.self, from: JSONEncoder().encode(k))
        #expect(back == k)
        #expect(back.shortcuts.map(\.display) == ["F5"])
    }

    @Test func recordedShortcutClicksEvenWhenModifiersMove() {
        // ⌃⌥Space: letting go of ⌥ before Space must still click, and key
        // repeat while held must not break it.
        var k = keys
        let spec = HotKeySpec(keyCode: 0x31, carbonModifiers: HotKeySpec.controlKey | HotKeySpec.optionKey, display: "⌃⌥Space")
        k.leftButton = .shortcut(spec)
        var d = KeyClickDetector()
        _ = d.handle(.down(.shortcut(spec)), time: 0, keys: k)
        _ = d.handle(.down(.shortcut(spec)), time: 0.05, keys: k)
        _ = d.handle(.otherKey, time: 0.08, keys: k)
        #expect(d.handle(.up(.shortcut(spec)), time: 0.12, keys: k) == [.tap])
        // Held long enough, it drags.
        _ = d.handle(.down(.shortcut(spec)), time: 1, keys: k)
        #expect(d.tick(time: 1.35, keys: k) == [.press])
        #expect(d.handle(.up(.shortcut(spec)), time: 2, keys: k) == [.release])
    }
}
