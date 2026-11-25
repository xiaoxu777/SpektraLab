//  FilmLabBar.swift — the window bar's own parts in FilmLab's 暗房 design (the owner chose design A, 2026-11-23).
//
//  The bar reads, left to right: home and the roll's name, the column and crop or sort, the mode row in the middle,
//  then undo and redo, 复制 ▾ and 粘贴 ▾, compare, 普通 | 专业, and 导出. Two things the owner asked for by name:
//
//  - **Copy and paste are buttons you can see.** 复制 opens a panel of what can be copied, grouped 冲洗 · 二级调色 · 其他,
//    each with this picture's value; the ticks are kept, so ⌘C copies the same next time without the panel. 粘贴 opens a
//    panel that says what is held and where it goes: the chosen pictures, the whole roll, or only the ones never
//    developed yet. ⌘V and ⌥⌘V still paste at once, as before; ⇧⌘C and ⇧⌘V open the panels.
//  - **导出 is a button**: it goes to the 导出 mode, where the export is set and begun.

import SwiftUI

/// Which of the bar's panels is open. Shared so a key (⇧⌘C, ⇧⌘V) opens the same panel the button does.
@MainActor
@Observable
final class FilmLabClipboardUI {
    static let shared = FilmLabClipboardUI()
    var copyShown = false
    var pasteShown = false
}

// MARK: - the bar's buttons

/// A bar glyph with no ground: undo, redo, compare, the column.
struct FilmLabBarIcon: View {
    let symbol: String
    let help: String
    var selected = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(MacMetric.font(13.5, .medium))
                .foregroundStyle(selected ? Theme.onSelection : Theme.secondaryText)
                .frame(width: MacMetric.pt(28), height: MacMetric.pt(24))
                .background { if selected { RoundedRectangle(cornerRadius: MacMetric.pt(6), style: .continuous).fill(Theme.selection) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : Theme.disabledOpacity)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A labelled bar button on the control ground: its glyph, its word, its key, and a chevron when it opens a panel.
struct FilmLabBarLabel: View {
    let symbol: String
    let title: String
    var key: String? = nil
    var chevron = false
    var open = false

    var body: some View {
        HStack(spacing: MacMetric.pt(5)) {
            Image(systemName: symbol).font(MacMetric.font(12, .medium))
            Text(title).font(MacMetric.font(12, .medium)).fixedSize()
            if let key { Text(key).font(MacMetric.font(10.5)).foregroundStyle(Theme.dim).fixedSize() }
            if chevron { Image(systemName: "chevron.down").font(MacMetric.font(8.5, .bold)).foregroundStyle(Theme.dim) }
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, MacMetric.pt(9))
        .frame(height: MacMetric.pt(24))
        .background(Theme.card, in: RoundedRectangle(cornerRadius: MacMetric.pt(6), style: .continuous))
        .overlay {
            if open { RoundedRectangle(cornerRadius: MacMetric.pt(6), style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5) }
        }
        .contentShape(Rectangle())
    }
}

/// 导出: the accent capsule at the bar's end. Goes to the 导出 mode.
struct FilmLabExportButton: View {
    let action: () -> Void
    var enabled = true

    var body: some View {
        Button(action: action) {
            HStack(spacing: MacMetric.pt(5)) {
                Image(systemName: "square.and.arrow.up").font(MacMetric.font(12, .semibold))
                Text(L("Export")).font(MacMetric.font(12, .semibold)).fixedSize()
            }
            .foregroundStyle(Theme.onSelection)
            .padding(.horizontal, MacMetric.pt(11))
            .frame(height: MacMetric.pt(24))
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: MacMetric.pt(6), style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : Theme.disabledOpacity)
        .help(L("Go to Export"))
        .accessibilityIdentifier("filmlab.bar.export")
    }
}

/// The roll in front, by name, after the house.
struct FilmLabRollName: View {
    let store: any MacLibraryData

    var body: some View {
        if let name = store.selectedSource?.name, !name.isEmpty {
            Text(name)
                .font(MacMetric.font(12.5, .medium))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: MacMetric.pt(160), alignment: .leading)
                .layoutPriority(-1)   // the first to give way when the bar is narrow
                .help(name)
        }
    }
}

// MARK: - 复制

/// 复制 ▾ and its panel. `frameID` is the picture copied from: the open one in 冲洗, the first chosen in 图库.
struct FilmLabCopyButton: View {
    let frameID: LibraryFrame.ID?
    @Environment(AppServices.self) private var model

