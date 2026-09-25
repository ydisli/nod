import NodCore
import SwiftUI

/// The popover under the menu bar icon: live face, mode, speed, quick actions.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            header
            FaceCard(height: 176)
            banners
            InputPicker(selection: $model.settings.input)
            sliders
            dwellRow
            actions
            Divider().opacity(0.6)
            footer
        }
        .padding(14)
        .frame(width: 332)
        .onAppear {
            model.retainFrames("menu")
            model.watchPermissions(true, client: "menu")
        }
        .onDisappear {
            model.releaseFrames("menu")
            model.watchPermissions(false, client: "menu")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            NodMark(size: 30, detailed: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("Nod").font(.system(size: 15, weight: .semibold))
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Start or stop Nod (\(model.settings.toggleHotKey.display))")
        }
    }

    private var statusLine: String {
        let s = model.live.status
        if !model.isEnabled {
            let key = model.settings.toggleHotKey
            return key.isEnabled ? "Off. Press \(key.display) to start" : "Off"
        }
        if model.cameraError != nil { return "Camera problem" }
        if !model.live.cameraRunning { return "Starting camera…" }
        if s.paused { return "Paused" }
        if s.scrolling { return "Scroll mode" }
        if s.dragging { return "Dragging" }
        if !s.faceVisible { return "Looking for your face…" }
        switch model.settings.input {
        case .nose: return "Following your nose"
        case .eyes: return "Following your eyes"
        case .hybrid: return "Following eyes and nose"
        }
    }

    @ViewBuilder private var banners: some View {
        if model.cameraPermission == .denied {
            Callout(symbol: "camera.fill", color: Theme.ember, title: "Camera access is off",
                    detail: "Nod needs the camera to see your face.", button: "Open Settings") {
                Permissions.openCameraSettings()
            }
        } else if model.isEnabled, model.accessibilityPermission != .granted {
            Callout(symbol: "hand.raised.fill", color: Theme.gold, title: "Allow Nod to move the pointer",
                    detail: "Turn on Nod in Accessibility. Already on? Remove it with −, then Allow again.", button: "Allow") {
                Permissions.promptAccessibility()
                Permissions.openAccessibilitySettings()
            }
        } else if let error = model.cameraError, model.isEnabled {
            Callout(symbol: "exclamationmark.triangle.fill", color: Theme.ember, title: "Camera problem",
                    detail: error, button: "Retry") {
                model.setEnabled(false)
                model.setEnabled(true)
            }
        } else if model.live.status.needsCalibration {
            Callout(symbol: "scope", color: Theme.violet, title: "Calibrate to use this mode",
                    detail: "Takes about 20 seconds.", button: "Calibrate") {
                model.windows?.startCalibration()
            }
        }
    }

    private var sliders: some View {
        @Bindable var model = model
        return VStack(spacing: 6) {
            LabeledSlider(title: "Speed", symbol: "hare", value: $model.settings.speed, range: 0.25...3) {
                String(format: "%.1f×", $0)
            }
            if model.settings.input == .eyes {
                LabeledSlider(title: "Steadiness", symbol: "waveform.path", value: $model.settings.eyeSmoothing, range: 0...1) {
                    "\(Int($0 * 100))%"
                }
            } else {
                LabeledSlider(title: "Smoothing", symbol: "waveform.path", value: $model.settings.smoothing, range: 0...1) {
                    "\(Int($0 * 100))%"
                }
            }
        }
    }

    private var dwellRow: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Toggle(isOn: $model.settings.dwell.enabled) {
                HStack(spacing: 6) {
                    Image(systemName: "timer").foregroundStyle(.secondary)
                    Text("Dwell to click").font(.system(size: 12))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Spacer()
            if model.settings.dwell.enabled {
                Menu {
                    ForEach(PointerAction.dwellChoices) { action in
                        Button {
                            model.chooseDwellAction(action)
                        } label: {
                            Label(action.title, systemImage: action.symbol)
                        }
                    }
                } label: {
                    Label(model.live.status.dwellAction.shortTitle, systemImage: model.live.status.dwellAction.symbol)
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("What the next dwell does")
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button { model.recenter() } label: {
                VStack(spacing: 3) { Image(systemName: "scope").frame(height: 16); Text("Recentre") }
            }
            .buttonStyle(TileButtonStyle())
            .help("Put the pointer back in the middle (\(model.settings.recenterHotKey.display))")

            Button { model.windows?.startCalibration() } label: {
                VStack(spacing: 3) { Image(systemName: "target").frame(height: 16); Text("Calibrate") }
            }
            .buttonStyle(TileButtonStyle())

            Button { model.windows?.togglePalette() } label: {
                VStack(spacing: 3) { Image(systemName: "square.grid.2x2").frame(height: 16); Text("Palette") }
            }
            .buttonStyle(TileButtonStyle(active: model.isPaletteVisible))

            Button { model.perform(.pauseToggle) } label: {
                VStack(spacing: 3) {
                    Image(systemName: model.live.status.paused ? "play.fill" : "pause.fill").frame(height: 16)
                    Text(model.live.status.paused ? "Resume" : "Pause")
                }
            }
            .buttonStyle(TileButtonStyle(active: model.live.status.paused))
            .disabled(!model.isEnabled)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                model.windows?.showSettings(pane: nil)
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Text(model.isEnabled && model.live.cameraRunning ? String(format: "%.0f fps · %.1f ms", model.live.fps, model.live.processingMs) : "")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
    }
}

/// The live face on a dark card, with gesture meters along the bottom.
struct FaceCard: View {
    @Environment(AppModel.self) private var model
    var height: CGFloat

    var body: some View {
        InkCard {
            FaceMeshView(sample: model.live.sample, activations: model.live.status.activations,
                         placeholder: model.isEnabled ? .searching : .demo)
            VStack {
                HStack {
                    pill
                    Spacer()
                    if model.live.status.frozen && model.isEnabled {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.gold)
                            .help("Pointer held steady while a gesture forms")
                    }
                }
                Spacer()
                if model.isEnabled {
                    GestureStrip(activations: model.live.status.activations, bindings: model.settings.gestures)
                } else {
                    Text("Nod is off. Switch it on to see yourself tracked.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(10)
        }
        .frame(height: height)
    }

    private var pill: some View {
        let s = model.live.status
        if !model.isEnabled { return StatusPill(text: "Preview", color: .gray) }
        if !model.live.cameraRunning { return StatusPill(text: "Camera", color: Theme.gold) }
        if s.paused { return StatusPill(text: "Paused", color: Theme.gold) }
        if s.faceVisible { return StatusPill(text: "Tracking", color: Theme.teal, pulsing: true) }
        return StatusPill(text: "No face", color: Theme.ember)
    }
}

/// Mini meters for each enabled gesture.
struct GestureStrip: View {
    let activations: [FaceGesture: Double]
    let bindings: [FaceGesture: GestureBinding]

    var body: some View {
        let enabled = FaceGesture.allCases.filter { bindings[$0]?.enabled == true }
        HStack(spacing: 10) {
            ForEach(enabled) { g in
                HStack(spacing: 5) {
                    Image(systemName: g.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle((activations[g] ?? 0) >= 1 ? Theme.gold : .white.opacity(0.75))
                        .frame(width: 14)
                    ActivationMeter(value: activations[g] ?? 0, height: 4)
                        .frame(width: 38)
                }
                .help(g.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.4)))
    }
}

/// Nose, Eyes or Hybrid as three tiles.
struct InputPicker: View {
    @Binding var selection: TrackingInput

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TrackingInput.allCases) { input in
                Button {
                    selection = input
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: symbol(input))
                        Text(input.title)
                    }
                }
                .buttonStyle(TileButtonStyle(active: selection == input))
                .help(input.summary)
            }
        }
    }

    private func symbol(_ i: TrackingInput) -> String {
        switch i {
        case .nose: "nose"
        case .eyes: "eye"
        case .hybrid: "sparkles"
        }
    }
}

/// A compact inline notice with one action.
struct Callout: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(button, action: action)
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.3), lineWidth: 0.5))
    }
}
