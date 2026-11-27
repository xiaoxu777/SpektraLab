//  FilmLabPersonalizeEdge.swift — 个性化's 片边: the switch, and the film formats as pictures of this photo.
//
//  The choice is seen, not read: each card is this picture laid in that format's film (`FilmCanvasView`, as the Film
//  Edge flow's cards draw it, larger), three across, named as a person who never shot film would name it ("6×6 方画幅",
//  "正方形": `FilmEdgeFormat.everydayName` / `everydayShape`). 普通版 offers the everyday formats; 专业版 every format
//  behind the filter, then 更多细节 (the five edge tools, `EdgeStepPanel(flat:)`). Both offer 方向 and 调整画面位置. The film's own 尺寸
//  (`FilmSizeSection`: the size the film is developed as while no edge is on) follows the section in the column.
//
//  **换一台相机** (the owner, 2026-11-25: "片边的换一台相机的功能怎么没了，记得加上去，同时写的通俗易懂一点"): the camera
//  body's seed (`filmEdge.cameraSeed`, the Body tool's 换一台) — the same kind of camera, another one of them, whose
//  frame corners, margins and holes fall a little differently. It was in the column flat before 个性化 folded the tools
//  away; it is a row of its own now, in both versions, under the cards.
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
    private static let everyday: [FilmEdgeFormat] = [.f135, .half, .f6x6, .f645, .f6x7, .xpan]
    @State private var diceTurns = 0.0

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
                                  value: edge.format.everydayName + Fmt.dot + edge.view.everydayLabel,
                                  isOn: Binding(get: { edge.active && appliesFilm }, set: { setFilmEdge($0) }),
                                  enabled: appliesFilm, id: "film-edge") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    FilmLabPersonalizeLabel(L("Camera"))
                    Text(L("Each kind of camera leaves a different frame and border on the film."))
                        .font(Theme.Font.ui(11.5)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if pro {
                    SegmentedSwitch(options: FilmEdgeFormat.Filter.offered(),
                                    selection: Binding(get: { filter }, set: { f in
                                        withAnimation(.easeOut(duration: 0.18)) { DevelopPanelPrefs.shared.filmEdgeFilter = f }
                                    }),
                                    title: { $0.everydayLabel }, track: Theme.card, size: 12)
                        .accessibilityLabel(L("Film Format Filter"))
                        .accessibilityIdentifier("filmlab.personalize.edge.filter")
                    if !cards.contains(edge.format) {
                        Text(L("Chosen: \(edge.format.everydayName)")).font(Theme.Font.ui(11.5, .medium)).foregroundStyle(Theme.dim)
                    }
                }
                styleGrid
                direction
                anotherCamera
                HStack(spacing: 10) {
                    FilmLabPersonalizeLabel(L("Show"))
                    // Greyed where the format draws one view whatever is kept (135 Full Width: Strip).
                    let open = FilmEdgeOptions.view(edge)
                    SegmentedSwitch(options: FilmEdgeView.allCases,
                                    selection: Binding(get: { edge.view },
                                                       set: { v in if open, v != edge.view { session.change { $0.filmEdge.mode = v } } }),
                                    title: { $0.everydayLabel }, segmentWidth: 96, track: Theme.card)
                        .rowEnabled(open)
                        .accessibilityIdentifier("filmlab.personalize.edge.view")
                }
                HStack(spacing: 10) {
                    FilmLabPersonalizeLabel(L("Scan look"))
                    SegmentedSwitch(options: FilmEdgeScan.allCases,
                                    selection: Binding(get: { edge.scanLook }, set: { choice in
                                        session.change { $0.filmEdge.chooseScan(choice) }
                                    }),
                                    title: { $0.title }, segmentWidth: 72, height: 34, track: Theme.card, size: 13)
                        .accessibilityIdentifier("filmlab.personalize.edge.scan")
                }
                more
            }
            .padding(.horizontal, 16)
        }
        .task(id: frame.id) { await FilmLabPersonalizeCheck.applyEdge(session, frame: frame, body: settings.bodySeed) }
    }

    // MARK: 换一台相机

    /// The same kind of camera, another one of them: a new body seed (the Body tool's 换一台), so the frame's corners,
    /// margins and holes fall a little differently. The dice turns once a tap, so the tap is seen to have done something
    /// even where the change on the edge is a hair's.
    private var anotherCamera: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Another camera")).font(Theme.Font.ui(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(L("Same kind, another one: its border is a little different."))
                    .font(Theme.Font.ui(11.5)).foregroundStyle(Theme.dim)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            // Keep both pills at their natural width; a narrow column puts the new numbers below the camera.
            ChipFlow(spacing: 8, lineSpacing: 8) {
                anotherCameraButton
                Button(action: rollNumbers) {
                    Text(L("New numbers"))
                        .font(Theme.Font.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1).fixedSize()
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Theme.card, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .help(L("New numbers"))
                .accessibilityLabel(L("New numbers"))
                .accessibilityIdentifier("filmlab.personalize.edge.numbers")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var anotherCameraButton: some View {
        Button(action: rollBody) {
            HStack(spacing: 6) {
                EdgeToolGlyph(tool: .body, color: Theme.text).frame(width: 16, height: 16)
                    .rotationEffect(.degrees(diceTurns))
                Text(L("Camera No. \(max(edge.cameraSeed, 1))"))
                    .font(Theme.Font.ui(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1).fixedSize()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12).frame(height: 30)
            .background(Theme.card, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .help(L("Another camera"))
        .accessibilityLabel(L("Another camera"))
        .accessibilityValue(L("Camera No. \(max(edge.cameraSeed, 1))"))
        .accessibilityIdentifier("filmlab.personalize.edge.another")
    }

    private func rollBody() {
        withAnimation(.easeOut(duration: 0.35)) { diceTurns += 180 }
        withAnimation(.easeOut(duration: 0.18)) { session.change { Self.rollBody(in: &$0) } }
    }

    static func rollBody(in edit: inout FrameEdit) {
        let before = edit.filmEdge.cameraSeed
        repeat { edit.filmEdge.cameraSeed = Int.random(in: FilmEdgeSettings.bodyRange) } while edit.filmEdge.cameraSeed == before
    }

    /// The upstream advance's draw: keep the camera and any manually chosen frame number.
    private func rollNumbers() {
        withAnimation(.easeOut(duration: 0.18)) { session.change { Self.rollNumbers(in: &$0) } }
    }

    static func rollNumbers(in edit: inout FrameEdit) {
        let before = edit.frameSeed
        repeat { edit.frameSeed = Int.random(in: 1...Int(Int32.max)) } while edit.frameSeed == before
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

    /// Each format follows the explicit strip direction, or the picture's shape until a direction is chosen.
    private func variant(_ format: FilmEdgeFormat) -> FrameEdit {
        var e = session.edit
        if format != e.filmEdge.format {
            e.filmEdge.take(format: format, stockID: e.params.filmStock)
            e.filmEdge.turn = Self.turn(for: e.filmEdge, pictureAspect: pictureAspect)
            e.filmEdge.framing = nil
        }
        e.dateBack.active = false
        return e
    }

    /// Format previews and applied choices keep the same half turn, including with automatic direction.
    private static func turn(for edge: FilmEdgeSettings, pictureAspect: Double) -> Int {
        edge.orientation?.turn(keeping: edge.turn)
            ?? (edge.format.defaultTurn(pictureAspect: pictureAspect) + (edge.turn >= 2 ? 2 : 0))
    }

    private func card(_ format: FilmEdgeFormat, width side: CGFloat) -> some View {
        let on = format == edge.format
        let stock = StockCatalog.shared.stock(session.edit.params.filmStock)
        let made = stock?.isMade(in: format) ?? true
        let edit = variant(format)
        let box = CGSize(width: side - 12, height: 66)
        return Button { pick(format) } label: {
            VStack(spacing: 6) {
                picture(edit, in: box)
                VStack(spacing: 1) {
                    Text(format.everydayName).font(Theme.Font.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(format.everydayShape).font(Theme.Font.ui(10.5)).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.75)
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
        .help(made ? format.everydayName : format.everydayName + L(", not made in this film"))
        .accessibilityLabel(format.everydayName + ", " + format.everydayShape + (made ? "" : L(", not made in this film")))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("filmlab.personalize.edge.style." + format.rawValue)
    }

    /// The same photograph and framing for format cards and direction choices; fit the canvas after its host turn.
    private func picture(_ edit: FrameEdit, in box: CGSize) -> some View {
        ZStack {
            if let film = model.filmEdge(for: frame, edit: edit, forcing: true) {
                let a = max(0.05, CGFloat(film.geometry.out.aspect))
                let fit = box.width / box.height > a ? CGSize(width: box.height * a, height: box.height)
                                                     : CGSize(width: box.width, height: box.width / a)
                FilmCanvasView(geometry: film.geometry, style: .developed, picture: frame.picture,
                               sourceSize: CGSize(width: frame.originalSize.width, height: frame.originalSize.height),
                               framing: film.framing, pointSize: max(fit.width, fit.height),
                               ink: EdgeLook.of(edit.params.filmStock).ink(on: edit.filmEdge.format))
                    .frame(width: fit.width, height: fit.height)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
        }
        .frame(width: box.width, height: box.height)
    }

    // MARK: 方向

    private var direction: some View {
        let side = floor((width - 32 - 8) / 2)
        return VStack(alignment: .leading, spacing: 8) {
            FilmLabPersonalizeLabel(L("Direction"))
            if edge.format.isCine, edge.format.acrossMM > edge.format.alongMM {
                Text(L("Movie film runs top to bottom."))
                    .font(Theme.Font.ui(11.5)).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach(FilmEdgeOrientation.allCases, id: \.self) { orientation in
                    directionCard(orientation, width: side)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmlab.personalize.edge.direction")
    }

    private func directionCard(_ orientation: FilmEdgeOrientation, width side: CGFloat) -> some View {
        let on = edge.turn % 2 == (orientation == .across ? 0 : 1)
        let title = orientation == .across ? L("Across") : L("Upright")
        let edit = Self.oriented(variant(edge.format), to: orientation,
                                 source: CGSize(width: frame.originalSize.width, height: frame.originalSize.height))
        return Button {
            guard edge.orientation != orientation || edge.turn != edit.filmEdge.turn else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                session.change { $0.filmEdge = edit.filmEdge }
            }
        } label: {
            VStack(spacing: 6) {
                picture(edit, in: CGSize(width: side - 12, height: 60))
                Text(title).font(Theme.Font.ui(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
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
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("filmlab.personalize.edge.direction." + orientation.rawValue)
    }

    /// The preview and the tap use the same cut: retain a placement only while it fits the turned gate.
    static func oriented(_ edit: FrameEdit, to orientation: FilmEdgeOrientation?, source: CGSize) -> FrameEdit {
        var e = edit
        e.filmEdge.orientation = orientation
        let aspect = Double(source.width / max(source.height, 1))
        let shownAspect = e.geometry.quarterTurns % 2 == 0 ? aspect : 1 / max(aspect, 0.0001)
        e.filmEdge.turn = Self.turn(for: e.filmEdge, pictureAspect: shownAspect)
        if let kept = e.filmEdge.framing,
           !FilmFraming.fits(kept, format: e.filmEdge.format, turn: e.filmEdge.turn, source: source) {
            e.filmEdge.framing = nil
        }
        return e
    }

    // MARK: framing in both modes, the tools in 专业版

    private var detailsShown: Bool { moreShown || FilmLabPersonalizeCheck.open == .edgeDetail }

    private var more: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if pro {
                    Button { withAnimation(.easeOut(duration: 0.18)) { moreShown.toggle() } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.right").font(Theme.Font.ui(9.5, .bold))
                                .rotationEffect(.degrees(detailsShown ? 90 : 0))
                            Text(L("More details")).font(Theme.Font.ui(12.5, .medium))
                        }
                        .foregroundStyle(Theme.secondaryText)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filmlab.personalize.edge.more")
                }
                Spacer(minLength: 0)
                Button { router.show(.crop(frame.id)) } label: {
                    Label(L("Move the picture"), systemImage: "crop").font(Theme.Font.ui(12.5, .medium)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("filmlab.personalize.edge.framing")
            }
            if pro, detailsShown {
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
            session.change { Self.setFilmEdge(on, in: &$0, pictureAspect: aspect, body: body) }
        }
    }

    static func setFilmEdge(_ on: Bool, in e: inout FrameEdit, pictureAspect: Double, body: Int) {
        guard on != e.filmEdge.active else { return }
        if on, e.filmEdge.cameraSeed == 0 {
            e.filmEdge.turn = Self.turn(for: e.filmEdge, pictureAspect: pictureAspect)
            e.filmEdge.cameraSeed = body
            if e.filmEdge.format.is120 { e.filmEdge.perforation = FilmEdgePerforation.starting(stockID: e.params.filmStock) }
        }
        e.filmEdge.active = on
    }

    private func pick(_ format: FilmEdgeFormat) {
        guard format != edge.format else { return }
        let aspect = pictureAspect
        withAnimation(.easeOut(duration: 0.18)) {
            session.change { Self.pick(format, in: &$0, pictureAspect: aspect) }
        }
    }

    static func pick(_ format: FilmEdgeFormat, in e: inout FrameEdit, pictureAspect: Double) {
        guard format != e.filmEdge.format else { return }
        e.filmEdge.take(format: format, stockID: e.params.filmStock)
        e.filmEdge.turn = Self.turn(for: e.filmEdge, pictureAspect: pictureAspect)
        e.filmEdge.framing = nil
        if !format.draws(e.dateBack.style), let face = DateBackFace.offered.first(where: format.draws) {
            e.dateBack.style = face
        }
    }
}

// MARK: - in everyday words

/// 个性化's names for the formats, the filter and the view: what a person who never shot film would call them. The
/// model's own labels (`label`, `cardTitle`) stay the film edge flow's and the clipboard's.
extension FilmEdgeFormat {
    var everydayName: String {
        switch self {
        case .f135: L("35mm full frame")
        case .half: L("Half frame")
        case .f645: L("645 medium format")
        case .f6x6: L("6×6 square")
        case .f6x7: L("6×7 medium format")
        case .f6x8: L("6×8 medium format")
        case .f6x9: L("6×9 medium format")
        case .xpan: L("XPan wide")
        case .sprocket135: L("35mm full width")
        case .f6x12: L("6×12 wide")
        case .f6x17: L("6×17 wide")
        case .super8: L("Super 8 movie")
        case .cine16: L("16mm movie")
        case .cine35: L("35mm movie")
        case .cine65: L("70mm movie")
        case .cine65x15: L("70mm giant screen")
        }
    }

    /// What the frame looks like.
    var everydayShape: String {
        switch self {
        case .f135, .f6x9: L("The usual 3:2")
        case .half: L("Tall, 3:4")
        case .f645, .f6x8: L("Close to 4:3")
        case .f6x6: L("Square shape")
        case .f6x7: L("Close to 5:4")
        case .xpan: L("Long, 2.7:1")
        case .sprocket135: L("Picture over the holes")
        case .f6x12: L("Long, 2:1")
        case .f6x17: L("Very long, 3:1")
        case .super8: L("Home movies")
        case .cine16: L("Small movie film")
        case .cine35: L("Cinema film")
        case .cine65: L("Big screen")
        case .cine65x15: L("Film runs sideways")
        }
    }
}

extension FilmEdgeFormat.Filter {
    var everydayLabel: String {
        switch self {
        case .all: L("All", as: "formats")
        case .film135: L("135 film")
        case .film120: L("120 film")
        case .panoramic: L("Wide", as: "formats")
        case .cine: L("Cine")
        }
    }
}

extension FilmEdgeView {
    /// 整条胶片: the whole width with its holes and print; 只留细边: a thin dark border round the picture.
    var everydayLabel: String { self == .strip ? L("Whole film") : L("Thin border") }
}