    var body: some View {
        @Bindable var ui = FilmLabClipboardUI.shared
        Button { ui.copyShown = true } label: {
            FilmLabBarLabel(symbol: "doc.on.doc", title: L("Copy"), chevron: true, open: ui.copyShown)
        }
        .buttonStyle(.plain)
        .disabled(frameID == nil)
        .opacity(frameID == nil ? Theme.disabledOpacity : 1)
        .help(L("Copy settings (⌘C); choose which (⇧⌘C)"))
        .accessibilityIdentifier("filmlab.bar.copy")
        .onAppear { FilmLabCheckArgs.openPanel(); FilmLabResizeProbe.startIfAsked() }
        .popover(isPresented: $ui.copyShown, arrowEdge: .bottom) {
            if let frameID {
                // A popover is a presentation of its own: the app's objects are handed on again (as the covers do).
                FilmLabCopyPanel(frameID: frameID) { ui.copyShown = false }
                    .interfaceScaled(.macPoints)
                    .appEnvironment(model)
                    .appColorScheme()
            }
        }
    }
}

/// What can be copied, grouped as the modes are, each with this picture's value. The ticks are kept (`remember`).
struct FilmLabCopyPanel: View {
    let frameID: LibraryFrame.ID
    let close: () -> Void
    @Environment(AppServices.self) private var model
    @Environment(FrameCatalog.self) private var library
    @State private var picked = ClipboardGroup.remembered()

    /// The panel's three headings and the groups under each, in the order the column shows them.
    static var sections: [(String, [ClipboardGroup])] {
        let offered = Set(ClipboardGroup.offered)
        let develop: [ClipboardGroup] = [.filmAndPaper, .filmExposure, .decodeTemperature, .decodeTint, .decodeCurve,
                                         .enlarger, .preflash, .couplers, .format, .hdr]
        let grading: [ClipboardGroup] = [.light, .curve, .colour, .lens]
        let other: [ClipboardGroup] = [.filmEdgeAndDateBack, .watermark]
        return [(L("Develop"), develop), (L("Grading"), grading), (L("Other", as: "copy panel heading"), other)]
            .map { ($0.0, $0.1.filter { offered.contains($0) }) }
            .filter { !$0.1.isEmpty }
    }

