import NodCore
import SwiftUI

/// First run: what Nod is, permissions, how to click, then go.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step: Int
    let finish: () -> Void

    init(startAt step: Int = 0, finish: @escaping () -> Void) {
        _step = State(initialValue: step)
        self.finish = finish
    }

    private let steps = 4

    var body: some View {
        ZStack {
            Theme.tourBackdrop

            VStack(spacing: 0) {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissions
                    case 2: clicking
                    default: ready
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
                Text("Meet Nod").font(.system(size: 38, weight: .bold))
                Text("Your head is the mouse.")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Turn your head to move the pointer, using the motion sensors in your AirPods. Click with a key, a lean of the head or by resting on a spot. No camera.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    chip("lock.fill", "On-device")
                    chip("video.slash.fill", "No camera")
                    chip("chevron.left.forwardslash.chevron.right", "Open source")
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 360, alignment: .leading)

            InkCard(cornerRadius: 22) {
                VStack(spacing: 18) {
                    Image(systemName: "airpodspro")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Theme.teal)
                    HeadDial(offset: Vec2(0.4, -0.25), lean: -0.14, leaning: 0.5)
                        .frame(width: 170, height: 170)
                }
            }
            .frame(width: 290, height: 330)
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Two permissions", "Nod uses them for nothing else.")
            VStack(spacing: 12) {
                PermissionCard(symbol: "accessibility", title: "Accessibility", detail: "So Nod can move the pointer and click for you. Turn on Nod in the list that opens.",
                               status: model.accessibilityPermission, buttonTitle: "Open Settings") {
                    Permissions.promptAccessibility()
                    Permissions.openAccessibilitySettings()
                }
                PermissionCard(symbol: "airpodspro", title: "Headphone motion", detail: "So Nod can read how your head turns. macOS asks the first time Nod starts, with your AirPods in.",
                               status: model.motionPermission, buttonTitle: nil) {}
            }
            Text("Built Nod yourself? macOS remembers Accessibility per build signature, so an unsigned build may ask again.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: 620)
    }

    private var clicking: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 18) {
            stepTitle("How do you want to click?", "Pick any combination. Each can be tuned later.")
            VStack(spacing: 10) {
                ToggleCard(symbol: "keyboard", title: "Tap right ⌘ to click",
                           detail: "Right ⌥ right clicks. Tap twice to double click, hold to drag.",
                           isOn: $model.settings.clickKeys.enabled)
                ToggleCard(symbol: HeadGesture.tiltLeft.symbol, title: "Lean your head left to click",
                           detail: "Keep leaning to hold the button, then turn to drag.",
                           isOn: headBinding(.tiltLeft))
                ToggleCard(symbol: HeadGesture.tiltRight.symbol, title: "Lean your head right to right click",
                           detail: "Opens context menus.",
                           isOn: headBinding(.tiltRight))
                ToggleCard(symbol: "timer", title: "Rest on a spot to click",
                           detail: "Dwell clicking, with a palette for right click, double click, drag and scroll.",
                           isOn: $model.settings.dwell.enabled)
                ToggleCard(symbol: HeadGesture.nod.symbol, title: "Nod to double click",
                           detail: "A quick nod down and up. Glancing at the keyboard can look similar.",
                           isOn: headBinding(.nod))
            }
        }
        .frame(maxWidth: 640)
    }

    private var ready: some View {
        VStack(spacing: 18) {
            Image(systemName: "airpodspro")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Theme.teal)
                .frame(height: 150)
            Text("Ready when your AirPods are").font(.system(size: 26, weight: .bold))
            Text("Put them in and look at the middle of the screen. Turn your head to move the pointer. If it ever drifts, look at the middle and press \(model.settings.recenterHotKey.display).")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Text("Press \(model.settings.toggleHotKey.display) at any time to switch Nod on or off.")
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
                        .fill(i == step ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.white.opacity(0.18)))
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
            } else {
                Button("Start Nod") { finish() }
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

    private func headBinding(_ g: HeadGesture) -> Binding<Bool> {
        Binding(get: { model.settings.binding(for: g).enabled },
                set: { on in
                    var b = model.settings.binding(for: g)
                    b.enabled = on
                    model.settings.headGestures[g] = b
                })
    }
}

struct PermissionCard: View {
    let symbol: String
    let title: String
    let detail: String
    let status: PermissionStatus
    /// nil when only macOS can ask (it does so on first use).
    let buttonTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, color: status.isGranted ? Theme.green : Theme.blue, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if status.isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.green)
            } else if let buttonTitle {
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

struct ToggleCard: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, color: isOn ? Theme.teal : .gray.opacity(0.55), size: 34)
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
