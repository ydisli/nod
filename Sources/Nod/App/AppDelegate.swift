import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var windows: WindowManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        windows = WindowManager(model: model)
        model.windows = windows
        windows.setUp()
        DevHooks.installIfRequested(model: model, windows: windows)

        if !model.settings.hasCompletedOnboarding {
            windows.showOnboarding()
        } else if model.wasEnabledLastRun {
            model.setEnabled(true)
        }
    }

    /// Reopening the app from Finder or Spotlight shows the settings, since
    /// a menu bar app has no other window to bring back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windows.showSettings(pane: nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave a mouse button held down behind us.
        model.pipeline.stopAndWait()
    }
}