    var body: some View {
        let edit = model.openSession(frameID)?.transferableSettings ?? library.frame(frameID)?.edit ?? .default
        let all = Set(Self.sections.flatMap(\.1))
        VStack(alignment: .leading, spacing: MacMetric.pt(10)) {
            HStack {
                Text(L("Copy Which Settings")).font(MacMetric.font(13.5, .bold)).foregroundStyle(Theme.text)
                Spacer()
                Button(picked.isSuperset(of: all) ? L("Select None") : L("Select All")) {
                    picked = picked.isSuperset(of: all) ? [] : all
                }
                .buttonStyle(.plain)
                .font(MacMetric.font(11.5, .medium))
                .foregroundStyle(Theme.accent)
            }
            Text(L("Next time ⌘C copies these without asking."))
                .font(MacMetric.font(11.5)).foregroundStyle(Theme.secondaryText)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: MacMetric.pt(4)) {
                    ForEach(Self.sections, id: \.0) { section in
                        Text(section.0).font(MacMetric.font(10.5, .semibold)).foregroundStyle(Theme.dim)
                            .padding(.top, MacMetric.pt(6))
                        ForEach(section.1) { group in
                            FilmLabCheckRow(title: group.title, value: group.summary(of: edit), on: picked.contains(group)) {
                                if picked.contains(group) { picked.remove(group) } else { picked.insert(group) }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: MacMetric.pt(380))
            HStack(spacing: MacMetric.pt(8)) {
                Spacer()
                Button(L("Cancel"), action: close).buttonStyle(FilmLabPanelButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(L("Copy \(picked.count) Items")) {
                    ClipboardGroup.remember(picked)
                    model.copySettings(of: frameID, groups: picked)
                    close()
                }
                .buttonStyle(FilmLabPanelButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(picked.isEmpty)
            }
        }
        .padding(MacMetric.pt(14))
        .frame(width: MacMetric.pt(320))
        .background(Theme.popover)
    }
}

/// A ticked row in a panel: the box, the name, and its value at the trailing edge.
struct FilmLabCheckRow: View {
    let title: String
    var value: String = ""
    let on: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: MacMetric.pt(8)) {
                ZStack {
                    RoundedRectangle(cornerRadius: MacMetric.pt(4), style: .continuous)
                        .fill(on ? Theme.accent : .clear)
                    RoundedRectangle(cornerRadius: MacMetric.pt(4), style: .continuous)
                        .strokeBorder(on ? Theme.accent : Theme.dim, lineWidth: 1.5)
                    if on { Image(systemName: "checkmark").font(MacMetric.font(8.5, .heavy)).foregroundStyle(Theme.onSelection) }
                }
                .frame(width: MacMetric.pt(14), height: MacMetric.pt(14))
                Text(title).font(MacMetric.font(12)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: MacMetric.pt(8))
                Text(value).font(MacMetric.font(11)).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.tail)
            }
            .padding(.vertical, MacMetric.pt(3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A panel's Cancel and its primary button (the accent).
struct FilmLabPanelButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacMetric.font(12, primary ? .semibold : .medium))
            .foregroundStyle(primary ? Theme.onSelection : Theme.text)
            .padding(.horizontal, MacMetric.pt(11))
            .frame(height: MacMetric.pt(26))
            .background(primary ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: MacMetric.pt(6), style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : Theme.disabledOpacity)
    }
}

// MARK: - 粘贴

/// Where a paste goes.
enum FilmLabPasteTarget: Hashable { case selected, all, undeveloped }

/// 粘贴 ▾ and its panel.
struct FilmLabPasteButton: View {
    let store: any MacLibraryData
    let rows: [MacImage]
    /// The develop page in front, whose own paste (its session, its Undo) takes a paste onto the open picture alone.
    var develop: MacDevelopBar? = nil
    @Environment(FrameCatalog.self) private var library
    @Environment(AppServices.self) private var model

    var body: some View {
        @Bindable var ui = FilmLabClipboardUI.shared
        let held = library.clipboard != nil
        Button { ui.pasteShown = true } label: {
            FilmLabBarLabel(symbol: "doc.on.clipboard", title: L("Paste"), chevron: true, open: ui.pasteShown)
        }
        .buttonStyle(.plain)
        .disabled(!held)
        .opacity(held ? 1 : Theme.disabledOpacity)
        .help(held ? L("Paste settings (⌘V); choose where (⇧⌘V)") : L("Nothing is copied yet"))
        .accessibilityIdentifier("filmlab.bar.paste")
        .popover(isPresented: $ui.pasteShown, arrowEdge: .bottom) {
            FilmLabPastePanel(store: store, rows: rows, develop: develop) { ui.pasteShown = false }
                .interfaceScaled(.macPoints)
                .appEnvironment(model)
                .appColorScheme()
        }
    }
}

struct FilmLabPastePanel: View {
    let store: any MacLibraryData
    let rows: [MacImage]
    var develop: MacDevelopBar?
    let close: () -> Void
    @Environment(AppServices.self) private var model
    @Environment(FrameCatalog.self) private var library
    @State private var target: FilmLabPasteTarget = .selected

    private var browser: MacLibraryBrowser { .shared }

    /// The chosen pictures; in 冲洗 with nothing else chosen, the open one.
    private var chosen: [MacImage] {
        let picked = rows.filter { browser.selection.contains($0.id) }
        if picked.isEmpty, let id = develop?.frameID { return rows.filter { $0.develop?.frameID == id } }
        return picked
    }

    /// Never opened in 冲洗: no frame yet, or a frame whose picture was never developed (the owner, 2026-11-23).
    private var undeveloped: [MacImage] {
        rows.filter { row in
            guard let id = row.develop?.frameID, let frame = library.frame(id) else { return true }
            return frame.developed == nil
        }
    }

    private func pictures(_ t: FilmLabPasteTarget) -> [MacImage] {
        switch t {
        case .selected: chosen
        case .all: rows
        case .undeveloped: undeveloped
        }
    }

    var body: some View {
        let clip = library.clipboard
        VStack(alignment: .leading, spacing: MacMetric.pt(10)) {
            Text(L("Paste Settings")).font(MacMetric.font(13.5, .bold)).foregroundStyle(Theme.text)
            if let clip {
                Text(L("Copied from \(clip.sourceName):")).font(MacMetric.font(11.5)).foregroundStyle(Theme.secondaryText)
                FlowChips(words: Self.order(clip.groups).map { $0.title })
            }
            Text(L("Paste onto")).font(MacMetric.font(11, .semibold)).foregroundStyle(Theme.dim).padding(.top, MacMetric.pt(4))
            VStack(spacing: MacMetric.pt(2)) {
                targetRow(.selected, L("The \(chosen.count) chosen pictures"), key: "⌘V")
                targetRow(.all, L("All \(rows.count) pictures in this roll"), key: "⌥⌘V")
                targetRow(.undeveloped, L("Only the \(undeveloped.count) not developed yet"), key: nil)
            }
            HStack(spacing: MacMetric.pt(8)) {
                Text(L("Each picture can be undone on its own page"))
                    .font(MacMetric.font(10.5)).foregroundStyle(Theme.dim).lineLimit(2)
                Spacer(minLength: MacMetric.pt(6))
                Button(L("Cancel"), action: close).buttonStyle(FilmLabPanelButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(L("Paste onto \(pictures(target).count)")) { paste() }
                    .buttonStyle(FilmLabPanelButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(clip == nil || pictures(target).isEmpty)
            }
        }
        .padding(MacMetric.pt(14))
        .frame(width: MacMetric.pt(340))
        .background(Theme.popover)
        // Nothing chosen to paste onto: the whole roll is the likelier wish.
        .onAppear { if chosen.isEmpty { target = .all } }
    }

    private func targetRow(_ t: FilmLabPasteTarget, _ title: String, key: String?) -> some View {
        let on = target == t
        let count = pictures(t).count
        return Button { target = t } label: {
            HStack(spacing: MacMetric.pt(8)) {
                ZStack {
                    Circle().strokeBorder(on ? Theme.accent : Theme.dim, lineWidth: 1.5)
                    if on { Circle().fill(Theme.accent).padding(MacMetric.pt(3.5)) }
                }
                .frame(width: MacMetric.pt(14), height: MacMetric.pt(14))
                Text(title).font(MacMetric.font(12)).foregroundStyle(Theme.text)
                Spacer()
                if let key { Text(key).font(Theme.Font.mono(10.5 / MacMetric.scale)).foregroundStyle(Theme.dim) }
            }
            .padding(.horizontal, MacMetric.pt(8))
            .padding(.vertical, MacMetric.pt(7))
            .background { if on { RoundedRectangle(cornerRadius: MacMetric.pt(7), style: .continuous).fill(Theme.card) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? Theme.disabledOpacity : 1)
    }

    private func paste() {
        let onto = pictures(target)
        close()
        // The open picture alone in 冲洗: the page's own paste, with its Undo.
        if target == .selected, let dev = develop, onto.allSatisfy({ $0.develop?.frameID == dev.frameID }) {
            dev.paste()
            return
        }
        MacLibraryActions.shared.pasteSettings(onto: onto, store: store, model: model)
    }

    /// The held groups in the copy panel's order.
    static func order(_ groups: Set<ClipboardGroup>) -> [ClipboardGroup] {
        let ordered = FilmLabCopyPanel.sections.flatMap(\.1)
        return ordered.filter { groups.contains($0) } + groups.filter { !ordered.contains($0) }.sorted { $0.rawValue < $1.rawValue }
    }
}

/// Words as small chips that wrap onto as many lines as they need.
struct FlowChips: View {
    let words: [String]

    var body: some View {
        FlowLayout(spacing: MacMetric.pt(4)) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                Text(w).font(MacMetric.font(11)).foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, MacMetric.pt(8)).frame(height: MacMetric.pt(20))
                    .background(Theme.card, in: Capsule())
            }
        }
    }
}

/// Left to right, wrapping at the proposed width.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > b.minX, x + size.width > b.maxX { x = b.minX; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

// MARK: - a check's launch

/// What a check's launch asks for, so `--capture-window` can draw a mode or a panel without a hand on the window:
/// `--filmlab-mode grade|personalize|export` opens the develop page on that mode (with `--develop`), `--filmlab-panel copy|paste`
/// opens that panel a moment after launch. Nothing is changed in the library or the settings. For the export's
/// animation: `--filmlab-export-folder <path>` exports into that folder for this run (the kept folder, the kept recipe
/// and the 已导出 log are left alone) and `--filmlab-export-go SECONDS` presses 导出 after that long.
@MainActor
enum FilmLabCheckArgs {
    static func value(_ name: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func applyMode() {
        switch value("--filmlab-mode") {
        case "grade": MacDevelopWanted.surface = .edit
        case "export": MacDevelopWanted.surface = .develop; MacDevelopWanted.step = .format; FilmLabFinish.shared.page = .export
        case "personalize": MacDevelopWanted.surface = .develop; MacDevelopWanted.step = .format; FilmLabFinish.shared.page = .personalize
        default: break
        }
    }

    /// `--filmlab-export-go` has pressed 导出 once this launch (`FilmLabExportFooter`).
    static var exportWent = false

    /// A page asked for, for `--capture-window` (design A round 7): `--filmlab-show lighttable` opens the Light Table as it
    /// stands (nothing is put on it), `--filmlab-show import --filmlab-show-path <folder>` opens the import page with that
    /// folder picked, as Finder's panel would hand it over. Nothing is imported: that takes the page's own Import button.
    static func showPage(model: AppServices) {
        guard let page = value("--filmlab-show") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            switch page {
            case "lighttable":
                model.router.toLibrary()
                model.router.open(.lightTable)
            case "import":
                guard let path = value("--filmlab-show-path") else { return }
                MacLibraryBrowser.shared.finderPicks = [URL(fileURLWithPath: path, isDirectory: true)]
                MacLibraryBrowser.shared.importAsked = true
            default: break
            }
        }
    }

    /// The panel asked for, opened once the bar is up.
    static func openPanel() {
        guard let panel = value("--filmlab-panel") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if panel == "copy" { FilmLabClipboardUI.shared.copyShown = true }
            if panel == "paste" { FilmLabClipboardUI.shared.pasteShown = true }
        }
    }
}

/// A check's launch only (`--filmlab-panel-inline copy|paste`): the panel drawn in the window itself, top right, since a
/// popover is a window of its own that `--capture-window` cannot draw.
struct FilmLabCheckOverlay: View {
    let store: any MacLibraryData
    let rows: [MacImage]
    var develop: MacDevelopBar?

    var body: some View {
        switch FilmLabCheckArgs.value("--filmlab-panel-inline") {
        case "copy":
            if let id = develop?.frameID {
                FilmLabCopyPanel(frameID: id) {}.clipShape(RoundedRectangle(cornerRadius: 10)).padding(.top, 44).padding(.trailing, 260)
            }
        case "paste":
            FilmLabPastePanel(store: store, rows: rows, develop: develop) {}.clipShape(RoundedRectangle(cornerRadius: 10)).padding(.top, 44).padding(.trailing, 160)
        default:
            EmptyView()
        }
    }
}

// MARK: - the toast

/// What the library's acts just did (`MacLibraryActions.notice`: "Settings pasted onto 4 pictures."), said over the
/// picture while the develop page is in front, where the library's sidebar line cannot be seen (design A). It goes
/// when the notice does (8 s after a paste lands).
struct FilmLabToast: View {
    var body: some View {
        VStack { toast }
            .animation(.easeOut(duration: 0.2), value: MacLibraryActions.shared.notice)
    }

    @ViewBuilder private var toast: some View {
        if let notice = MacLibraryActions.shared.notice {
            HStack(spacing: MacMetric.pt(8)) {
                Image(systemName: notice.said.hasSuffix("…") ? "hourglass" : "checkmark.circle.fill")
                    .font(MacMetric.font(13, .semibold))
                    .foregroundStyle(notice.said.hasSuffix("…") ? Theme.secondaryText : Theme.labelGreen)
                Text(L(shown: notice.line)).font(MacMetric.font(12.5)).foregroundStyle(Theme.text)
                    .lineLimit(2)
            }
            .padding(.horizontal, MacMetric.pt(14))
            .padding(.vertical, MacMetric.pt(9))
            .background(Theme.popover, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .frame(maxWidth: MacMetric.pt(520))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
