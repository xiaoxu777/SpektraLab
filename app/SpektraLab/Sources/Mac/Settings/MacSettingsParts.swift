// Shared Settings rows and controls, in FilmLab’s own tokens and Mac point scale.
import SwiftUI

enum MacSettingsMetric {
    /// The section list's width, Mac points.
    static let sidebar: CGFloat = 176
    /// A row holds a 34-point control with breathing room.
    static let row: CGFloat = 52
    /// The content's widest: past it the rows would be read across a whole display.
    static let readable: CGFloat = 680
    static let inset: CGFloat = 16
    static let gap: CGFloat = 20
    static let control: CGFloat = 34
}

/// A group: its heading in small capitals, its rows in one box, and a caption under the box.
struct MacSettingsGroup<Content: View, Accessory: View>: View {
    let title: String?
    var footer: String? = nil
    /// A heading of the page's own words is in small capitals; a name the user gave (a recipe's) is not.
    var capitals = true
    let accessory: () -> Accessory
    let content: () -> Content

    /// `accessory`: a control at the heading's trailing edge (*Open Catalog or Folder…*).
    init(title: String?, footer: String? = nil, capitals: Bool = true, @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.footer = footer
        self.capitals = capitals
        self.content = content
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(8)) {
            if let title {
                HStack(alignment: .lastTextBaseline, spacing: MacMetric.pt(8)) {
                    // Design A: group titles in their own case, quiet, as the column's sections (2026-11-24).
                    Text(title).font(MacMetric.font(13, .semibold)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    accessory()
                }
                .padding(.horizontal, MacMetric.pt(4))
            }
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: MacMetric.pt(10), style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MacMetric.pt(10), style: .continuous).strokeBorder(Theme.wall, lineWidth: 1))
            if let footer {
                MacSettingsCaption(footer).padding(.horizontal, MacMetric.pt(4))
            }
        }
    }
}

extension MacSettingsGroup where Accessory == EmptyView {
    init(title: String?, footer: String? = nil, capitals: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, footer: footer, capitals: capitals, content: content, accessory: { EmptyView() })
    }
}

/// Title and supporting words stay together; the trailing control is centred against that stack.
/// `compact` is for reference lists without full-height controls.
struct MacSettingsRow<Control: View>: View {
    let label: String
    var detail: String? = nil
    var caption: String? = nil
    var wrapsDetail = false
    var compact = false
    var last = false
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(5)) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MacMetric.pt(16)) {
                    // Long supporting text wraps before we consider moving the control below it.
                    words.frame(minWidth: MacMetric.pt(100), idealWidth: MacMetric.pt(100),
                                maxWidth: .infinity, alignment: .leading)
                    control().fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: MacMetric.pt(10)) {
                    words
                    HStack { Spacer(minLength: 0); control() }
                }
            }
        }
        .padding(.horizontal, MacMetric.pt(MacSettingsMetric.inset))
        .padding(.vertical, MacMetric.pt(compact ? 4 : 10))
        .frame(minHeight: MacMetric.pt(compact ? 32 : MacSettingsMetric.row))
        .overlay(alignment: .bottom) {
            if !last { MacSettingsHairline().padding(.horizontal, MacMetric.pt(MacSettingsMetric.inset)) }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(4)) {
            Text(label).font(MacMetric.font(14, .medium)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                if wrapsDetail {
                    Text(verbatim: detail).font(MacMetric.font(11).monospaced())
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else {
                    // Paths grow the row instead of ending at a hidden scroll viewport.
                    Text(verbatim: detail).font(MacMetric.font(12)).foregroundStyle(Theme.secondaryText)
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if let caption { MacSettingsCaption(caption) }
        }
    }

}

extension MacSettingsRow where Control == EmptyView {
    init(label: String, detail: String? = nil, caption: String? = nil, wrapsDetail: Bool = false,
         compact: Bool = false, last: Bool = false) {
        self.init(label: label, detail: detail, caption: caption, wrapsDetail: wrapsDetail,
                  compact: compact, last: last) { EmptyView() }
    }
}

/// A value read, not set: the words at the leading edge, the value at the trailing edge in the
/// secondary grey, wrapping when it is long (a path, an engine's stamp).
struct MacSettingsValueRow: View {
    let label: String
    let value: String
    var caption: String? = nil
    var last = false

    var body: some View {
        MacSettingsRow(label: label, caption: caption, last: last) {
            Text(value).font(MacMetric.font(13)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: MacMetric.pt(360), alignment: .trailing)
                .textSelection(.enabled)
        }
    }
}

/// The faint line between two rows of one box (the lower of the two tiers).
struct MacSettingsHairline: View {
    var body: some View { Rectangle().fill(Theme.wall).frame(height: 1) }
}

/// A caption: what a setting does, in the page's smallest type, wrapping.
struct MacSettingsCaption: View {
    let text: String
    var color: Color = Theme.dim
    init(_ text: String, color: Color = Theme.dim) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text).font(MacMetric.font(12)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A switch with the same binding and accessibility labels as the former checkbox.
struct MacSettingsCheckbox: View {
    let label: String
    @Binding var on: Bool

    var body: some View {
        Toggle(label, isOn: $on)
            .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
            .accessibilityLabel(label)
            .accessibilityValue(on ? L("On") : L("Off"))
    }

}

/// A pop-up button: the chosen value and the up-down chevron on the card colour, a menu of the
/// choices with the chosen one ticked. `allowed` false shows a choice greyed, and it takes nothing.
struct MacSettingsPopUp<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value
    var allowed: (Value) -> Bool = { _ in true }
    /// What the button says when the selection is none of the options (a kept value from elsewhere).
    var other: String? = nil
    var face: String? = nil
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                if allowed(option.0) {
                    Button { selection = option.0 } label: {
                        if option.0 == selection { Label(option.1, systemImage: "checkmark") } else { Text(option.1) }
                    }
                } else {
                    Button(option.1) {}.disabled(true)
                }
            }
        } label: {
            MacSettingsPopUpFace(text: face ?? options.first { $0.0 == selection }?.1 ?? other ?? "")
                .opacity(enabled ? 1 : Theme.disabledOpacity)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label)
        .accessibilityValue(options.first { $0.0 == selection }?.1 ?? other ?? "")
    }
}

