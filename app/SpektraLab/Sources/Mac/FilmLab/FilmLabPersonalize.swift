//  FilmLabPersonalize.swift — FilmLab's 个性化 mode: the film edge, the date back and the watermark, before 导出.
//
//  The owner, 2026-11-25: "把片边和日期后背加到导出前面吧，命名为个性化之类的意思，导出界面只做导出，个性化界面还可以编辑水印".
//  The mode row reads 图库 · 冲洗 · 二级调色 · 个性化 · 导出. 个性化 and 导出 are both the develop page on its Format step —
//  the one place the picture is shown as it leaves the app, with its edge, its date and its watermarks — and which of
//  the two the column is is `FilmLabFinish.page`, so `DevelopStep` and everything that reads it stay as they were.
//
//  The column (`FilmLabPersonalizeColumn`) is three sections, each a name with a switch and, when on, its choices as
//  pictures (the owner, of the old export presets: "用户不会去看这些小方块。视觉上就要对"):
//  - **片边** (`FilmLabEdgeSection`): this photo drawn in each film format, three across; 专业版 adds the filter, the edge
//    tools and 调整取景. 底片画幅 belongs with 颗粒·光晕 in the grading column (`FilmLabGradeTabs`).
//  - **日期后背**: the faces as cards, the corner, the size and the brightness (`DateStepPanel(flat:)`).
//  - **水印** (`FilmLabMarkSection`): the library's marks as tiles, a mark made from typed text, where it sits, how big.
//  Under them, when the export will take more than this picture, one row puts all three onto the others.
//
//  Every control is an edit of the frame's session, as the panels were in 导出's column before: Undo walks them.

import SwiftUI

/// Which of the two pages on the develop page's Format step is in front: 个性化 or 导出.
@MainActor
@Observable
final class FilmLabFinish {
    static let shared = FilmLabFinish()
    enum Page: String { case personalize, export }
    var page: Page = .export
}

/// 个性化's column: 片边, 日期后背, 水印, and the row that puts them onto the rest of the batch.
struct FilmLabPersonalizeColumn: View {
    let session: OpenFrameSession
    let frame: LibraryFrame
    /// The pictures the export will take (`DevelopWorkspace.exportIDs`).
    let ids: [LibraryFrame.ID]
    /// A pair's or a double's own panel, drawn first (专业版): their film edge and date are theirs.
    var piece: AnyView? = nil

    @Environment(AppServices.self) private var model
    @State private var width: CGFloat = 378
    @State private var checkScrollRoom: CGFloat = 0

    private var single: Bool { frame.pair == nil && session.pair == nil }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroll in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        if let piece { piece }
                        if single {
                            if FeatureFlags.filmEdge { FilmLabEdgeSection(session: session, frame: frame, width: width) }
                            if FeatureFlags.dateBack { FilmLabDateSection(session: session, frame: frame, width: width) }
                        }
                        if session.takesWatermarks { FilmLabMarkSection(session: session, frame: frame, width: width) }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.bottom, FilmLabPersonalizeCheck.scrollTarget == nil ? 12 : max(12, checkScrollRoom))
                }
                .scrollIndicators(.hidden)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { if FilmLabPersonalizeCheck.scrollTarget != nil { checkScrollRoom = $0 } }
                .task(id: frame.id) {
                    guard let target = FilmLabPersonalizeCheck.scrollTarget,
                          await FilmLabPersonalizeCheck.settle(session, frameID: frame.id) else { return }
                    // Edge edits can change the heights above the requested section; let that layout finish too.
                    guard await FilmLabPersonalizeCheck.settle(session, frameID: frame.id),
                          FilmLabPersonalizeCheck.consume(.scroll) else { return }
                    scroll.scrollTo(target, anchor: .top)
                }
            }
            FilmLabPersonalizeBatchRow(session: session, frame: frame, ids: ids)
        }
        // The cards are drawn to a width: the column's.
        .onGeometryChange(for: CGFloat.self) { ($0.size.width / 2).rounded() * 2 } action: { width = max(280, $0) }
        .accessibilityIdentifier("filmlab.personalize")
    }
}

/// A section of 个性化: its glyph, its name, what it is set to, and its switch; its choices under it while on.
struct FilmLabPersonalizeSection<Content: View>: View {
    let title: String
    let symbol: String
    /// What it is set to, under the name ("135 · 整条"); nil while off.
    var value: String? = nil
    @Binding var isOn: Bool
    var enabled = true
    let id: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(Theme.Font.ui(14, .medium))
                    .foregroundStyle(isOn ? Theme.accent : Theme.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.Font.ui(15, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(isOn ? (value ?? L("On")) : L("Off"))
                        .font(Theme.Font.ui(11.5)).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 8)
                SpkToggle(isOn: $isOn, size: .regular)
                    .scaleEffect(0.8, anchor: .trailing)
                    .rowEnabled(enabled)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("filmlab.personalize." + id)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .contentShape(Rectangle())
            if isOn || FilmLabPersonalizeCheck.expands(id) {
                content()
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .id(id)
    }
}

/// A small heading over a group of choices inside a section.
struct FilmLabPersonalizeLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.Font.ui(11.5, .semibold)).foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 日期后背

