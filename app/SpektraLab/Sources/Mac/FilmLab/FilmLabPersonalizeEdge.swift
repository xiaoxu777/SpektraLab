//  FilmLabPersonalizeEdge.swift — 个性化's 片边: the switch, and the film formats as pictures of this photo.
//
//  The choice is seen, not read: each card is this picture laid in that format's film (`FilmCanvasView`, as the Film
//  Edge flow's cards draw it, larger), three across. 普通版 offers the everyday formats; 专业版 every format behind the
//  flow's filter, then the view, 调整取景 and the five edge tools (`EdgeStepPanel(flat:)`). The film's own 尺寸
//  (`FilmSizeSection`: the size the film is developed as while no edge is on) follows the section in the column.
//
//  The acts are `FilmEdgeColumn`'s, through the session: the switch (the first time on, the film lies the way the
//  picture does, shot through this Mac's body), and a format's card (the gate lies the way the picture does, the cut
//  starts again, a date face the format cannot print gives way to one it can).

import SwiftUI

struct FilmLabEdgeSection: View {
    let session: OpenFrameSession
    let frame: LibraryFrame
    let width: CGFloat

    @Environment(AppServices.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @AppStorage("filmlab.personalize.edge.more") private var moreShown = false

    private var edge: FilmEdgeSettings { session.edit.filmEdge }
    private var appliesFilm: Bool { session.edit.appliesFilm }
    private var pro: Bool { !FeatureFlags.simpleWindow }

    /// 普通版's cards: the formats most people mean by a film edge. The chosen one is always among them.
    private static let everyday: [FilmEdgeFormat] = [.f135, .f6x6, .f645, .f6x7, .xpan, .sprocket135]

    private var filter: FilmEdgeFormat.Filter {
        let kept = DevelopPanelPrefs.shared.filmEdgeFilter
        return FilmEdgeFormat.Filter.offered().contains(kept) ? kept : .all
    }

    private var cards: [FilmEdgeFormat] {
        if pro { return filter.formats() }
        var list = Self.everyday.filter(FilmEdgeFormat.offered.contains)
        if !list.contains(edge.format) { list.append(edge.format) }
        return list
    }

    private var pictureAspect: Double {
        let a = frame.originalSize.aspect
        return session.edit.geometry.quarterTurns % 2 == 0 ? a : 1 / max(a, 0.0001)
    }

    var body: some View {
        FilmLabPersonalizeSection(title: L("Film Edge"), symbol: "film",
                                  value: edge.format.label + Fmt.dot + edge.view.label,
                                  isOn: Binding(get: { edge.active && appliesFilm }, set: { setFilmEdge($0) }),
                                  enabled: appliesFilm, id: "film-edge") {
            VStack(alignment: .leading, spacing: 12) {
                if pro {
                    SegmentedSwitch(options: FilmEdgeFormat.Filter.offered(),
                                    selection: Binding(get: { filter }, set: { f in
                                        withAnimation(.easeOut(duration: 0.18)) { DevelopPanelPrefs.shared.filmEdgeFilter = f }
                                    }),
                                    title: \.label, track: Theme.card, size: 12)
                        .accessibilityLabel(L("Film Format Filter"))
                        .accessibilityIdentifier("filmlab.personalize.edge.filter")
                    if !cards.contains(edge.format) {
                        Text(L("Chosen: \(edge.format.label)")).font(Theme.Font.ui(11.5, .medium)).foregroundStyle(Theme.dim)
                    }
                }
                styleGrid
                HStack(spacing: 10) {
                    FilmLabPersonalizeLabel(L("View"))
                    // Greyed where the format draws one view whatever is kept (135 Full Width: Strip).
                    let open = FilmEdgeOptions.view(edge)
                    SegmentedSwitch(options: FilmEdgeView.allCases,
                                    selection: Binding(get: { edge.view },
                                                       set: { v in if open, v != edge.view { session.change { $0.filmEdge.mode = v } } }),
                                    title: \.label, segmentWidth: 84, track: Theme.card)
                        .rowEnabled(open)
                        .accessibilityIdentifier("filmlab.personalize.edge.view")
                }
                if pro { more }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: the formats

    private var styleGrid: some View {
        let gap: CGFloat = 8
        let side = floor((width - 32 - gap * 2) / 3)
        return ChipFlow(spacing: gap, lineSpacing: gap) {
            ForEach(cards) { format in card(format, width: side) }
        }
        .frame(width: side * 3 + gap * 2, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmlab.personalize.edge.styles")
    }

    /// The edit as one format's card shows it: that format, lying the way the picture does, its largest cut, no date.
    private func variant(_ format: FilmEdgeFormat) -> FrameEdit {
        var e = session.edit
        if format != e.filmEdge.format {
            e.filmEdge.take(format: format, stockID: e.params.filmStock)
            e.filmEdge.turn = format.defaultTurn(pictureAspect: pictureAspect)
            e.filmEdge.framing = nil
        }
        e.dateBack.active = false
        return e
    }

    private func card(_ format: FilmEdgeFormat, width side: CGFloat) -> some View {
        let on = format == edge.format
        let stock = StockCatalog.shared.stock(session.edit.params.filmStock)
        let made = stock?.isMade(in: format) ?? true
        let edit = variant(format)
        let box = CGSize(width: side - 12, height: 66)
        return Button { pick(format) } label: {
            VStack(spacing: 6) {
                ZStack {
                    if let film = model.filmEdge(for: frame, edit: edit, forcing: true) {
                        let a = max(0.05, CGFloat(film.geometry.canvas.aspect))
                        let fit = box.width / box.height > a ? CGSize(width: box.height * a, height: box.height)
                                                             : CGSize(width: box.width, height: box.width / a)
                        FilmCanvasView(geometry: film.geometry, style: .developed, picture: frame.picture,
                                       sourceSize: CGSize(width: frame.originalSize.width, height: frame.originalSize.height),
                                       framing: film.framing, pointSize: max(fit.width, fit.height),
                                       ink: EdgeLook.of(edit.params.filmStock).ink(on: format))
                            .frame(width: fit.width, height: fit.height)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    }
                }
                .frame(width: box.width, height: box.height)
                VStack(spacing: 1) {
                    Text(format.cardTitle).font(Theme.Font.ui(12.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(format.cardDetail).font(Theme.Font.ui(10.5)).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            .padding(.top, 8).padding(.bottom, 7)
            .frame(width: side)
            .background(on ? Theme.card : Theme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                if on { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.selectionFrame, lineWidth: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        // A format this stock was never made in is shown, and cannot be chosen.
        .rowEnabled(made)
        .help(made ? format.label : format.label + L(", not made in this film"))
        .accessibilityLabel(format.label + ", " + format.aspectText + (made ? "" : L(", not made in this film")))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("filmlab.personalize.edge.style." + format.rawValue)
    }

    // MARK: 专业版: framing, the tools, the size

    private var more: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { withAnimation(.easeOut(duration: 0.18)) { moreShown.toggle() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right").font(Theme.Font.ui(9.5, .bold))
                            .rotationEffect(.degrees(moreShown ? 90 : 0))
                        Text(L("Edge Details")).font(Theme.Font.ui(12.5, .medium))
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("filmlab.personalize.edge.more")
                Spacer(minLength: 0)
                Button { router.show(.crop(frame.id)) } label: {
                    Label(L("Adjust Framing"), systemImage: "crop").font(Theme.Font.ui(12.5, .medium)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("filmlab.personalize.edge.framing")
            }
            if moreShown {
                VStack(spacing: 0) {
                    EdgeStepPanel(film: model.filmEdge(for: frame, edit: session.edit, forcing: true),
                                  draft: FilmLabEdgeDraft.binding(session), tool: .constant(.gate), width: width,
                                  editing: { down in if down { session.began(.shoot) } else { session.ended() } },
                                  changed: {}, flat: true)
                }
                // The panels are drawn to the column's width, their own margins inside it.
                .padding(.horizontal, -16)
                .padding(.top, 6)
            }
        }
    }

    // MARK: acts

    private func setFilmEdge(_ on: Bool) {
        guard on != edge.active else { return }
        let aspect = pictureAspect, body = settings.bodySeed
        withAnimation(.easeOut(duration: 0.18)) {
            session.change { e in
                if on, e.filmEdge.cameraSeed == 0 {
                    e.filmEdge.turn = e.filmEdge.format.defaultTurn(pictureAspect: aspect)
                    e.filmEdge.cameraSeed = body
                    if e.filmEdge.format.is120 { e.filmEdge.perforation = FilmEdgePerforation.starting(stockID: e.params.filmStock) }
                }
                e.filmEdge.active = on
            }
        }
    }

    private func pick(_ format: FilmEdgeFormat) {
        guard format != edge.format else { return }
        let aspect = pictureAspect
        withAnimation(.easeOut(duration: 0.18)) {
            session.change { e in
                let wasHalfTurned = e.filmEdge.turn >= 2
                e.filmEdge.take(format: format, stockID: e.params.filmStock)
                e.filmEdge.turn = format.defaultTurn(pictureAspect: aspect) + (wasHalfTurned ? 2 : 0)
                e.filmEdge.framing = nil
                if !format.draws(e.dateBack.style), let face = DateBackFace.offered.first(where: format.draws) {
                    e.dateBack.style = face
                }
            }
        }
    }
}