/// A pop-up button's face, for a menu built by hand.
struct MacSettingsPopUpFace: View {
    let text: String
    var body: some View {
        HStack(spacing: MacMetric.pt(6)) {
            Text(text).font(MacMetric.font(13, .medium)).foregroundStyle(Theme.text)
                .fixedSize()
            Image(systemName: "chevron.up.chevron.down").font(MacMetric.font(9, .semibold)).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, MacMetric.pt(12))
        .frame(minHeight: MacMetric.pt(MacSettingsMetric.control))
        .background(Theme.card, in: RoundedRectangle(cornerRadius: MacMetric.pt(5), style: .continuous))
        .contentShape(Rectangle())
    }
}

/// The page's buttons at macOS's sizes (the import page's): the primary one in the accent, the others on
/// `Theme.card`, a destructive one in the danger red.
struct MacSettingsButtonStyle: ButtonStyle {
    enum Kind { case primary, plain, destructive }
    var kind: Kind = .plain
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacMetric.font(13, kind == .primary ? .semibold : .medium))
            .foregroundStyle(kind == .primary ? Theme.onSelection : kind == .destructive ? Theme.danger : Theme.text)
            .padding(.horizontal, MacMetric.pt(10))
            .frame(minHeight: MacMetric.pt(MacSettingsMetric.control))
            .background(kind == .primary ? Theme.accent : Theme.card,
                        in: RoundedRectangle(cornerRadius: MacMetric.pt(5), style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : Theme.disabledOpacity)
            .fixedSize()
            .contentShape(Rectangle())
    }
}

/// A text field on the card colour, at a small control's height.
struct MacSettingsField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat? = nil
    var onCommit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(MacMetric.font(13)).textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { onCommit() }
            .onChange(of: focused) { _, now in if !now { onCommit() } }
            .padding(.horizontal, MacMetric.pt(6))
            .frame(width: width.map { MacMetric.pt($0) }, height: MacMetric.pt(MacSettingsMetric.control))
            .background(Theme.card, in: RoundedRectangle(cornerRadius: MacMetric.pt(5), style: .continuous))
    }
}

/// The same hit area and selection colour for every small set of choices in Settings.
struct MacSettingsSegments<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: MacMetric.pt(3)) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button { selection = option.0 } label: {
                    Text(option.1).font(MacMetric.font(13, .medium)).fixedSize()
                        .foregroundStyle(selection == option.0 ? Theme.onSelection : Theme.secondaryText)
                        .padding(.horizontal, MacMetric.pt(12))
                        .frame(minHeight: MacMetric.pt(MacSettingsMetric.control))
                        .background(selection == option.0 ? Theme.accent : .clear,
                                    in: RoundedRectangle(cornerRadius: MacMetric.pt(6)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.0 ? .isSelected : [])
            }
        }
        .padding(MacMetric.pt(3))
        .background(Theme.field, in: RoundedRectangle(cornerRadius: MacMetric.pt(9)))
        .accessibilityElement(children: .contain).accessibilityLabel(label)
    }
}