/// 日期后背: the switch, then the faces as cards, the corner, the size and the brightness.
struct FilmLabDateSection: View {
    let session: OpenFrameSession
    let frame: LibraryFrame
    let width: CGFloat

    private var edge: FilmEdgeSettings { session.edit.filmEdge }
    private var back: DateBackSettings { session.edit.dateBack }
    private var appliesFilm: Bool { session.edit.appliesFilm }
    private var printsNothing: Bool { FilmEdgeOptions.printsNothing(back, edge) }

    var body: some View {
        FilmLabPersonalizeSection(title: L("Date Back"), symbol: "calendar",
                                  value: back.style.label,
                                  isOn: Binding(get: { back.active && !printsNothing && appliesFilm }, set: { setDate($0) }),
                                  enabled: appliesFilm && !printsNothing, id: "date-back") {
            DateStepPanel(frame: frame, draft: FilmLabEdgeDraft.binding(session), control: .constant(.corner), width: width,
                          editing: { down in if down { session.began(.shoot) } else { session.ended() } }, changed: {},
                          pick: pickFace, flat: true)
        }
    }

    /// The date's switch (as `FilmEdgeColumn`'s): switched on with a face this camera cannot print, it takes one it can.
    private func setDate(_ on: Bool) {
        guard on != back.active else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            session.change { e in
                e.dateBack.active = on
                if on, !e.dateBack.prints(e.dateBack.style, filmEdge: e.filmEdge),
                   let face = DateBackFace.offered.first(where: { e.dateBack.prints($0, filmEdge: e.filmEdge) }) {
                    e.dateBack.style = face
                }
            }
        }
    }

    private func pickFace(_ face: DateBackFace) {
        var b = back
        b.tap(face)
        guard b != back else { return }
        session.change { $0.dateBack = b }
    }
}

/// The film edge panels' `draft`, as the frame itself: what they set is one film-side edit through the session — the
/// film edge, the date and the advance's seed, nothing else (`FilmEdgeColumn.draft`).
@MainActor
enum FilmLabEdgeDraft {
    static func binding(_ session: OpenFrameSession) -> Binding<FrameEdit> {
        Binding(get: { session.edit }, set: { new in
            let (e, d, seed) = (new.filmEdge, new.dateBack, new.frameSeed)
            guard e != session.edit.filmEdge || d != session.edit.dateBack || seed != session.edit.frameSeed else { return }
            session.change { $0.filmEdge = e; $0.dateBack = d; $0.frameSeed = seed }
        })
    }
}

// MARK: - onto the rest of the batch

/// At the column's foot while the export will take more than this picture: this picture's film edge, date back and
/// watermarks onto the others, in one go (each is a picture's own setting, so without it a batch exports each with its
/// own). Pasted as a paste is: one step of history on each picture.
struct FilmLabPersonalizeBatchRow: View {
    let session: OpenFrameSession
    let frame: LibraryFrame
    let ids: [LibraryFrame.ID]
    @Environment(AppServices.self) private var model
    @State private var done = false

    var body: some View {
        let others = ids.filter { $0 != frame.id }
        if !others.isEmpty {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Use these on all \(ids.count) pictures"))
                        .font(Theme.Font.ui(12.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.85)
                    Text(done ? L("Done. Each picture has its own Undo.") : L("Otherwise each picture keeps its own."))
                        .font(Theme.Font.note).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Button(done ? L("Applied") : L("Apply")) { apply(others) }
                    .buttonStyle(FilmLabPanelButtonStyle(primary: !done))
                    .disabled(done)
                    .accessibilityIdentifier("filmlab.personalize.to-all")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.chrome)
            .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
            // Changed again after applying: offered again.
            .onChange(of: session.edit.filmEdge) { _, _ in done = false }
            .onChange(of: session.edit.dateBack) { _, _ in done = false }
            .onChange(of: session.edit.watermarks) { _, _ in done = false }
            .onChange(of: ids) { _, _ in done = false }
        }
    }

    /// The library's own paste (its history steps, its previews developed again), with a clip of these three groups in
    /// the clipboard's place for the length of the call: what the person copied is put back at once.
    private func apply(_ others: [LibraryFrame.ID]) {
        let edit = session.edit
        var groups: Set<ClipboardGroup> = [.filmEdgeAndDateBack]
        if ClipboardGroup.offered.contains(.watermark) { groups.insert(.watermark) }
        let clip = SettingsClip(groups: groups, settings: edit, sourceName: frame.fileName,
                                sourceAspect: SettingsClip.shownAspect(frame.originalSize, quarterTurns: edit.geometry.quarterTurns))
        let store = MacLibraryUI.store(model)
        let wanted = Set(others)
        let rows = store.images.filter { $0.develop.map { wanted.contains($0.frameID) } ?? false }
        guard !rows.isEmpty else { return }
        let held = model.library.clipboard
        model.library.clipboard = clip
        MacLibraryActions.shared.pasteSettings(onto: rows, store: store, model: model)
        model.library.clipboard = held
        done = true
    }
}
