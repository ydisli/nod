import AppKit
import SwiftUI

/// Nod's visual language: deep graphite surfaces and an anodized titanium
/// accent (violet, blue, teal), with gold for "something is happening".
enum Theme {
    static let teal = Color(hex: 0x2FD5C4)
    static let blue = Color(hex: 0x4C8DFF)
    static let violet = Color(hex: 0x8B6CFA)
    static let gold = Color(hex: 0xF7C04A)
    static let ember = Color(hex: 0xFF7A59)
    static let green = Color(hex: 0x4ADE80)

    static let ink = Color(hex: 0x0B0E14)
    static let inkRaised = Color(hex: 0x141A26)
    static let inkLine = Color.white.opacity(0.09)

    static let anodized = LinearGradient(colors: [violet, blue, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let voltage = LinearGradient(colors: [blue, teal], startPoint: .leading, endPoint: .trailing)
    static let heat = LinearGradient(colors: [teal, gold], startPoint: .leading, endPoint: .trailing)

    static let panel = LinearGradient(colors: [Color(hex: 0x171D2A), Color(hex: 0x0C1017)], startPoint: .top, endPoint: .bottom)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Building blocks

/// A rounded square with a gradient and a white symbol, like System Settings.
struct IconBadge: View {
    let symbol: String
    var colors: [Color] = [Theme.blue, Theme.teal]
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
    }
}

/// Small status capsule with a coloured dot.
struct StatusPill: View {
    let text: String
    let color: Color
    var pulsing = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: pulse ? 4 : 1)
                .scaleEffect(pulse ? 1.15 : 1)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// A horizontal meter with a tick where the gesture triggers (value 1).
struct ActivationMeter: View {
    let value: Double
    var height: CGFloat = 5
    /// The meter shows 0...`range`; the trigger tick sits at 1.
    var range = 1.6

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fill = min(max(value / range, 0), 1) * w
            let tick = w / range
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.1))
                Capsule()
                    .fill(value >= 1 ? AnyShapeStyle(Theme.heat) : AnyShapeStyle(Theme.voltage))
                    .frame(width: max(fill, height))
                    .opacity(value > 0.02 ? 1 : 0)
                Rectangle()
                    .fill(.primary.opacity(0.55))
                    .frame(width: 1.5, height: height + 4)
                    .offset(x: tick - 0.75)
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.08), value: value)
    }
}

/// The big gradient call to action.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.anodized))
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: Theme.blue.opacity(configuration.isPressed ? 0.2 : 0.45), radius: configuration.isPressed ? 4 : 10, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A quiet rounded button for toolbars inside panels.
struct TileButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? AnyShapeStyle(Theme.anodized.opacity(0.9)) : AnyShapeStyle(.primary.opacity(configuration.isPressed ? 0.14 : 0.07)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            )
            .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .contentShape(Rectangle())
    }
}

/// A dark card surface for live visuals.
struct InkCard<Content: View>: View {
    var cornerRadius: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.panel)
            RadialGradient(colors: [Theme.blue.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 220)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            content
        }
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.inkLine, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// Header shown at the top of each settings pane.
struct PaneHeader: View {
    let symbol: String
    let colors: [Color]
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconBadge(symbol: symbol, colors: colors, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }
}

/// A slider with its label and a live value readout.
struct LabeledSlider: View {
    let title: String
    let symbol: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.2f", $0) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12))
                .frame(width: 70, alignment: .leading)
            Slider(value: $value, in: range)
                .controlSize(.small)
            Text(format(value))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}
