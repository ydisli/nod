import AppKit
import NodCore
import SwiftUI

// MARK: - Halo

@MainActor @Observable
final class HaloState {
    var hud = HUDState()
    var toast: Toast?

    struct Toast: Equatable {
        let id: Int
        let text: String
        let symbol: String
    }
}

/// A small click-through window that follows the pointer and shows dwell
/// progress, gesture charge, drag/scroll/pause state and action hints.
@MainActor
final class HaloController {
    private let state = HaloState()
    private var panel: NSPanel?
    private var follow: Timer?
    private var toastCounter = 0
    private var toastClear: DispatchWorkItem?
    var enabled = true {
        didSet { refreshVisibility() }
    }

    private static let size = CGSize(width: 150, height: 150)

    func update(_ hud: HUDState) {
        state.hud = hud
        refreshVisibility()
    }

    func toast(_ text: String, symbol: String) {
        guard enabled else { return }
        toastCounter += 1
        state.toast = HaloState.Toast(id: toastCounter, text: text, symbol: symbol)
        toastClear?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.state.toast = nil
                self?.refreshVisibility()
            }
        }
        toastClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
        refreshVisibility()
    }

    func hide() {
        state.hud = HUDState()
        state.toast = nil
        refreshVisibility()
    }

    private var shouldShow: Bool {
        guard enabled else { return false }
        let h = state.hud
        return state.toast != nil || h.dwellProgress > 0.02 || h.dragging || h.scrolling || h.paused || h.gestureLevel > 0.3
    }

    private func refreshVisibility() {
        if shouldShow {
            let p = ensurePanel()
            position(p)
            if !p.isVisible { p.orderFrontRegardless() }
            startFollowing()
        } else {
            follow?.invalidate()
            follow = nil
            panel?.orderOut(nil)
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = NSHostingView(rootView: HaloView(state: state))
        panel = p
        return p
    }

    private func startFollowing() {
        guard follow == nil else { return }
        follow = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.panel else { return }
                self.position(p)
            }
        }
        RunLoop.main.add(follow!, forMode: .common)
    }

    private func position(_ p: NSPanel) {
        let m = NSEvent.mouseLocation
        let origin = CGPoint(x: (m.x - Self.size.width / 2).rounded(), y: (m.y - Self.size.height / 2).rounded())
        if p.frame.origin != origin { p.setFrameOrigin(origin) }
    }
}

struct HaloView: View {
    let state: HaloState

    var body: some View {
        let h = state.hud
        ZStack {
            // Dwell ring.
            if h.dwellProgress > 0.02 {
                Circle()
                    .stroke(.black.opacity(0.35), lineWidth: 6)
                    .frame(width: 46, height: 46)
                Circle()
                    .trim(from: 0, to: h.dwellProgress)
                    .stroke(AngularGradient(colors: [Theme.teal, Theme.blue, Theme.violet, Theme.gold], center: .center),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 46, height: 46)
                    .shadow(color: Theme.teal.opacity(0.7), radius: 4)
                Image(systemName: h.dwellAction.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Theme.ink.opacity(0.85)))
                    .offset(x: 23, y: -23)
            }
            // Gesture charge: a thin inner ring that fills as an expression forms.
            if h.gestureLevel > 0.3 {
                Circle()
                    .trim(from: 0, to: min(h.gestureLevel, 1))
                    .stroke(h.gestureLevel >= 1 ? Theme.gold : Theme.teal.opacity(0.8),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 30, height: 30)
            }
            VStack(spacing: 4) {
                Spacer().frame(height: 104)
                if let t = state.toast {
                    Label(t.text, systemImage: t.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.ink.opacity(0.88)))
                        .overlay(Capsule().strokeBorder(Theme.teal.opacity(0.5), lineWidth: 0.75))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .id(t.id)
                } else if let badge = stateBadge(h) {
                    Label(badge.0, systemImage: badge.1)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3.5)
                        .background(Capsule().fill(badge.2.opacity(0.9)))
                }
                Spacer()
            }
        }
        .frame(width: 150, height: 150)
        .animation(.easeOut(duration: 0.15), value: state.toast)
    }

    private func stateBadge(_ h: HUDState) -> (String, String, Color)? {
        if h.paused { return ("Paused", "pause.fill", Theme.gold.opacity(0.85)) }
        if h.dragging { return ("Dragging", "hand.draw.fill", Theme.violet) }
        if h.scrolling { return ("Scrolling", "arrow.up.and.down", Theme.blue) }
        return nil
    }
}

// MARK: - Palette

/// Hosting view that reacts to the first click even though the panel never
/// becomes active, so a dwell click on a button works immediately.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A floating panel of big targets for choosing what the next dwell does.
@MainActor
final class PaletteController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let p = ensurePanel()
        p.orderFrontRegardless()
        model.isPaletteVisible = true
        model.paletteMoved(to: p.frame)
    }

    func hide() {
        panel?.orderOut(nil)
        model.isPaletteVisible = false
        model.paletteMoved(to: nil)
    }

    func toggle() { isVisible ? hide() : show() }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let size = CGSize(width: 92, height: 452)
        let p = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = FirstClickHostingView(rootView: PaletteView(onClose: { [weak self] in self?.hide() }).environment(model))
        p.contentView = host
        p.setContentSize(host.fittingSize)
        p.delegate = self
        // Park it at the right edge of the main display, vertically centred.
        let screen = Displays.screen(for: model.settings.displayID ?? CGMainDisplayID()) ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            let fit = p.frame.size
            p.setFrameOrigin(CGPoint(x: vf.maxX - fit.width - 16, y: vf.midY - fit.height / 2))
        }
        panel = p
        return p
    }

    func windowDidMove(_ notification: Notification) {
        if let p = panel, p.isVisible { model.paletteMoved(to: p.frame) }
    }
}

struct PaletteView: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void

    private let actions: [PointerAction] = [.leftClick, .rightClick, .doubleClick, .dragToggle, .scrollToggle]

    var body: some View {
        let status = model.live.status
        VStack(spacing: 7) {
            Capsule().fill(.white.opacity(0.25)).frame(width: 28, height: 4).padding(.top, 2)
            ForEach(actions) { action in
                PaletteButton(action: action, active: status.dwellAction == action || (action == .dragToggle && status.dragging)
                              || (action == .scrollToggle && status.scrolling)) {
                    model.chooseDwellAction(action)
                }
            }
            Divider().overlay(.white.opacity(0.15)).padding(.horizontal, 6)
            PaletteButton(action: .pauseToggle, active: status.paused, titleOverride: status.paused ? "Resume" : "Pause",
                          symbolOverride: status.paused ? "play.fill" : "pause.fill") {
                model.perform(.pauseToggle)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 22, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide palette")
        }
        .padding(8)
        .frame(width: 92)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.inkLine, lineWidth: 1))
        )
        .environment(\.colorScheme, .dark)
    }
}

struct PaletteButton: View {
    let action: PointerAction
    let active: Bool
    var titleOverride: String?
    var symbolOverride: String?
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 4) {
                Image(systemName: symbolOverride ?? action.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 24)
                Text(titleOverride ?? action.shortTitle)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 72, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? AnyShapeStyle(Theme.anodized) : AnyShapeStyle(Color.white.opacity(0.07)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(active ? 0.35 : 0.08), lineWidth: 1)
            )
            .shadow(color: active ? Theme.blue.opacity(0.5) : .clear, radius: 8)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(titleOverride ?? action.title)
    }
}
