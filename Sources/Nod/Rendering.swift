import AppKit
import NodCore
import SwiftUI

/// Offscreen rendering for the app icon and for documentation screenshots.
///
///     Nod --render-icon Nod.iconset
///     Nod --render-screens docs/screens
@MainActor
enum Rendering {
    static func renderIcon(to dir: String) -> Int32 {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let entries: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, px) in entries {
            let view = NodMark(size: CGFloat(px), detailed: px >= 64, iconCanvas: true)
            guard writePNG(view, size: CGSize(width: px, height: px), to: url.appendingPathComponent(name + ".png")) else {
                print("Failed to render \(name)")
                return 1
            }
        }
        print("Wrote \(entries.count) icon images to \(dir)")
        return 0
    }

    /// Screens with demo data, for the README and for visual review.
    static func renderScreens(to dir: String) -> Int32 {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let model = AppModel(demo: true)
        func out(_ name: String) -> URL { url.appendingPathComponent(name + ".png") }

        let menu = MenuPanel().environment(model)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        let menuHeight = NSHostingController(rootView: menu).sizeThatFits(in: CGSize(width: 332, height: 4000)).height
        snapshot(menu, size: CGSize(width: 332, height: menuHeight), to: out("menu"))

        // Show that any shortcut can click, next to a modifier key.
        model.settings.clickKeys.rightClick = .shortcut(HotKeySpec(keyCode: 0x31, carbonModifiers: HotKeySpec.controlKey | HotKeySpec.optionKey, display: "⌃⌥Space"))
        for pane in [SettingsPane.pointer, .clicking, .permissions, .help, .about] {
            let router = SettingsRouter()
            router.pane = pane
            snapshot(SettingsView(router: router).environment(model), size: CGSize(width: 820, height: 600),
                     to: out("settings-\(pane.rawValue)"), titled: true)
        }
        for step in 0..<4 {
            snapshot(OnboardingView(startAt: step) {}.environment(model), size: CGSize(width: 780, height: 540), to: out("onboarding-\(step)"))
        }
        snapshot(PaletteView(onClose: {}).environment(model), size: NSHostingView(rootView: PaletteView(onClose: {}).environment(model)).fittingSize, to: out("palette"))

        let halo = HaloState()
        halo.hud = HUDState(dwellProgress: 0.62, dwellAction: .rightClick, gestureLevel: 0.7, tracking: true)
        halo.toast = HaloState.Toast(id: 1, text: "Right", symbol: PointerAction.rightClick.symbol)
        snapshot(HaloView(state: halo).background(Color(hex: 0x3A4152)), size: CGSize(width: 150, height: 150), to: out("halo"))
        print("Wrote screens to \(dir)")
        return 0
    }

    /// Renders a pure SwiftUI view (no AppKit controls) at 1x.
    @discardableResult
    static func writePNG<V: View>(_ view: V, size: CGSize, to url: URL, scale: CGFloat = 1) -> Bool {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        renderer.isOpaque = false
        guard let cg = renderer.cgImage else { return false }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// Renders any view, including AppKit backed controls, by hosting it in
    /// an offscreen window and caching its display.
    @discardableResult
    static func snapshot<V: View>(_ view: V, size: CGSize, to url: URL, appearance: NSAppearance.Name = .darkAqua,
                                  titled: Bool = false) -> Bool {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        // Split views and sidebars only lay out properly in a real titled window.
        let style: NSWindow.StyleMask = titled ? [.titled, .closable] : [.borderless]
        let window = NSWindow(contentRect: host.frame, styleMask: style, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        if titled {
            window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
            window.orderFrontRegardless()
        }
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI settle (fonts, layout passes, first animation frame).
        RunLoop.main.run(until: Date().addingTimeInterval(titled ? 0.9 : 0.35))
        defer { window.orderOut(nil) }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }
}
