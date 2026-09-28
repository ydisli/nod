import NodCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, pointer, clicking, dwell, shortcuts, permissions, help, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .pointer: "Pointer"
        case .clicking: "Clicking"
        case .dwell: "Dwell Clicking"
        case .shortcuts: "Shortcuts"
        case .permissions: "Permissions"
        case .help: "Help"
        case .about: "About Nod"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .pointer: "cursorarrow.motionlines"
        case .clicking: "cursorarrow.click"
        case .dwell: "timer"
        case .shortcuts: "keyboard.fill"
        case .permissions: "lock.shield.fill"
        case .help: "questionmark.circle.fill"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: Color(hex: 0x7D879B)
        case .pointer: Theme.blue
        case .clicking: Color(hex: 0x1FA89A)
        case .dwell: Theme.accent
        case .shortcuts: Color(hex: 0x6B7488)
        case .permissions: Color(hex: 0x2FAE62)
        case .help: Color(hex: 0xE0A43A)
        case .about: Theme.accent
        }
    }

    var subtitle: String {
        switch self {
        case .general: "How Nod starts and gives feedback."
        case .pointer: "How turning your head moves the pointer."
        case .clicking: "Click with a key or your head. Meters show live strength, the line marks the trigger point."
        case .dwell: "Rest the pointer on something to click it. No gestures needed."
        case .shortcuts: "Keyboard shortcuts that work in every app."
        case .permissions: "What Nod needs from macOS, and why."
        case .help: "How to use Nod, and what to do when something is off."
        case .about: "Open source, on-device, free."
        }
    }
}

@MainActor @Observable
final class SettingsRouter {
    var pane: SettingsPane? = .general
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Bindable var router: SettingsRouter

