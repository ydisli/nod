import AppKit

// Developer entry points, handy for bug reports and for CI.
let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--diagnose-image"), i + 1 < arguments.count {
    exit(Diagnostics.analyzeImage(at: arguments[i + 1]))
}

if let i = arguments.firstIndex(of: "--render-icon"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { Rendering.renderIcon(to: arguments[i + 1]) })
}

if let i = arguments.firstIndex(of: "--render-screens"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated {
        NSApplication.shared.setActivationPolicy(.prohibited)
        return Rendering.renderScreens(to: arguments[i + 1])
    })
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
