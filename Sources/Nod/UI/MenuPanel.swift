import NodCore
import SwiftUI

/// The popover under the menu bar icon: live head, motion style, speed,
/// quick actions.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            header
            HeadCard(height: 164)
            banners
            MotionPicker(selection: $model.settings.motion)
            sliders
            dwellRow
            actions
            Divider().opacity(0.6)
            footer
        }
        .padding(14)
        .frame(width: 332)
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
        if model.headphoneError != nil { return "AirPods problem" }
        if s.paused { return "Paused" }
        if s.scrolling { return "Scroll mode" }
        if s.dragging { return "Dragging" }
        if !s.tracking { return "Waiting for your AirPods…" }
        return "Following your head"
    }

    @ViewBuilder private var banners: some View {
        if let error = model.headphoneError, model.isEnabled {
            Callout(symbol: "exclamationmark.triangle.fill", color: Theme.ember, title: "AirPods problem",
                    detail: error, button: "Retry") {
                model.setEnabled(false)
                model.setEnabled(true)
            }
        } else if model.isEnabled, model.accessibilityPermission != .granted {
            Callout(symbol: "hand.raised.fill", color: Theme.gold, title: "Allow Nod to move the pointer",
                    detail: "Turn on Nod in Accessibility. Already on? Remove it with −, then Allow again.", button: "Allow") {
                Permissions.promptAccessibility()
                Permissions.openAccessibilitySettings()
            }
        } else if model.isEnabled, model.live.running, !model.live.status.tracking {
            Callout(symbol: "airpodspro", color: Theme.blue, title: "Put in your AirPods",
                    detail: "Any AirPods with head tracking for spatial audio, such as AirPods Pro or AirPods Max.",
                    button: nil) {}
        }
    }

    private var sliders: some View {
        @Bindable var model = model
        return VStack(spacing: 6) {
            LabeledSlider(title: "Speed", symbol: "hare", value: $model.settings.speed, range: 0.25...3) {
                String(format: "%.1f×", $0)
            }
            LabeledSlider(title: "Smoothing", symbol: "waveform.path", value: $model.settings.smoothing, range: 0...1) {
                "\(Int($0 * 100))%"
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
            Button {
                model.windows?.showSettings(pane: .help)
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("Help")
            Spacer()
            RateLabel()
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
    }
}

/// Updates on its own, so the rest of the panel does not redraw with it.
private struct RateLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let live = model.live
        Text(model.isEnabled && live.running && live.rate > 0 ? String(format: "%.0f Hz · %.2f ms", live.rate, live.processingMs) : "")
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.tertiary)
    }
}

/// AirPods on a dark card: a dial that shows recent head movement and a
/// horizon that leans with your head, with tilt meters along the bottom.
struct HeadCard: View {
    @Environment(AppModel.self) private var model
    var height: CGFloat

    var body: some View {
        let tracking = model.isEnabled && model.live.status.tracking
        InkCard {
            if tracking {
                LiveHeadDial()
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "airpodspro")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(model.isEnabled ? "Put in your AirPods and look at the screen." : "Nod is off. Switch it on to steer with your AirPods.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            VStack {
                HStack {
                    pill
                    Spacer()
                    if model.live.status.frozen && model.isEnabled {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.gold)
                            .help("Pointer held steady while a tilt forms")
                    }
                }
                Spacer()
                if tracking {
                    LiveGestureStrip()
                }
            }
            .padding(10)
        }
        .frame(height: height)
    }

    private var pill: some View {
        let s = model.live.status
        if !model.isEnabled { return StatusPill(text: "Off", color: .gray) }
        if model.headphoneError != nil { return StatusPill(text: "Problem", color: Theme.ember) }
        if s.paused { return StatusPill(text: "Paused", color: Theme.gold) }
        if s.tracking { return StatusPill(text: "AirPods", color: Theme.teal) }
        return StatusPill(text: "No AirPods", color: Theme.gold)
    }
}

/// The only views that read the fast moving head data.
private struct LiveHeadDial: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let m = model.live.motion
        HeadDial(offset: m.offset, lean: m.lean,
                 leaning: max(m.activations[.tiltLeft] ?? 0, m.activations[.tiltRight] ?? 0))
    }
}

private struct LiveGestureStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let a = model.live.motion.activations
        GestureStrip(items: HeadGesture.allCases.filter { model.settings.binding(for: $0).enabled }.map {
            GestureStrip.Item(id: $0.rawValue, symbol: $0.symbol, title: $0.title, activation: a[$0] ?? 0)
        })
    }
}

/// A round dial: the dot is where the head has just moved, the line is the
/// head's sideways lean (it turns gold as a tilt gets close to clicking).
/// Drawn in one Canvas without shadows or animations, because it redraws
/// many times a second.
struct HeadDial: View {
    let offset: Vec2
    let lean: Double
    let leaning: Double

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func circle(_ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
            }
            ctx.stroke(circle(r - 0.5), with: .color(.white.opacity(0.14)), lineWidth: 1)
            ctx.stroke(circle(r / 2), with: .color(.white.opacity(0.07)), lineWidth: 1)
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
            ctx.stroke(cross, with: .color(.white.opacity(0.06)), lineWidth: 1)

            let half = r * 0.85
            let dx = cos(lean) * half, dy = sin(lean) * half
            var horizon = Path()
            horizon.move(to: CGPoint(x: c.x - dx, y: c.y - dy))
            horizon.addLine(to: CGPoint(x: c.x + dx, y: c.y + dy))
            let lineColor = leaning >= 1 ? Theme.gold : Theme.blue.opacity(0.35 + 0.5 * min(leaning, 1))
            ctx.stroke(horizon, with: .color(lineColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            let p = CGPoint(x: c.x + offset.x * r * 0.9, y: c.y + offset.y * r * 0.9)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)), with: .color(Theme.teal.opacity(0.18)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(Theme.teal))
        }
    }
}

/// Mini meters for each enabled gesture.
struct GestureStrip: View {
    struct Item: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let activation: Double
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(item.activation >= 1 ? Theme.gold : .white.opacity(0.75))
                        .frame(width: 14)
                    ActivationMeter(value: item.activation, height: 4, animated: false)
                        .frame(width: 38)
                }
                .help(item.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.4)))
    }
}

/// Relative, Direct or Joystick as tiles.
struct MotionPicker: View {
    @Binding var selection: MotionStyle

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MotionStyle.allCases) { style in
                Button {
                    selection = style
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: style.symbol)
                        Text(style.title)
                    }
                }
                .buttonStyle(TileButtonStyle(active: selection == style))
                .help(style.summary)
            }
        }
    }
}

extension MotionStyle {
    var symbol: String {
        switch self {
        case .relative: "hand.point.up.left"
        case .direct: "scope"
        case .joystick: "gamecontroller"
        }
    }
}

/// A compact inline notice with one action.
struct Callout: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let button: String?
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
            if let button {
                Button(button, action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.3), lineWidth: 0.5))
    }
}
