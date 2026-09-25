import AppKit
import CoreGraphics
import NodCore

/// Posts real mouse events. Requires the Accessibility permission; without it
/// macOS silently drops the events.
///
/// Thread safe enough for its use: only called from the tracking queue.
final class MouseDriver {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var pressed: Set<MouseButton> = []
    private var lastPress: (time: Double, point: CGPoint, button: MouseButton)?
    private var clickCount = 1
    private var scrollRemainder = CGVector.zero

    /// Where the system cursor is right now, in global display points (y down).
    static func cursorLocation() -> Vec2 {
        let p = CGEvent(source: nil)?.location ?? .zero
        return Vec2(Double(p.x), Double(p.y))
    }

    func execute(_ command: PointerCommand) {
        switch command {
        case let .move(to, dragging):
            move(to: cg(to), dragging: dragging)
        case let .press(button, at):
            press(button, at: cg(at))
        case let .release(button, at):
            release(button, at: cg(at))
        case let .click(button, count, at):
            click(button, count: count, at: cg(at))
        case let .scroll(delta):
            scroll(delta)
        case .feedback:
            break
        }
    }

    /// Lets go of every button, used when tracking stops or the app quits.
    func releaseAll() {
        let at = CGEvent(source: nil)?.location ?? .zero
        for b in pressed { post(upType(b), button: b, at: at, clickState: 1) }
        pressed.removeAll()
    }

    private func cg(_ v: Vec2) -> CGPoint { CGPoint(x: v.x, y: v.y) }

    private func move(to p: CGPoint, dragging: Bool) {
        let type: CGEventType = dragging && pressed.contains(.left) ? .leftMouseDragged : .mouseMoved
        post(type, button: .left, at: p, clickState: 0)
    }

    private func press(_ button: MouseButton, at p: CGPoint) {
        // Consecutive presses in the same spot count up, so two quick mouth
        // clicks are a real double click to the app underneath.
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPress, last.button == button, now - last.time <= NSEvent.doubleClickInterval,
           hypot(last.point.x - p.x, last.point.y - p.y) < 6 {
            clickCount += 1
        } else {
            clickCount = 1
        }
        lastPress = (now, p, button)
        pressed.insert(button)
        post(downType(button), button: button, at: p, clickState: clickCount)
    }

    private func release(_ button: MouseButton, at p: CGPoint) {
        guard pressed.contains(button) else { return }
        pressed.remove(button)
        post(upType(button), button: button, at: p, clickState: clickCount)
    }

    private func click(_ button: MouseButton, count: Int, at p: CGPoint) {
        for i in 1...max(count, 1) {
            post(downType(button), button: button, at: p, clickState: i)
            post(upType(button), button: button, at: p, clickState: i)
        }
        lastPress = (ProcessInfo.processInfo.systemUptime, p, button)
        clickCount = count
    }

    private func scroll(_ delta: Vec2) {
        // Positive y in NodCore moves the view down the page, which is a
        // negative wheel value in Quartz terms.
        scrollRemainder.dx += -delta.x
        scrollRemainder.dy += -delta.y
        let dx = Int32(scrollRemainder.dx.rounded(.towardZero))
        let dy = Int32(scrollRemainder.dy.rounded(.towardZero))
        guard dx != 0 || dy != 0 else { return }
        scrollRemainder.dx -= CGFloat(dx)
        scrollRemainder.dy -= CGFloat(dy)
        let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        e?.post(tap: .cghidEventTap)
    }

    private func post(_ type: CGEventType, button: MouseButton, at p: CGPoint, clickState: Int) {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: cgButton(button)) else { return }
        if clickState > 0 { e.setIntegerValueField(.mouseEventClickState, value: Int64(clickState)) }
        e.post(tap: .cghidEventTap)
    }

    private func cgButton(_ b: MouseButton) -> CGMouseButton {
        switch b {
        case .left: .left
        case .right: .right
        case .middle: .center
        }
    }

    private func downType(_ b: MouseButton) -> CGEventType {
        switch b {
        case .left: .leftMouseDown
        case .right: .rightMouseDown
        case .middle: .otherMouseDown
        }
    }

    private func upType(_ b: MouseButton) -> CGEventType {
        switch b {
        case .left: .leftMouseUp
        case .right: .rightMouseUp
        case .middle: .otherMouseUp
        }
    }
}
