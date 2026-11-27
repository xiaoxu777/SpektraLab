// Appearance uses the same rows as the other Settings pages. The first background swatch restores its default.
import SwiftUI
import UIKit

@MainActor
struct AppearanceStyle {
    let pt: (CGFloat) -> CGFloat
    static let mac = AppearanceStyle(pt: { MacMetric.pt($0) })
}

struct AppearanceSettings: View {
    let style: AppearanceStyle
    @AppStorage(AppAppearance.key) private var mode = AppAppearance.standard.rawValue
    @AppStorage(InterfaceScale.key) private var scale = InterfaceScale.standard.rawValue
    @AppStorage(AppBackground.darkKey) private var darkGround = ""
    @AppStorage(AppBackground.lightKey) private var lightGround = ""
    @Environment(\.colorScheme) private var scheme
    private var light: Bool { scheme == .light }
    private var ground: UInt32 {
        _ = light ? lightGround : darkGround
        return AppBackground.ground(light: light)
    }

    var body: some View {
        MacSettingsGroup(title: nil) {
            MacSettingsRow(label: L("Mode")) {
                HStack(spacing: MacMetric.pt(10)) {
                    ForEach(AppAppearance.allCases, id: \.self) { choice in
                        Button { mode = choice.rawValue } label: {
                            VStack(spacing: MacMetric.pt(8)) {
                                AppearanceThumbnail(choice: choice, pt: style.pt)
                                    .frame(width: MacMetric.pt(96), height: MacMetric.pt(60))
                                    .clipShape(RoundedRectangle(cornerRadius: MacMetric.pt(6)))
                                    .padding(MacMetric.pt(3))
                                    .overlay(RoundedRectangle(cornerRadius: MacMetric.pt(9))
                                        .strokeBorder(mode == choice.rawValue ? Theme.accent : Theme.wall, lineWidth: 2))
                                Text(choice.title).font(MacMetric.font(13, .medium)).foregroundStyle(Theme.text).fixedSize()
                            }
                            .padding(.vertical, MacMetric.pt(6)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(mode == choice.rawValue ? .isSelected : [])
                        .accessibilityIdentifier("appearance.mode.\(choice.rawValue)")
                    }
                }
            }
            .macSettingsItem("Appearance", "Mode", "System", "Light", "Dark")
            MacSettingsRow(label: L("Background")) {
                HStack(spacing: MacMetric.pt(8)) {
                    ForEach(Array(AppBackground.presets(light: light).enumerated()), id: \.offset) { index, hex in
                        Button { AppBackground.choose(index == 0 ? nil : hex, light: light) } label: {
                            Circle().fill(Color(hex: hex))
                                .overlay(Circle().strokeBorder(ground == hex ? Theme.accent : Theme.dim, lineWidth: ground == hex ? 2 : 1))
                                .padding(MacMetric.pt(3))
                                .frame(width: MacMetric.pt(32), height: MacMetric.pt(34))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(index == 0 ? L("Use Default") : AppBackground.hexString(hex))
                        .accessibilityAddTraits(ground == hex ? .isSelected : [])
                    }
                    ColorPicker(L("Custom colour"), selection: Binding(get: { Color(hex: ground) },
                        set: { AppBackground.choose(AppBackground.hex(of: $0), light: light) }), supportsOpacity: false)
                        .labelsHidden().frame(width: MacMetric.pt(32), height: MacMetric.pt(34))
                        .opacity(0.02)
                        .overlay {
                            // The system picker remains the hit target; only its dark pill is replaced.
                            Circle().fill(Color(hex: ground))
                                .overlay(Circle().strokeBorder(AngularGradient(
                                    colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center), lineWidth: 2))
                                .padding(MacMetric.pt(3))
                                .allowsHitTesting(false)
                        }
                        .accessibilityIdentifier("appearance.background.well")
                }
                .accessibilityIdentifier("appearance.background")
            }
            .macSettingsItem("Background")
            MacSettingsRow(label: L("Interface scale"), last: true) {
                MacSettingsSegments(label: L("Interface scale"), options: InterfaceScale.allCases.map { ($0, $0.title) },
                                    selection: Binding(get: { InterfaceScale(rawValue: scale) ?? .standard }, set: { scale = $0.rawValue }))
                    .accessibilityIdentifier("appearance.scale")
            }
            .macSettingsItem("Interface scale")
        }
    }

    // Retained for the existing screenshot driver; the colour controls are now always visible.
    static let openPicker = Notification.Name("spk.appearance.picker")
}

/// A mode's card: a small window drawn in that mode's own grounds — its bar, the column, a picture, the
/// filmstrip — from the tokens themselves, resolved for that mode (System: Light's left half, Dark's right).
private struct AppearanceThumbnail: View {
    let choice: AppAppearance
    let pt: (CGFloat) -> CGFloat
    @AppStorage(AppBackground.darkKey) private var darkGround = ""
    @AppStorage(AppBackground.lightKey) private var lightGround = ""

    var body: some View {
        _ = (darkGround, lightGround)       // read, so the cards follow a chosen ground
        return GeometryReader { geo in
            switch choice {
            case .light: window(light: true, in: geo.size)
            case .dark: window(light: false, in: geo.size)
            case .system:
                ZStack {
                    window(light: true, in: geo.size)
                    window(light: false, in: geo.size)
                        .mask(alignment: .trailing) { Rectangle().frame(width: geo.size.width / 2) }
                }
            }
        }
    }

    /// A token as it is in the mode `light`.
    private func tone(_ c: Color, _ light: Bool) -> Color {
        Color(uiColor: UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: light ? .light : .dark)))
    }

    private func window(light: Bool, in size: CGSize) -> some View {
        let bar = size.height * 0.16
        let column = size.width * 0.34
        let strip = size.height * 0.2
        return ZStack(alignment: .topLeading) {
            tone(Theme.background, light)
            // The column, its card and three lines of words.
            VStack(alignment: .leading, spacing: pt(3)) {
                RoundedRectangle(cornerRadius: pt(2)).fill(tone(Theme.card, light)).frame(height: size.height * 0.16)
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(tone(Theme.text, light).opacity(0.5)).frame(width: column * (i == 1 ? 0.45 : 0.62), height: pt(2.5))
                }
            }
            .padding(pt(4))
            .frame(width: column, height: size.height, alignment: .topLeading)
            .background(tone(Theme.panel, light))
            // The bar over the picture side: the way back and the accent's Export.
            HStack(spacing: pt(3)) {
                Capsule().fill(tone(Theme.text, light).opacity(0.5)).frame(width: pt(12), height: pt(2.5))
                Spacer(minLength: 0)
                Capsule().fill(Theme.accent).frame(width: pt(14), height: pt(5))
            }
            .padding(.horizontal, pt(5))
            .frame(width: size.width - column, height: bar)
            .offset(x: column)
            // The picture and the filmstrip under it.
            LinearGradient(colors: [Theme.edgeInk.opacity(0.8), Theme.rebate], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: size.width - column - pt(10), height: size.height - bar - strip - pt(4))
                .offset(x: column + pt(5), y: bar)
            HStack(spacing: pt(2)) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: pt(1)).fill(tone(Theme.card, light)).frame(width: pt(9), height: strip - pt(6))
                }
            }
            .frame(width: size.width - column, height: strip)
            .background(alignment: .top) { tone(Theme.wall, light).frame(height: 1) }
            .offset(x: column, y: size.height - strip)
            Rectangle().fill(tone(Theme.wall, light)).frame(width: 1, height: size.height).offset(x: column)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
