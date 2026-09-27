@preconcurrency import AVFoundation
import NodCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, pointer, clicking, dwell, calibration, camera, shortcuts, permissions, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .pointer: "Pointer"
        case .clicking: "Gestures"
        case .dwell: "Dwell Clicking"
        case .calibration: "Calibration"
        case .camera: "Camera"
        case .shortcuts: "Shortcuts"
        case .permissions: "Permissions"
        case .about: "About Nod"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .pointer: "cursorarrow.motionlines"
        case .clicking: "face.smiling"
        case .dwell: "timer"
        case .calibration: "scope"
        case .camera: "camera.fill"
        case .shortcuts: "keyboard.fill"
        case .permissions: "lock.shield.fill"
        case .about: "info.circle.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .general: [Color(hex: 0x8E9AAF), Color(hex: 0x5B6475)]
        case .pointer: [Theme.blue, Color(hex: 0x3563D8)]
        case .clicking: [Theme.teal, Color(hex: 0x1C9E91)]
        case .dwell: [Theme.violet, Color(hex: 0x6546D8)]
        case .calibration: [Theme.gold, Color(hex: 0xE09A1F)]
        case .camera: [Color(hex: 0x5D6B82), Color(hex: 0x3A4456)]
        case .shortcuts: [Color(hex: 0x7A8599), Color(hex: 0x4E576A)]
        case .permissions: [Theme.green, Color(hex: 0x23A45A)]
        case .about: [Theme.violet, Theme.teal]
        }
    }

    var subtitle: String {
        switch self {
        case .general: "How Nod starts and gives feedback."
        case .pointer: "What steers the pointer and how it feels."
        case .clicking: "Click, drag and more with your face or head. Meters show live strength, the line marks the trigger point."
        case .dwell: "Rest the pointer on something to click it. No gestures needed."
        case .calibration: "Teach Nod your range of movement and your expressions."
        case .camera: "Which camera Nod watches and how hard it works."
        case .shortcuts: "Keyboard shortcuts that work in every app."
        case .permissions: "What Nod needs from macOS, and why."
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
                PaneHeader(symbol: pane.symbol, colors: pane.colors, title: pane.title, subtitle: pane.subtitle)
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
                            IconBadge(symbol: pane.symbol, colors: pane.colors, size: 22)
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
                    if pane == .dwell || pane == .shortcuts {
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
        case .calibration: CalibrationPane()
        case .camera: CameraPane()
        case .shortcuts: ShortcutsPane()
        case .permissions: PermissionsPane()
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
            Section("Steer with") {
                ForEach(TrackingInput.allCases) { input in
                    ChoiceRow(title: input.title, detail: input.summary, symbol: input.symbol,
                              selected: s.input == input, badge: badge(input)) {
                        model.settings.input = input
                    }
                }
            }
            if s.input == .nose || s.input == .headphones {
                Section("Motion") {
                    ForEach(MotionStyle.allCases) { style in
                        ChoiceRow(title: style.title, detail: summary(style, input: s.input), symbol: motionSymbol(style),
                                  selected: s.motion == style, badge: nil) {
                            model.settings.motion = style
                        }
                    }
                }
            }
            Section("Feel") {
                SliderRow(title: "Speed", value: $model.settings.speed, range: 0.25...3, format: { String(format: "%.1f×", $0) })
                if s.input != .eyes {
                    SliderRow(title: "Acceleration", value: $model.settings.acceleration, range: 0...1,
                              format: { $0 < 0.05 ? "Off" : "\(Int($0 * 100))%" },
                              help: "Slow movements stay precise, quick ones travel far.")
                    SliderRow(title: "Smoothing", value: $model.settings.smoothing, range: 0...1, format: { "\(Int($0 * 100))%" },
                              help: "More smoothing removes tremor but adds a little lag.")
                }
                if s.input == .eyes || s.input == .hybrid {
                    SliderRow(title: "Eye steadiness", value: $model.settings.eyeSmoothing, range: 0...1, format: { "\(Int($0 * 100))%" },
                              help: "Webcam gaze is jittery; steadier means calmer but slower.")
                }
                if s.input == .nose || s.input == .headphones, s.motion == .joystick {
                    SliderRow(title: "Top speed", value: $model.settings.joystickSpeed, range: 0.2...2,
                              format: { String(format: "%.1f", $0) }, help: "Screen widths per second at full tilt.")
                    SliderRow(title: "Dead zone", value: $model.settings.deadzone, range: 0...0.4, format: { "\(Int($0 * 100))%" },
                              help: "How far you can move before the pointer starts gliding.")
                }
                if s.input == .hybrid {
                    SliderRow(title: "Jump distance", value: $model.settings.hybridJumpDistance, range: 0.08...0.5,
                              format: { "\(Int($0 * 100))%" }, help: "How far away you must look before the pointer jumps there.")
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
                Text("Calibration, direct aiming and recentring use this display. The pointer can still travel to every display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func badge(_ i: TrackingInput) -> String? {
        switch i {
        case .eyes: "Experimental"
        case .headphones: "No camera"
        default: nil
        }
    }

    private func summary(_ m: MotionStyle, input: TrackingInput) -> String {
        guard input == .headphones else { return m.summary }
        switch m {
        case .relative: return "Moves like a mouse. Small head turns, fine control. Recommended."
        case .direct: return "Your head aims at a spot on screen. Recentre lines it up, no calibration."
        case .joystick: return "Turn away from centre to glide. Least neck movement."
        }
    }

    private func motionSymbol(_ m: MotionStyle) -> String {
        switch m {
        case .relative: "hand.point.up.left"
        case .direct: "scope"
        case .joystick: "gamecontroller"
        }
    }
}

// MARK: - Gestures

struct GesturesPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.settings.input.usesCamera {
            faceGestures
        } else {
            headGestures
        }
    }

    private var headGestures: some View {
        @Bindable var model = model
        return Form {
            Section {
                if !model.isEnabled {
                    Label("Reading your AirPods so the meters are live. Pointer control stays off.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.live.head == nil {
                    Label("Put in your AirPods to see the meters move.", systemImage: "airpodspro")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(HeadGesture.allCases) { g in
                Section {
                    GestureRow(title: g.title, instruction: g.instruction, symbol: g.symbol,
                               binding: Binding(get: { model.settings.binding(for: g) },
                                                set: { model.settings.headGestures[g] = $0 }),
                               activation: model.live.status.headActivations[g] ?? 0,
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

    private var faceGestures: some View {
        @Bindable var model = model
        return Form {
            if !model.isEnabled {
                Section {
                    Label("Showing a camera preview so the meters are live. Pointer control stays off.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(FaceGesture.allCases) { g in
                Section {
                    GestureRow(title: g.title, instruction: g.instruction, symbol: g.symbol,
                               binding: Binding(get: { model.settings.binding(for: g) },
                                                set: { model.settings.gestures[g] = $0 }),
                               activation: model.live.status.activations[g] ?? 0,
                               mirrored: g == .rightWink)
                }
            }
            Section {
                Toggle(isOn: $model.settings.holdSteadyWhileGesturing) {
                    Text("Hold the pointer steady while a gesture forms")
                    Text("Opening your mouth moves your head a little. This keeps clicks exactly where you aimed.")
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Learn my expressions")
                        Text(model.gestureBaseline?.peaks.isEmpty == false ? "Tuned to your face." : "Using typical values.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Teach Nod") { model.windows?.startCalibration(gesturesOnly: true) }
                }
            }
        }
        .formStyle(.grouped)
        .liveFrames(model, id: "settings.gestures", preview: true)
    }
}

struct GestureRow: View {
    let title: String
    let instruction: String
    let symbol: String
    @Binding var binding: GestureBinding
    let activation: Double
    var mirrored = false
    var showsHoldTime = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadge(symbol: symbol, colors: binding.enabled ? [Theme.teal, Theme.blue] : [.gray.opacity(0.7), .gray.opacity(0.5)], size: 28)
                    .scaleEffect(x: mirrored ? -1 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(instruction).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if binding.enabled {
                    ActivationMeter(value: activation, height: 6).frame(width: 110)
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

// MARK: - Calibration

struct CalibrationPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Movement") {
                ProfileRow(input: .nose, profile: model.profiles[.nose])
                ProfileRow(input: .eyes, profile: model.profiles[.eyes])
            }
            Section("Expressions") {
                HStack(spacing: 12) {
                    IconBadge(symbol: "face.smiling", colors: [Theme.teal, Theme.blue], size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Resting face and gesture strength").font(.system(size: 13, weight: .semibold))
                        Text(expressionStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.gestureBaseline != nil {
                        Button("Forget") { model.forgetGestureBaseline() }
                    }
                    Button("Teach") { model.windows?.startCalibration(gesturesOnly: true) }
                }
            }
            Section("AirPods") {
                Tip(symbol: "airpodspro", text: "AirPods need no calibration. Look at the middle of the screen and press Recentre (\(model.settings.recenterHotKey.display)) whenever the pointer drifts.")
            }
            Section("For the best result") {
                Tip(symbol: "sun.max", text: "Light your face from the front. A window behind you makes the face dark.")
                Tip(symbol: "camera.metering.center.weighted", text: "Put the camera at eye level, about an arm's length away.")
                Tip(symbol: "figure.seated.side.right", text: "Sit the way you normally will. Recalibrate if you change chair or posture.")
                Tip(symbol: "eyeglasses", text: "Glasses are fine. Strong reflections can confuse eye tracking.")
            }
        }
        .formStyle(.grouped)
    }

    private var expressionStatus: String {
        guard let b = model.gestureBaseline else { return "Learned automatically each time Nod starts." }
        if b.peaks.isEmpty { return "Resting face learned during calibration." }
        return "Tuned for " + b.peaks.keys.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", ").lowercased() + "."
    }
}

struct ProfileRow: View {
    @Environment(AppModel.self) private var model
    let input: TrackingInput
    let profile: CalibrationProfile?

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: input == .nose ? "nose" : "eye", colors: profile == nil ? [.gray.opacity(0.7), .gray.opacity(0.5)] : [Theme.gold, Theme.ember], size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(input == .nose ? "Nose" : "Eyes").font(.system(size: 13, weight: .semibold))
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if profile != nil {
                Button("Forget") { model.forgetCalibration(input) }
            }
            Button(profile == nil ? "Calibrate" : "Recalibrate") { model.windows?.startCalibration(input: input) }
        }
    }

    private var status: String {
        guard let p = profile else {
            return input == .nose ? "Optional for relative and joystick motion, needed for direct aiming." : "Needed for eye and hybrid tracking."
        }
        let when = p.createdAt.formatted(.relative(presentation: .named))
        return "Calibrated \(when), typical error about \(Int(p.meanErrorPoints.rounded())) pt."
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

// MARK: - Camera

struct CameraPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ZStack {
                    CameraPreview(session: model.pipeline.session)
                    FaceMeshView(sample: model.live.sample, activations: model.live.status.activations,
                                 framing: .camera, showGrid: false, placeholder: .none)
                    VStack {
                        HStack {
                            if let s = model.live.sample {
                                StatusPill(text: lighting(s), color: s.brightness < 0.22 ? Theme.gold : Theme.teal)
                                StatusPill(text: distance(s), color: s.faceScale < 0.07 || s.faceScale > 0.3 ? Theme.gold : Theme.teal)
                            } else {
                                StatusPill(text: model.live.cameraRunning ? "No face" : "Camera off", color: .gray)
                            }
                            Spacer()
                            Text(String(format: "%.0f fps · %.1f ms", model.live.fps, model.live.processingMs))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(.black.opacity(0.45)))
                        }
                        Spacer()
                    }
                    .padding(10)
                }
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .background(Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
            Section {
                Picker("Camera", selection: $model.settings.cameraID) {
                    Text("Automatic").tag(String?.none)
                    ForEach(model.cameraDevices) { d in
                        Text(d.name).tag(String?.some(d.id))
                    }
                }
                Picker("Effort", selection: $model.settings.efficiency) {
                    ForEach(EfficiencyMode.allCases) { m in
                        Text("\(m.title), \(m.summary)").tag(m)
                    }
                }
            } footer: {
                Text("Video never leaves this Mac and nothing is recorded. The camera light is on only while Nod is tracking or showing a preview.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .liveFrames(model, id: "settings.camera", preview: true)
    }

    private func lighting(_ s: FaceSample) -> String {
        s.brightness < 0.22 ? "Too dark" : (s.brightness > 0.85 ? "Very bright" : "Light good")
    }

    private func distance(_ s: FaceSample) -> String {
        s.faceScale < 0.07 ? "Move closer" : (s.faceScale > 0.3 ? "Move back" : "Distance good")
    }
}

/// Live camera video, mirrored like a mirror.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let c = layer.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer as? AVCaptureVideoPreviewLayer, let c = layer.connection, c.isVideoMirroringSupported, !c.isVideoMirrored {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
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
                ShortcutRow(title: "Calibrate", detail: "Opens calibration for the current input.", spec: $model.settings.calibrateHotKey)
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
                .background(RoundedRectangle(cornerRadius: 7).fill(recording ? AnyShapeStyle(Theme.anodized.opacity(0.35)) : AnyShapeStyle(.primary.opacity(0.07))))
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
                PermissionRow(symbol: "camera.fill", title: "Camera",
                              detail: "To see your face. Frames are analysed in memory and dropped immediately.",
                              status: model.cameraPermission) {
                    if model.cameraPermission == .notDetermined {
                        Task {
                            _ = await Permissions.requestCamera()
                            model.refreshPermissions()
                        }
                    } else {
                        Permissions.openCameraSettings()
                    }
                }
                PermissionRow(symbol: "accessibility", title: "Accessibility",
                              detail: "To move the pointer and click for you. Nod reads nothing on screen.",
                              status: model.accessibilityPermission) {
                    Permissions.promptAccessibility()
                    Permissions.openAccessibilitySettings()
                }
                if model.settings.input == .headphones || model.motionPermission != .notDetermined {
                    PermissionRow(symbol: "airpodspro", title: "Headphone motion",
                                  detail: "Only for the AirPods input. macOS asks the first time Nod reads your head movement.",
                                  status: model.motionPermission,
                                  showsButton: model.motionPermission != .notDetermined) {
                        Permissions.openPrivacySettings()
                    }
                }
            }
            Section("Privacy") {
                Tip(symbol: "wifi.slash", text: "Nod makes no network connections. There is no account, analytics or telemetry.")
                Tip(symbol: "internaldrive", text: "Only your settings and calibration numbers are saved, never images.")
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
            IconBadge(symbol: symbol, colors: status.isGranted ? [Theme.green, Color(hex: 0x23A45A)] : [Theme.gold, Theme.ember], size: 28)
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

// MARK: - About

struct AboutPane: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                NodMark(size: 112)
                    .shadow(color: Theme.blue.opacity(0.35), radius: 24, y: 8)
                    .padding(.top, 10)
                Text("Nod").font(.system(size: 30, weight: .bold))
                Text("Your face is the mouse.").font(.system(size: 15)).foregroundStyle(.secondary)
                Text("Version \(Bundle.main.shortVersion)")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
                Text("Hands-free pointer control for macOS. Nod follows your nose or your eyes through the camera you already have, and turns expressions into clicks. Everything happens on your Mac.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, 4)
                HStack(spacing: 10) {
                    Link(destination: URL(string: "https://github.com/ydisli/nod")!) {
                        Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://github.com/ydisli/nod/issues")!) {
                        Label("Report a problem", systemImage: "exclamationmark.bubble")
                    }
                }
                .padding(.top, 6)
                Text("MIT License. Built on Apple Vision, with the 1€ filter by Casiez, Roussel and Vogel.")
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
                IconBadge(symbol: symbol, colors: selected ? [Theme.violet, Theme.blue] : [.gray.opacity(0.55), .gray.opacity(0.4)], size: 28)
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
    /// camera runs even when tracking is off, without moving the pointer.
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
