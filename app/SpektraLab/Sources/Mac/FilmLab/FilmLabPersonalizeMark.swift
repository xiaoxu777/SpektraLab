//  FilmLabPersonalizeMark.swift — 个性化's 水印: the app's watermark feature (PRD-8: the library of PNG marks in
//  Settings › Watermarks, a photograph's placements, the handles on the canvas), edited here instead of from the 图层
//  panel (the owner, 2026-11-25: "个性化界面还可以编辑水印").
//
//  The switch, then:
//  - **the marks as tiles**, three across on the checkerboard: 文字 (a mark made from typed text, kept in the library as
//    a PNG like any other, `FilmLabTextMark`), the library's marks, and PNG… (Finder's panel, the library's own checks);
//  - **where it sits**: a pad of nine places, each the safe margin in from its edge, beside 大小 and 不透明度 — the mark can
//    still be dragged, sized and turned on the picture itself (`WatermarkCanvasStage`);
//  - **its colour**, and in 专业版 成片 · 底片, the typed size and turn, and up to four marks (`WatermarkPage(embedded:)`).
//
//  The switch off keeps the placements and hides them (`WatermarkPlacement.on`), so on again brings them back where
//  they were. Every act is the session's own (`WatermarkActs`): one step of Undo each.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FilmLabMarkSection: View {
    let session: OpenFrameSession
    let frame: LibraryFrame
    let width: CGFloat

    @Environment(AppServices.self) private var model
    /// The text field is open: no mark is placed yet, or the placed one is being retyped.
    @State private var typing = false
    @State private var text = ""
    @State private var importing = false
    @State private var refusal: String?
    @State private var sizing = false
    @FocusState private var textFocused: Bool

    private var store: WatermarkStore { model.watermarks }
    private var marks: [WatermarkPlacement] { session.shownMarks }
    private var pro: Bool { !FeatureFlags.simpleWindow }
    /// The placement the controls edit: the picked one, else the topmost.
    private var current: WatermarkPlacement? { session.pickedMark ?? marks.last }
    private var anyOn: Bool { session.edit.watermarks.contains { $0.on } }

    var body: some View {
        FilmLabPersonalizeSection(title: L("Watermark"), symbol: "signature", value: summary,
                                  isOn: Binding(get: { anyOn || typing }, set: { setOn($0) }), id: "watermark") {
            VStack(alignment: .leading, spacing: 12) {
                tiles
                if typing { textRow }
                if let refusal {
                    Text(refusal).font(Theme.Font.ui(11.5)).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let p = current, anyOn {
                    if pro, marks.count > 1 || WatermarkGeometry.canAdd(to: session.edit.watermarks) { markChips(p) }
                    placeRow(p)
                    WatermarkPage(session: session, placement: p, embedded: pro ? .pro : .simple)
                        .padding(.horizontal, -16)
                }
            }
            .padding(.horizontal, 16)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png]) { result in
            guard case .success(let url) = result else { return }
            Task { @MainActor in
                switch await store.add(fileAt: url) {
                case .success(let added): refusal = nil; use(added.mark)
                case .failure(let why): refusal = why.message
                }
            }
        }
        // The first mark's handles wait for a click on it: the picture is seen as it will leave the app.
        .onAppear { pickCurrent(selected: false) }
        .onChange(of: frame.id) { _, _ in typing = false; refusal = nil; pickCurrent(selected: false) }
    }

    /// "© Eric · 右下" under the name: the mark's name, and how many where there are more.
    private var summary: String? {
        guard let p = current else { return nil }
        let name = store.mark(p.mark)?.name ?? L("Missing")
        let on = session.edit.watermarks.filter(\.on).count
        return on > 1 ? name + Fmt.dot + L("\(on) watermarks") : name
    }

    // MARK: the switch

    private func setOn(_ on: Bool) {
        withAnimation(.easeOut(duration: 0.18)) {
            if on {
                if !session.edit.watermarks.isEmpty {
                    session.change { e in for i in e.watermarks.indices { e.watermarks[i].on = true } }
                    pickCurrent(selected: true)
                } else if let mark = FilmLabTextMark.lastUsed(in: store) ?? store.marks.first {
                    use(mark)
                } else {
                    // An empty library: the text field first.
                    typing = true
                    textFocused = true
                }
            } else {
                typing = false
                session.watermarkPick = nil
                if anyOn { session.change { e in for i in e.watermarks.indices { e.watermarks[i].on = false } } }
            }
        }
    }

    /// The row's pick is the canvas's stage (`watermarkPick`); `selected` puts its handles out.
    private func pickCurrent(selected: Bool) {
        guard anyOn, let p = current, p.on else { return }
        if session.watermarkPick != p.id { session.watermarkPick = p.id }
        session.watermarkSelected = selected
    }

    // MARK: the marks

    private var tiles: some View {
        let gap: CGFloat = 8
        let side = floor((width - 32 - gap * 2) / 3)
        let chosen = anyOn ? current?.mark : nil
        return ChipFlow(spacing: gap, lineSpacing: gap) {
            tile(width: side, on: typing, label: L("Text", as: "a watermark of typed words"), id: "text") {
                Text(verbatim: "Aa").font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(Theme.text)
            } action: {
                text = chosen.flatMap(FilmLabTextMark.text(of:)) ?? ""
                typing = true
                textFocused = true
            }
            ForEach(store.marks) { mark in
                tile(width: side, on: mark.id == chosen && !typing, label: mark.name, id: mark.id.uuidString) {
                    WatermarkThumbnail(mark: mark.id, cell: 5)
                } action: {
                    typing = false
                    use(mark)
                }
            }
            tile(width: side, on: false, label: L("PNG…"), id: "png") {
                Image(systemName: "plus").font(Theme.Font.ui(17, .medium)).foregroundStyle(Theme.secondaryText)
            } action: { importing = true }
        }
        .frame(width: side * 3 + gap * 2, alignment: .leading)
    }

    private func tile<Face: View>(width side: CGFloat, on: Bool, label: String, id: String,
                                  @ViewBuilder face: () -> Face, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                face()
                    .frame(width: side - 12, height: 44)
                    .background(Theme.plot)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(label).font(Theme.Font.ui(11, on ? .semibold : .medium))
                    .foregroundStyle(on ? Theme.text : Theme.secondaryText).lineLimit(1).truncationMode(.tail)
                    .frame(width: side - 12)
            }
            .padding(.top, 6).padding(.bottom, 6)
            .frame(width: side)
            .background(on ? Theme.card : Theme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                if on { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.selectionFrame, lineWidth: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("filmlab.personalize.mark." + id)
    }

    private var textRow: some View {
        HStack(spacing: 8) {
            TextField(L("Your name or a line of text"), text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Font.ui(13))
                .foregroundStyle(Theme.text)
                .focused($textFocused)
                .onSubmit { commitText() }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(textFocused ? Theme.accent : Theme.rule, lineWidth: 1))
                .accessibilityIdentifier("filmlab.personalize.mark.field")
            Button(L("Use", as: "use this text")) { commitText() }
                .buttonStyle(FilmLabPanelButtonStyle(primary: true))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onChange(of: textFocused) { _, now in
            MacLibraryBrowser.shared.typing = now
        }
        .onDisappear { MacLibraryBrowser.shared.typing = false }
    }

    private func commitText() {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        textFocused = false
        Task { @MainActor in
            guard let mark = await FilmLabTextMark.mark(for: words, in: store) else {
                refusal = L("The text could not be made into a watermark.")
                return
            }
            refusal = nil
            typing = false
            use(mark)
        }
    }

    /// `mark` on the picture: in the current placement's place (its spot, size, turn and opacity kept), or a new
    /// placement bottom right. One step of Undo.
    private func use(_ mark: WatermarkMark) {
        FilmLabTextMark.remember(mark.id)
        if let p = current {
            let owns = session.beginHistoryTransaction()
            session.changeWatermark(p.id) { $0.mark = mark.id; $0.on = true }
            if owns { session.endHistoryTransaction() }
            pickCurrent(selected: true)
            return
        }
        add(mark)
    }

    private func add(_ mark: WatermarkMark) {
        let aspect = Double(mark.w) / Double(max(mark.h, 1))
        let owns = session.beginHistoryTransaction()
        if let id = session.addWatermark(mark) {
            session.changeWatermark(id) { p in
                // Bottom right of the picture, the safe margin in.
                p.size = FilmLabMarkPlace.startSize(aspect: aspect)
                p.anchor = .br
                p.dx = WatermarkGeometry.safeMargin + p.size / 2
                p.dy = WatermarkGeometry.safeMargin + p.size / (2 * max(aspect, 0.01))
                let g = ground(p)
                p = FilmLabMarkPlace.placed(p, at: .init(column: 2, row: 2), canvas: g.canvas, box: g.box, aspect: aspect)
            }
        }
        if owns { session.endHistoryTransaction() }
        session.watermarkSelected = true
    }

    // MARK: 专业版: several marks

    private func markChips(_ p: WatermarkPlacement) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(marks.enumerated()), id: \.element.id) { i, m in
                let on = m.id == p.id
                Button { session.watermarkPick = m.id } label: {
                    Text(verbatim: "\(i + 1)").font(Theme.Font.ui(12, .semibold)).monospacedDigit()
                        .foregroundStyle(on ? Theme.onSelection : Theme.text)
                        .frame(width: 28, height: 24)
                        .background(on ? Theme.selection : Theme.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .opacity(m.on ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .help(store.mark(m.mark)?.name ?? "")
                .accessibilityLabel(L("Watermark \(i + 1)"))
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
            if WatermarkGeometry.canAdd(to: session.edit.watermarks), let mark = store.mark(p.mark) ?? store.marks.first {
                Button { add(mark) } label: {
                    Image(systemName: "plus").font(Theme.Font.ui(11, .semibold)).foregroundStyle(Theme.secondaryText)
                        .frame(width: 28, height: 24)
                        .background(Theme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(L("Add Watermark"))
                .accessibilityLabel(L("Add Watermark"))
            }
            Spacer(minLength: 0)
            Button { session.removeWatermark(p.id) } label: {
                Image(systemName: "trash").font(Theme.Font.ui(12, .medium)).foregroundStyle(Theme.secondaryText)
                    .frame(width: 28, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Delete Watermark"))
            .accessibilityLabel(L("Delete Watermark"))
            .accessibilityIdentifier("filmlab.personalize.mark.delete")
        }
    }

    // MARK: where it sits, how big

    private func aspect(_ p: WatermarkPlacement) -> Double {
        guard let i = store.info(p.mark), i.w > 0, i.h > 0 else { return 1 }
        return Double(i.w) / Double(i.h)
    }

    /// The canvas `p` is measured on (any unit: its numbers are shares of the short side) and the picture's box on it:
    /// under a film edge a 成片 mark's canvas is the whole film, and the pad's places are the picture's, not the
    /// rebate's (a mark is still dragged onto the edge by hand). Made from the edit, so it is there before the
    /// canvas's own stage is.
    private func ground(_ p: WatermarkPlacement) -> (canvas: CGSize, box: CGRect) {
        let e = session.shownEdit
        let finished = DevelopedFrameView.finishedSize(frame: frame, edit: e, model: model, developed: session.developed)
        guard let c = model.watermarkCanvases(frame, edit: e, finished: finished), c.full.width > 0, c.full.height > 0 else {
            let s = session.markCanvas(p)
            return (s, CGRect(origin: .zero, size: s))
        }
        if !WatermarkRules.drawnAsFull(p, appliesFilm: e.appliesFilm), c.base.width > 0 { return (c.base, CGRect(origin: .zero, size: c.base)) }
        let whole = CGRect(origin: .zero, size: c.full)
        let box = CGRect(origin: .zero, size: c.base).applying(c.baseToFull).intersection(whole)
        return (c.full, box.width > 1 && box.height > 1 ? box : whole)
    }

    private func placeRow(_ p: WatermarkPlacement) -> some View {
        let g = ground(p), canvas = g.canvas, box = g.box, a = aspect(p)
        let spot = FilmLabMarkPlace.spot(of: p, canvas: canvas, box: box, aspect: a)
        let most = min(0.9, WatermarkGeometry.maxSize(canvas: canvas, aspect: a))
        return HStack(alignment: .center, spacing: 14) {
            FilmLabMarkPad(spot: spot, canvasAspect: box.height > 0 ? box.width / box.height : 1.5) { s in
                session.changeWatermark(p.id) { $0 = FilmLabMarkPlace.placed($0, at: s, canvas: canvas, box: box, aspect: a) }
                session.watermarkSelected = true
            }
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(L("Size")).font(Theme.Font.ui(12.5, .medium)).foregroundStyle(Theme.text)
                        .frame(width: 52, alignment: .leading)
                    SliderTrack(value: Binding(get: { p.size }, set: { v in
                        session.moveWatermark(p.id) { q in
                            q.size = min(max(v, WatermarkGeometry.minSize), most)
                            // On a place of the pad it stays there, its margin kept; elsewhere it grows about its centre.
                            q = spot.map { FilmLabMarkPlace.placed(q, at: $0, canvas: canvas, box: box, aspect: a) }
                                ?? WatermarkGeometry.settled(q, canvas: canvas, aspect: a)
                        }
                    }), range: WatermarkGeometry.minSize...max(most, WatermarkGeometry.minSize + 0.01), rest: 0.18, step: 0.005,
                                detentAtRest: false, showsRest: false,
                                onEditingChanged: { down in
                                    guard down != sizing else { return }
                                    sizing = down
                                    down ? session.beganWatermark() : session.endedWatermark()
                                })
                        .frame(height: 28)
                    Text(verbatim: "\(Int((p.size * 100).rounded())) %").font(Theme.Font.ui(12).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText).frame(width: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Size"))
                .accessibilityValue("\(Int((p.size * 100).rounded())) %")
                .accessibilityIdentifier("filmlab.personalize.mark.size")
            }
        }
    }
}

/// The nine places of the pad, and a mark's numbers at each.
enum FilmLabMarkPlace {
    struct Spot: Hashable { var column: Int; var row: Int }

    /// A new mark's width, of the short side: a signature in a corner, a wide line of text a little wider.
    static func startSize(aspect: Double) -> Double { aspect > 4 ? 0.32 : aspect > 2 ? 0.24 : 0.16 }

    /// A place's centre: in `box` (the picture on the canvas), the safe margin of the box's short side in from its edge.
    private static func centre(_ p: WatermarkPlacement, at s: Spot, canvas: CGSize, box: CGRect, aspect: Double) -> CGPoint {
        let w = p.size * WatermarkGeometry.shortSide(canvas), h = w / max(aspect, 0.01)
        let m = WatermarkGeometry.safeMargin * Double(min(box.width, box.height))
        // A turned mark's box, so a quarter turn keeps its margin too.
        let c = abs(cos(p.rotation)), sn = abs(sin(p.rotation))
        let bw = w * c + h * sn, bh = w * sn + h * c
        let x = s.column == 0 ? Double(box.minX) + m + bw / 2 : s.column == 1 ? Double(box.midX) : Double(box.maxX) - m - bw / 2
        let y = s.row == 0 ? Double(box.minY) + m + bh / 2 : s.row == 1 ? Double(box.midY) : Double(box.maxY) - m - bh / 2
        return CGPoint(x: x, y: y)
    }

    static func placed(_ p: WatermarkPlacement, at s: Spot, canvas: CGSize, box: CGRect, aspect: Double) -> WatermarkPlacement {
        guard canvas.width > 0, canvas.height > 0 else { return p }
        let q = WatermarkGeometry.placement(p, centeredAt: centre(p, at: s, canvas: canvas, box: box, aspect: aspect), canvas: canvas)
        return WatermarkGeometry.settled(q, canvas: canvas, aspect: aspect)
    }

    /// The place the mark is on, within a hundredth of the short side; nil off the pad's places (dragged by hand).
    static func spot(of p: WatermarkPlacement, canvas: CGSize, box: CGRect, aspect: Double) -> Spot? {
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let at = WatermarkGeometry.storedCenter(of: p, canvas: canvas)
        let near = 0.012 * WatermarkGeometry.shortSide(canvas)
        for row in 0..<3 {
            for column in 0..<3 {
                let c = centre(p, at: Spot(column: column, row: row), canvas: canvas, box: box, aspect: aspect)
                if abs(c.x - at.x) <= near, abs(c.y - at.y) <= near { return Spot(column: column, row: row) }
            }
        }
        return nil
    }
}

/// The pad: a small picture's outline with nine places; the mark's is lit.
struct FilmLabMarkPad: View {
    let spot: FilmLabMarkPlace.Spot?
    let canvasAspect: CGFloat
    let choose: (FilmLabMarkPlace.Spot) -> Void

    private static let names = [["top left", "top", "top right"], ["left", "centre", "right"], ["bottom left", "bottom", "bottom right"]]

    var body: some View {
        let a = min(max(canvasAspect, 0.6), 1.8)
        let size = a >= 1 ? CGSize(width: 96, height: 96 / a) : CGSize(width: 78 * a, height: 78)
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { column in
                        let s = FilmLabMarkPlace.Spot(column: column, row: row)
                        let on = s == spot
                        Button { choose(s) } label: {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(on ? Theme.selection : Theme.dim.opacity(0.55))
                                .frame(width: on ? 14 : 8, height: on ? 6 : 4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: Alignment(horizontal: column == 0 ? .leading : column == 1 ? .center : .trailing,
                                                            vertical: row == 0 ? .top : row == 1 ? .center : .bottom))
                                .padding(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L(shown: Self.names[row][column]))
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Theme.plot, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
        .frame(width: 96, height: 80)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmlab.personalize.mark.pad")
    }
}

/// A watermark made from typed text: the words drawn white on nothing, kept in the library as a PNG named by them, so
/// everything a mark can do (its colour, its place, 底片) a line of text can. Which marks are text, and their words, is
/// kept beside the app's settings (`filmlab.watermark.texts`): the library's own index is not touched.
@MainActor
enum FilmLabTextMark {
    private static let textsKey = "filmlab.watermark.texts"
    private static let lastKey = "filmlab.watermark.last"

    private static var texts: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: textsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: textsKey) }
    }

    /// The words `mark` was made from; nil for a PNG the person brought.
    static func text(of mark: UUID) -> String? { texts[mark.uuidString] }

    static func remember(_ mark: UUID) { UserDefaults.standard.set(mark.uuidString, forKey: lastKey) }

    /// The mark last put on a picture, while the library still has it.
    static func lastUsed(in store: WatermarkStore) -> WatermarkMark? {
        UserDefaults.standard.string(forKey: lastKey).flatMap(UUID.init(uuidString:)).flatMap(store.mark)
    }

    /// The library's mark for `words`: the one made from them before, or a new PNG.
    static func mark(for words: String, in store: WatermarkStore) async -> WatermarkMark? {
        if let kept = texts.first(where: { $0.value == words })?.key, let id = UUID(uuidString: kept), let mark = store.mark(id) {
            return mark
        }
        guard let data = png(words), case .success(let added) = await store.add(data, name: words) else { return nil }
        texts[added.mark.id.uuidString] = words
        return added.mark
    }

    /// `words` in the system's semibold face, white, on a transparent ground, a little air around them.
    static func png(_ words: String) -> Data? {
        let line = String(words.prefix(80))
        var points: CGFloat = 180
        var drawn = NSAttributedString(string: line)
        var size = CGSize.zero
        // Narrow enough for the library (8192 px a side at the most).
        for _ in 0..<6 {
            drawn = NSAttributedString(string: line, attributes: [.font: UIFont.systemFont(ofSize: points, weight: .semibold),
                                                                   .foregroundColor: UIColor.white, .kern: points * 0.02])
            size = drawn.size()
            if size.width <= 7000 { break }
            points *= 0.7
        }
        guard size.width >= 1, size.height >= 1 else { return nil }
        let pad = (points * 0.18).rounded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let canvas = CGSize(width: ceil(size.width) + pad * 2, height: ceil(size.height) + pad * 2)
        return UIGraphicsImageRenderer(size: canvas, format: format).pngData { _ in drawn.draw(at: CGPoint(x: pad, y: pad)) }
    }
}
