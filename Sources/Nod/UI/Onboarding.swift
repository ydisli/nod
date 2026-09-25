import NodCore
import SwiftUI

/// First run: what Nod is, permissions, how to steer, how to click, calibrate.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step: Int
    let finish: (_ calibrate: Bool) -> Void

    init(startAt step: Int = 0, finish: @escaping (_ calibrate: Bool) -> Void) {
        _step = State(initialValue: step)
        self.finish = finish
    }

    private let steps = 5

    var body: some View {
        ZStack {
            Theme.panel
            RadialGradient(colors: [Theme.violet.opacity(0.22), .clear], center: UnitPoint(x: 0.85, y: 0.1), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.teal.opacity(0.12), .clear], center: UnitPoint(x: 0.1, y: 1), startRadius: 0, endRadius: 420)

            VStack(spacing: 0) {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissions
                    case 2: steering
                    case 3: clicking
                    default: calibrate
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)

                bottomBar
            }
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .padding(.bottom, 26)
        }
        .frame(width: 780, height: 540)
        .environment(\.colorScheme, .dark)
        .onAppear { model.watchPermissions(true, client: "onboarding") }
        .onDisappear { model.watchPermissions(false, client: "onboarding") }
    }

    // MARK: Steps

    private var welcome: some View {
        HStack(spacing: 36) {
            VStack(alignment: .leading, spacing: 16) {
                NodMark(size: 64)
                    .shadow(color: Theme.blue.opacity(0.4), radius: 18, y: 6)
                Text("Meet Nod").font(.system(size: 38, weight: .bold))
                Text("Your face is the mouse.")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.anodized)
                Text("Move the pointer with your nose or your eyes. Click by opening your mouth, raising your eyebrows or simply resting on a spot. All through the camera you already have.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    chip("lock.fill", "On-device")
                    chip("video.slash.fill", "No recording")
                    chip("chevron.left.forwardslash.chevron.right", "Open source")
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 360, alignment: .leading)

            InkCard(cornerRadius: 22) {
                FaceMeshView(sample: nil, placeholder: .demo)
            }
            .frame(width: 290, height: 330)
            .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Two permissions", "macOS asks you to approve both. Nod uses them for nothing else.")
            VStack(spacing: 12) {
                PermissionCard(symbol: "camera.fill", title: "Camera", detail: "So Nod can see your face. Frames are analysed in memory and thrown away.",
                               status: model.cameraPermission, buttonTitle: model.cameraPermission == .notDetermined ? "Allow Camera" : "Open Settings") {
                    if model.cameraPermission == .notDetermined {
                        Task {
                            _ = await Permissions.requestCamera()
                            model.refreshPermissions()
                        }
                    } else {
                        Permissions.openCameraSettings()
                    }
                }
                PermissionCard(symbol: "accessibility", title: "Accessibility", detail: "So Nod can move the pointer and click for you. Turn on Nod in the list that opens.",
                               status: model.accessibilityPermission, buttonTitle: "Open Settings") {
                    Permissions.promptAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }
            Text("Built Nod yourself? macOS remembers the permission per build, so a fresh build asks again.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: 620)
    }

    private var steering: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 18) {
            stepTitle("How do you want to steer?", "You can switch any time from the menu bar.")
            HStack(spacing: 14) {
                ForEach(TrackingInput.allCases) { input in
                    BigChoice(symbol: input == .nose ? "nose" : (input == .eyes ? "eye" : "sparkles"),
                              title: input.title, detail: input.summary,
                              badge: input == .nose ? "Recommended" : (input == .eyes ? "Experimental" : nil),
                              selected: model.settings.input == input) {
                        model.settings.input = input
                    }
                }
            }
        }
    }

    private var clicking: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 18) {
            stepTitle("How do you want to click?", "Pick any combination. Each can be tuned later.")
            VStack(spacing: 10) {
                ToggleCard(symbol: "mouth", title: "Open your mouth to click",
                           detail: "Keep it open to hold the button and drag.",
                           isOn: gestureBinding(.mouthOpen))
                ToggleCard(symbol: "eyebrow", title: "Raise your eyebrows to right click",
                           detail: "Opens context menus.",
                           isOn: gestureBinding(.browRaise))
                ToggleCard(symbol: "timer", title: "Rest on a spot to click",
                           detail: "Dwell clicking, with a palette for right click, double click, drag and scroll.",
                           isOn: $model.settings.dwell.enabled)
                ToggleCard(symbol: "eye.slash", title: "Close your eyes for a moment to pause",
                           detail: "And again to resume. Handy for reading.",
                           isOn: gestureBinding(.longBlink))
            }
        }
        .frame(maxWidth: 640)
    }

    private var calibrate: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.anodized, lineWidth: 3).frame(width: 110, height: 110)
                Circle().stroke(Theme.anodized.opacity(0.4), lineWidth: 2).frame(width: 150, height: 150)
                Circle().fill(.white).frame(width: 12, height: 12)
                    .shadow(color: Theme.teal, radius: 10)
            }
            Text("Last step, a 20 second calibration").font(.system(size: 26, weight: .bold))
            Text(model.settings.input == .nose
                 ? "Point your nose at nine dots. Nod learns how far you like to move, so a comfortable turn reaches every corner."
                 : "Follow nine dots with your eyes, keeping your head still. Nod learns how your eyes map to the screen.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Text("Everything advances on its own. Press Esc at any time to stop.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: Chrome

    private var bottomBar: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? AnyShapeStyle(Theme.anodized) : AnyShapeStyle(.white.opacity(0.18)))
                        .frame(width: i == step ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.35), value: step)
            Spacer()
            if step > 0 {
                Button("Back") { go(step - 1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.trailing, 12)
            }
            if step < steps - 1 {
                Button(step == 0 ? "Get Started" : "Continue") { go(step + 1) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 1 && model.cameraPermission != .granted)
            } else {
                Button("Skip for Now") { finish(false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.trailing, 12)
                Button("Start Calibration") { finish(true) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func go(_ s: Int) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = s }
    }

    private func stepTitle(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).font(.system(size: 28, weight: .bold))
            Text(s).font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
    }

    private func gestureBinding(_ g: FaceGesture) -> Binding<Bool> {
        Binding(get: { model.settings.binding(for: g).enabled },
                set: { on in
                    var b = model.settings.binding(for: g)
                    b.enabled = on
                    model.settings.gestures[g] = b
                })
    }
}