    var body: some View {
        let pane = router.pane ?? .general
        HStack(spacing: 0) {
            sidebar(selected: pane)
                .frame(width: 214)
            Divider()
            VStack(spacing: 0) {
                PaneHeader(symbol: pane.symbol, color: pane.color, title: pane.title, subtitle: pane.subtitle)
                content(pane)
                    // A fresh view per pane, so every pane opens scrolled to the top.
                    .id(pane)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    /// A plain, predictable sidebar. NavigationSplitView in an AppKit-hosted
    /// window clipped its columns under the title bar.
    private func sidebar(selected: SettingsPane) -> some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        router.pane = pane
                    } label: {
                        HStack(spacing: 10) {
                            IconBadge(symbol: pane.symbol, color: pane.color, size: 22)
                            Text(pane.title)
                                .font(.system(size: 13, weight: pane == selected ? .semibold : .regular))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(pane == selected ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.clear))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(pane == selected ? .isSelected : [])
                    if pane == .dwell || pane == .permissions {
                        Divider().padding(.vertical, 5).padding(.horizontal, 8)
                    }
                }
            }
            .padding(10)
        }
        .background(.background.secondary)
    }

    @ViewBuilder
    private func content(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane()
        case .pointer: PointerPane()
        case .clicking: GesturesPane()
        case .dwell: DwellPane()
        case .shortcuts: ShortcutsPane()
        case .permissions: PermissionsPane()
        case .help: HelpPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - General

struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle(isOn: Binding(get: { launchAtLogin }, set: { launchAtLogin = model.setLaunchAtLogin($0) })) {
                    Text("Open Nod when I log in")
                    Text("Nod also resumes tracking if it was on when you quit.")
                }
                .disabled(!LaunchAtLogin.isAvailable)
            }
            Section("Feedback") {
                Toggle(isOn: $model.settings.playSounds) {
                    Text("Play sounds")
                    Text("A soft tick on clicks, other tones for drag, scroll and pause.")
                }
                Toggle(isOn: $model.settings.showHalo) {
                    Text("Show the halo around the pointer")
                    Text("Dwell progress, drag and scroll state, and a hint for each action.")
                }
            }
            Section("Sharing the pointer") {
                Toggle(isOn: $model.settings.yieldToMouse) {
                    Text("Step aside when the mouse or trackpad moves")
                    Text("A helper can take over at any time, Nod picks up again a moment later.")
                }
            }
            Section {
                HStack {
                    Text("Welcome tour")
                    Spacer()
                    Button("Show Again") { model.windows?.showOnboarding() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pointer

struct PointerPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let s = model.settings
        Form {
            Section {
                ForEach(MotionStyle.allCases) { style in
                    ChoiceRow(title: style.title, detail: style.summary, symbol: style.symbol,
                              selected: s.motion == style, badge: nil) {
                        model.settings.motion = style
                    }
                }
            } header: {
                Text("Motion")
            } footer: {
                Text("Look at the middle of the screen and press \(s.recenterHotKey.display) to recentre. In Direct, that also makes the way you are facing the new centre.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Feel") {
                SliderRow(title: "Speed", value: $model.settings.speed, range: 0.25...3, format: { String(format: "%.1f×", $0) })
                if s.motion == .relative {
                    SliderRow(title: "Acceleration", value: $model.settings.acceleration, range: 0...1,
                              format: { $0 < 0.05 ? "Off" : "\(Int($0 * 100))%" },
                              help: "Slow movements stay precise, quick ones travel far.")
                }
                SliderRow(title: "Smoothing", value: $model.settings.smoothing, range: 0...1, format: { "\(Int($0 * 100))%" },
                          help: "More smoothing removes tremor but adds a little lag.")
                if s.motion == .joystick {
                    SliderRow(title: "Top speed", value: $model.settings.joystickSpeed, range: 0.2...2,
                              format: { String(format: "%.1f", $0) }, help: "Screen widths per second at full turn.")
                    SliderRow(title: "Dead zone", value: $model.settings.deadzone, range: 0...0.4, format: { "\(Int($0 * 100))%" },
                              help: "How far you can turn before the pointer starts gliding.")
                }
            }
            Section("Direction") {
                Toggle("Reverse left and right", isOn: $model.settings.invertX)
                Toggle("Reverse up and down", isOn: $model.settings.invertY)
            }
            Section {
                Picker("Main display", selection: Binding(get: { model.settings.displayID ?? 0 },
                                                          set: { model.settings.displayID = $0 == 0 ? nil : $0 })) {
                    Text("Display with the menu bar").tag(UInt32(0))
                    ForEach(Displays.all()) { d in
                        Text(d.name).tag(d.id)
                    }
                }
            } footer: {
                Text("Recentring and direct aiming use this display. The pointer can still travel to every display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Clicking

struct GesturesPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            if !model.isEnabled || !model.live.connected {
                Section {
                    if !model.isEnabled {
                        Label("Reading your AirPods so the meters are live. Pointer control stays off.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.live.connected {
                        Label("Put in your AirPods to see the meters move.", systemImage: "airpodspro")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ClickKeysSection()
            ForEach(HeadGesture.allCases) { g in
                Section {
                    GestureRow(title: g.title, instruction: g.instruction, symbol: g.symbol,
                               binding: Binding(get: { model.settings.binding(for: g) },
                                                set: { model.settings.headGestures[g] = $0 }),
                               gesture: g,
                               showsHoldTime: g != .nod)
                }
            }
            Section {
                Toggle(isOn: $model.settings.holdSteadyWhileGesturing) {
                    Text("Hold the pointer steady while a tilt forms")
                    Text("Leaning sideways turns your head a little too. This keeps clicks exactly where you aimed.")
                }
            } footer: {
                Text("A nod clicks where the pointer was before your head went down. It is off at first, because glancing at the keyboard can look like a nod.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .liveFrames(model, id: "settings.gestures", preview: true)
    }
}

struct ClickKeysSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle(isOn: $model.settings.clickKeys.enabled) {
                Text("Click with keys")
                Text("A key press does not move your head, so the click lands exactly where you aimed.")
            }
            if model.settings.clickKeys.enabled {
                row("Click", detail: "Tap twice to double click. A recorded key, not ⌘ ⌥ ⌃ ⇧, can also be held to drag.", \.leftButton)
                row("Right click", detail: nil, \.rightClick)
                row("Double click", detail: "Optional, tapping the click key twice also works.", \.doubleClick)
                row("Drag", detail: "Tap to pick up, move your head, tap again to drop.", \.drag)
            }
        } header: {
            Text("Keys")
        } footer: {
            Text("Click a key box, then press any key or shortcut, or tap a modifier key such as right ⌘ or left ⌥. A modifier key counts only when pressed on its own, so shortcuts keep working. Delete clears. Nod never records what you type.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, detail: String?, _ path: WritableKeyPath<ClickKeys, ClickTrigger>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if case let .shortcut(spec) = model.settings.clickKeys[keyPath: path], spec.carbonModifiers == 0, spec.display.count == 1 {
                    Text("Typing \(spec.display) anywhere clicks while Nod is on.").font(.caption).foregroundStyle(Theme.gold)
                } else if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            ClickTriggerRecorder(trigger: Binding(get: { model.settings.clickKeys[keyPath: path] }, set: { set($0, at: path) }),
                                 isTaken: { taken($0) })
            Menu {
                ForEach(ClickKey.allCases.filter { $0 != .off }) { k in
                    Button(k.title) { set(.modifier(k), at: path) }
                }
                Divider()
                Button("Off") { set(.off, at: path) }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Pick a modifier key")
        }
    }

    /// One key, one job: whoever had this key gives it up.
    private func set(_ new: ClickTrigger, at path: WritableKeyPath<ClickKeys, ClickTrigger>) {
        var keys = model.settings.clickKeys
        for other in [\ClickKeys.leftButton, \.rightClick, \.doubleClick, \.drag] where other != path && keys[keyPath: other] == new && !new.isOff {
            keys[keyPath: other] = .off
        }
        keys[keyPath: path] = new
        model.settings.clickKeys = keys
    }

    /// Nod's own shortcuts cannot also click.
    private func taken(_ spec: HotKeySpec) -> Bool {
        let s = model.settings
        return [s.toggleHotKey, s.recenterHotKey].contains { $0.keyCode == spec.keyCode && $0.carbonModifiers == spec.carbonModifiers }
    }
}

/// Records a click trigger: any key or shortcut, or a lone tap of a
/// modifier key.
struct ClickTriggerRecorder: View {
    @Binding var trigger: ClickTrigger
    var isTaken: (HotKeySpec) -> Bool = { _ in false }
    @State private var recording = false
    @State private var monitor: Any?
    @State private var pendingModifier: ClickKey?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press a key…" : trigger.title)
                .font(.system(size: 12, weight: .medium))
                .frame(minWidth: 130)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 7).fill(recording ? Theme.teal.opacity(0.25) : .primary.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(recording ? Theme.teal : .primary.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        pendingModifier = nil
        HotKeyCenter.shared.isSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // A modifier key pressed and let go on its own.
                if let key = ClickKey(keyCode: event.keyCode) {
                    let down = UInt64(event.modifierFlags.rawValue) & key.deviceMask != 0
                    if down {
                        pendingModifier = key
                    } else if pendingModifier == key {
                        trigger = .modifier(key)
                        stop()
                    }
                }
                return nil
            }
            pendingModifier = nil
            switch Int(event.keyCode) {
            case 53: // Escape
                stop()
            case 51, 117: // Delete, Forward delete
                trigger = .off
                stop()
            default:
                if let spec = HotKeyCenter.spec(from: event, allowPlain: true), !isTaken(spec) {
                    trigger = .shortcut(spec)
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        pendingModifier = nil
        HotKeyCenter.shared.isSuspended = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}

struct GestureRow: View {
    let title: String
    let instruction: String
    let symbol: String
    @Binding var binding: GestureBinding
    let gesture: HeadGesture
    var showsHoldTime = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadge(symbol: symbol, color: binding.enabled ? Theme.teal : .gray.opacity(0.7), size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(instruction).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if binding.enabled {
                    LiveMeter(gesture: gesture).frame(width: 110)
                }
                Toggle("", isOn: $binding.enabled).labelsHidden().toggleStyle(.switch)
            }
            if binding.enabled {
                Picker("Does", selection: $binding.action) {
                    ForEach(PointerAction.gestureChoices) { a in
                        Label(a.title, systemImage: a.symbol).tag(a)
                    }
                }
                SliderRow(title: "Sensitivity", value: $binding.sensitivity, range: 0...1,
                          format: { $0 < 0.34 ? "Big move" : ($0 < 0.67 ? "Medium" : "Subtle") })
                if showsHoldTime {
                    SliderRow(title: "Hold for", value: $binding.holdTime, range: 0...1.5, format: { String(format: "%.2f s", $0) })
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A gesture meter that reads the live value itself, so only it redraws.
struct LiveMeter: View {
    @Environment(AppModel.self) private var model
    let gesture: HeadGesture

    var body: some View {
        ActivationMeter(value: model.live.motion.activations[gesture] ?? 0, height: 6, animated: false)
    }
}

// MARK: - Dwell

struct DwellPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle(isOn: $model.settings.dwell.enabled) {
                    Text("Click by resting the pointer")
                    Text("Hold still for a moment and the ring around the pointer fills, then clicks.")
                }
            }
            Section("Timing") {
                SliderRow(title: "Dwell time", value: $model.settings.dwell.time, range: 0.4...3, format: { String(format: "%.1f s", $0) })
                SliderRow(title: "Stillness radius", value: $model.settings.dwell.radius, range: 10...80, format: { "\(Int($0)) pt" },
                          help: "How much the pointer may wander and still count as resting.")
            }
            .disabled(!model.settings.dwell.enabled)
            Section("Action") {
                Picker("Resting does", selection: $model.settings.dwell.defaultAction) {
                    ForEach(PointerAction.dwellChoices) { a in
                        Label(a.title, systemImage: a.symbol).tag(a)
                    }
                }
                Toggle(isOn: $model.settings.dwell.stickyChoice) {
                    Text("Keep a palette choice until I pick another")
                    Text("Off: a right click or double click chosen in the palette is used once, then it goes back.")
                }
                Toggle(isOn: $model.settings.dwell.showPalette) {
                    Text("Show the action palette while tracking")
                    Text("Big buttons you can dwell on to choose right click, double click, drag, scroll or pause.")
                }
                HStack {
                    Spacer()
                    Button(model.isPaletteVisible ? "Hide Palette" : "Show Palette") { model.windows?.togglePalette() }
                }
            }
            .disabled(!model.settings.dwell.enabled)
        }
        .formStyle(.grouped)
    }
}

struct Tip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.teal).frame(width: 18)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ShortcutRow(title: "Start or stop Nod", detail: "Your safety switch.", spec: $model.settings.toggleHotKey)
                ShortcutRow(title: "Recentre the pointer", detail: "Or make your current pose the centre.", spec: $model.settings.recenterHotKey)
            } footer: {
                Text("Click a shortcut, then press the new keys. Include ⌘, ⌥ or ⌃. Press Delete to clear, Escape to cancel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRow: View {
    let title: String
    let detail: String
    @Binding var spec: HotKeySpec

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            KeyRecorder(spec: $spec)
        }
    }
}

struct KeyRecorder: View {
    @Binding var spec: HotKeySpec
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Type shortcut…" : (spec.isEnabled ? spec.display : "None"))
                .font(.system(size: 12, weight: .medium).monospaced())
                .frame(minWidth: 96)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 7).fill(recording ? AnyShapeStyle(Theme.teal.opacity(0.25)) : AnyShapeStyle(.primary.opacity(0.07))))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(recording ? Theme.teal : .primary.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.isSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 53: // Escape
                stop()
            case 51, 117: // Delete, Forward delete
                spec = .disabled
                stop()
            default:
                if let s = HotKeyCenter.spec(from: event) {
                    spec = s
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        HotKeyCenter.shared.isSuspended = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}

// MARK: - Permissions

struct PermissionsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                PermissionRow(symbol: "accessibility", title: "Accessibility",
                              detail: "To move the pointer and click for you. Nod reads nothing on screen.",
                              status: model.accessibilityPermission) {
                    Permissions.promptAccessibility()
                    Permissions.openAccessibilitySettings()
                }
                PermissionRow(symbol: "airpodspro", title: "Headphone motion",
                              detail: "To read how your head turns. macOS asks the first time Nod starts.",
                              status: model.motionPermission,
                              showsButton: model.motionPermission != .notDetermined) {
                    Permissions.openPrivacySettings()
                }
            }
            Section("Privacy") {
                Tip(symbol: "wifi.slash", text: "Nod makes no network connections. There is no account, analytics or telemetry.")
                Tip(symbol: "internaldrive", text: "Only your settings are saved. Nod uses no camera and records nothing.")
                Tip(symbol: "keyboard", text: "With click keys on, Nod notices when another key is pressed, only to tell a click from a shortcut. It never reads or keeps what you type.")
                Tip(symbol: "chevron.left.forwardslash.chevron.right", text: "The source code is public, so anyone can check these promises.")
            }
        }
        .formStyle(.grouped)
        .onAppear { model.watchPermissions(true, client: "settings.permissions") }
        .onDisappear { model.watchPermissions(false, client: "settings.permissions") }
    }
}

struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let status: PermissionStatus
    /// Some permissions can only be asked for by macOS itself.
    var showsButton = true
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: status.isGranted ? Theme.green : Theme.gold, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if status.isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
                    .font(.system(size: 12, weight: .medium))
            } else if showsButton {
                Button(status == .notDetermined ? "Allow" : "Open Settings", action: action)
            } else {
                Text("Not asked yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Help

struct HelpPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.settings
        let keys = s.clickKeys
        Form {
            Section("Getting started") {
                Tip(symbol: "airpodspro", text: "Put in AirPods that support head tracking for spatial audio, such as AirPods Pro or AirPods Max.")
                Tip(symbol: "power", text: "Press \(shortcut(s.toggleHotKey)) to switch Nod on or off. It is your safety switch.")
                Tip(symbol: "scope", text: "Look at the middle of the screen and press \(shortcut(s.recenterHotKey)) to recentre. Do it again whenever the pointer and where you look drift apart.")
                Tip(symbol: "arrow.left.and.right", text: "Turn your head to move the pointer. Small turns make fine moves.")
            }
            Section("Clicking") {
                if keys.enabled, !keys.leftButton.isOff {
                    Tip(symbol: "keyboard", text: "Tap \(keys.leftButton.shortTitle) to click, tap it twice to double click.")
                }
                if keys.enabled, !keys.rightClick.isOff {
                    Tip(symbol: "keyboard", text: "Tap \(keys.rightClick.shortTitle) to right click.")
                }
                if keys.enabled, !keys.drag.isOff {
                    Tip(symbol: "hand.draw", text: "Tap \(keys.drag.shortTitle) to pick something up, move your head, tap it again to drop.")
                }
                Tip(symbol: "keyboard.badge.ellipsis", text: "A key like ⌘ or ⇧ clicks only when tapped on its own. Used in a shortcut such as ⌘A, it does nothing in Nod.")
                Tip(symbol: HeadGesture.tiltLeft.symbol, text: "Lean your head left to click, keep leaning to drag. Lean right to right click. Leaning never moves the pointer.")
                Tip(symbol: "timer", text: "Dwell Clicking clicks when you rest on a spot. Its palette picks what the next rest does: right click, double click, drag or scroll.")
                Tip(symbol: "slider.horizontal.3", text: "Change any of these in Clicking, including your own shortcuts.")
            }
            Section("When something is off") {
                Tip(symbol: "hand.raised", text: "The pointer does not move: open the menu bar panel. Nod needs Accessibility, and your AirPods in your ears.")
                Tip(symbol: "scope", text: "The pointer drifts from where you look: recentre. Direct motion in Pointer keeps the two lined up best.")
                Tip(symbol: "arrow.left.arrow.right", text: "It moves the wrong way: Pointer, Reverse left and right, or up and down.")
                Tip(symbol: "exclamationmark.triangle", text: "It clicks by accident: in Clicking, switch off leaning or nodding, or set their Sensitivity to Big move.")
                Tip(symbol: "computermouse", text: "You want your mouse back: just move it. Nod steps aside, and \(shortcut(s.toggleHotKey)) stops it completely.")
            }
            Section {
                HStack(spacing: 16) {
                    Link(destination: URL(string: "https://github.com/ydisli/nod#readme")!) {
                        Label("Read the guide", systemImage: "book")
                    }
                    Link(destination: URL(string: "https://github.com/ydisli/nod/issues")!) {
                        Label("Report a problem", systemImage: "exclamationmark.bubble")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func shortcut(_ spec: HotKeySpec) -> String {
        spec.isEnabled ? spec.display : "your shortcut (none set, see Shortcuts)"
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                NodMark(size: 112)
                    .padding(.top, 10)
                Text("Nod").font(.system(size: 30, weight: .bold))
                Text("Your head is the mouse.").font(.system(size: 15)).foregroundStyle(.secondary)
                Text("Version \(Bundle.main.shortVersion)")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
                Text("Hands-free pointer control for macOS. Nod follows your head through the motion sensors in your AirPods, and clicks with a key, a lean or a rest. Everything happens on your Mac.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, 4)
                VStack(spacing: 3) {
                    Text("Made by Yusuf Disli").font(.system(size: 13, weight: .semibold))
                    Link("yusufdisli.com", destination: URL(string: "https://yusufdisli.com")!)
                        .font(.system(size: 13))
                }
                .padding(.top, 6)
                HStack(spacing: 10) {
                    Link(destination: URL(string: "https://github.com/ydisli/nod")!) {
                        Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://github.com/ydisli/nod/issues")!) {
                        Label("Report a problem", systemImage: "exclamationmark.bubble")
                    }
                }
                .padding(.top, 6)
                Text("MIT License. Smoothing by the 1€ filter of Casiez, Roussel and Vogel.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String).flatMap { $0.hasPrefix("__") ? nil : $0 } ?? "dev"
    }
}

// MARK: - Shared rows

/// A radio style row with icon, title, explanation and a check.
struct ChoiceRow: View {
    let title: String
    let detail: String
    let symbol: String
    let selected: Bool
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(symbol: symbol, color: selected ? Theme.violet : .gray.opacity(0.55), size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        if let badge {
                            Text(badge.uppercased())
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Capsule().fill(Theme.gold.opacity(0.2)))
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.teal) : AnyShapeStyle(.tertiary))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.2f", $0) }
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Slider(value: $value, in: range).frame(width: 220)
                Text(format(value))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    /// Registers for live tracking frames while visible. With `preview`, the
    /// AirPods are read even when tracking is off, without moving the pointer.
    func liveFrames(_ model: AppModel, id: String, preview: Bool = false) -> some View {
        onAppear {
            model.retainFrames(id)
            if preview { model.retainPreview(id) }
        }
        .onDisappear {
            model.releaseFrames(id)
            if preview { model.releasePreview(id) }
        }
    }
}