struct PermissionCard: View {
    let symbol: String
    let title: String
    let detail: String
    let status: PermissionStatus
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, colors: status.isGranted ? [Theme.green, Color(hex: 0x23A45A)] : [Theme.blue, Theme.violet], size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if status.isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.green)
            } else {
                Button(buttonTitle, action: action)
                    .controlSize(.large)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(status.isGranted ? Theme.green.opacity(0.35) : .white.opacity(0.08), lineWidth: 1))
        .animation(.easeOut(duration: 0.25), value: status)
    }
}

struct BigChoice: View {
    let symbol: String
    let title: String
    let detail: String
    let badge: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    IconBadge(symbol: symbol, colors: selected ? [Theme.violet, Theme.teal] : [.gray.opacity(0.55), .gray.opacity(0.35)], size: 44)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? AnyShapeStyle(Theme.teal) : AnyShapeStyle(.white.opacity(0.25)))
                }
                Text(title).font(.system(size: 18, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill((badge == "Recommended" ? Theme.teal : Theme.gold).opacity(0.18)))
                        .foregroundStyle(badge == "Recommended" ? Theme.teal : Theme.gold)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(selected ? 0.09 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(Theme.anodized) : AnyShapeStyle(.white.opacity(0.08)), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: selected)
    }
}

struct ToggleCard: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, colors: isOn ? [Theme.teal, Theme.blue] : [.gray.opacity(0.55), .gray.opacity(0.35)], size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(isOn ? 0.07 : 0.035)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}
