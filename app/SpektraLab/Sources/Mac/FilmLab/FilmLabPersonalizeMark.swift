//  FilmLabPersonalizeMark.swift — 个性化's 水印: the app's watermark feature (PRD-8: the library of PNG marks in
//  Settings › Watermarks, a photograph's placements, the handles on the canvas), edited here instead of from the 图层
//  panel (the owner, 2026-11-25: "个性化界面还可以编辑水印").
//
//  The switch, then:
//  - **the marks as tiles**, three across on the checkerboard: 文字 (a mark made from typed text, kept in the library as
//    a PNG like any other, `FilmLabTextMark`), the library's marks; Upload PNG below opens Finder's panel with the
//    library's own checks;
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
    @State private var textStyle: FilmLabTextStyle = .print
    @State private var textFace = FilmLabHandwriting.faces[0].id
    @State private var textSeed = UUID()
    @State private var textTask: Task<Void, Never>?
    @State private var textRequest = UUID()
    @State private var signing = false
    @State private var signatureTarget: WatermarkPlacement?
    @State private var signatureFrame: UUID?
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
                uploadButton
                if let refusal {
                    Text(refusal).font(Theme.Font.ui(11.5)).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if typing { textRow; textChoices }
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
        .sheet(isPresented: $signing) {
            FilmLabSignatureSheet { data in
                guard session.frame?.id == signatureFrame, current?.id == signatureTarget?.id,
                      current?.mark == signatureTarget?.mark else { return L("The photo changed. Open the signature pad again.") }
                guard !session.exportHolds() else { return L("This picture is being exported. Its layers wait until the export is done.") }
                switch await store.add(data, name: L("Signature")) {
                case .failure(let why): return why.message
                case .success(let added):
                    guard session.frame?.id == signatureFrame, current?.id == signatureTarget?.id,
                          current?.mark == signatureTarget?.mark else { return L("The photo changed. Open the signature pad again.") }
                    guard !session.exportHolds() else { return L("This picture is being exported. Its layers wait until the export is done.") }
                    typing = false; refusal = nil; use(added.mark)
                    return nil
                }
            }
        }
        // The first mark's handles wait for a click on it: the picture is seen as it will leave the app.
        .onAppear {
            pickCurrent(selected: false)
            if let mark = current?.mark, FilmLabTextMark.recipe(of: mark) != nil { editText(mark, focus: false) }
        }
        .onChange(of: frame.id) { _, _ in cancelText(); typing = false; refusal = nil; pickCurrent(selected: false) }
        .onChange(of: text) { _, _ in
            cancelText(); textSeed = UUID()
            if textStyle == .hand, !textFaces.contains(where: { $0.id == textFace }), let first = textFaces.first {
                textFace = first.id
            }
        }
        .onChange(of: current?.mark) { _, mark in
            if typing, let mark, FilmLabTextMark.recipe(of: mark) != nil { editText(mark, focus: false) }
        }
        .onDisappear { cancelText() }
        .task(id: frame.id) { await checkLaunch() }
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
                cancelText()
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
                editText(chosen, focus: true)
            }
            ForEach(store.marks) { mark in
                tile(width: side, on: mark.id == chosen && !typing, label: mark.name, id: mark.id.uuidString) {
                    WatermarkThumbnail(mark: mark.id, cell: 5)
                } action: {
                    cancelText()
                    typing = false
                    use(mark)
                    if FilmLabTextMark.recipe(of: mark.id) != nil { editText(mark.id, focus: false) }
                }
            }
        }
        .frame(width: side * 3 + gap * 2, alignment: .leading)
    }

    private var uploadButton: some View {
        Button { cancelText(); importing = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(Theme.Font.ui(19, .medium)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Upload PNG")).font(Theme.Font.ui(14, .semibold)).foregroundStyle(Theme.text)
                    Text(L("Your logo or signature, transparent background"))
                        .font(Theme.Font.ui(12)).foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(width: width - 32, alignment: .leading)
            .frame(minHeight: 52)
            .background(Theme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(L("Your logo or signature, transparent background"))
        .accessibilityLabel(L("Upload PNG"))
        .accessibilityHint(L("Your logo or signature, transparent background"))
        .accessibilityIdentifier("filmlab.personalize.mark.upload")
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
                .disabled(textWords.isEmpty || (textStyle == .hand && !textFaces.contains(where: { $0.id == textFace })))
        }
        .onChange(of: textFocused) { _, now in
            MacLibraryBrowser.shared.typing = now
        }
        .onDisappear { MacLibraryBrowser.shared.typing = false }
    }

    private var textWords: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var textFaces: [FilmLabHandwriting.Face] { FilmLabHandwriting.available(for: textWords) }

    private var textChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            SegmentedSwitch(options: FilmLabTextStyle.allCases,
                            selection: Binding(get: { textStyle }, set: { style in
                                textStyle = style
                                if style == .hand, !textFaces.contains(where: { $0.id == textFace }), let first = textFaces.first {
                                    textFace = first.id
                                }
                                commitText()
                            }), title: { $0.label }, height: 36, track: Theme.card, size: 14)
                .accessibilityIdentifier("filmlab.personalize.mark.text.style")
            if textStyle == .hand {
                if textFaces.isEmpty {
                    Text(L("No handwriting font for this text.")).font(Theme.Font.ui(12)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(textFaces) { face in
                        let recipe = FilmLabTextRecipe(text: textWords, style: .hand, postScriptName: face.id)
                        FilmLabHandwritingTile(face: face, words: textWords,
                                              seed: FilmLabTextMark.existing(recipe, in: store)?.id ?? textSeed,
                                              width: max(80, (width - 40) / 2), selected: textFace == face.id) {
                            textFace = face.id
                            commitText()
                        }
                    }
                }
                HStack {
                    Text(L("Signature")).font(Theme.Font.ui(13, .medium)).foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Button(L("Draw one")) {
                        openSignature()
                    }
                    .buttonStyle(FilmLabPanelButtonStyle())
                    .disabled(session.exportHolds())
                    .accessibilityIdentifier("filmlab.personalize.mark.signature")
                }
            }
        }
    }

    private func editText(_ mark: UUID?, focus: Bool) {
        cancelText()
        let recipe = mark.flatMap(FilmLabTextMark.recipe(of:))
        text = recipe?.text ?? ""
        textStyle = recipe?.style ?? .print
        textFace = recipe?.postScriptName ?? FilmLabHandwriting.faces[0].id
        textSeed = UUID()
        typing = true
        textFocused = focus
    }

    private func cancelText() {
        textTask?.cancel(); textTask = nil
        textRequest = UUID()
    }

    private func commitText(recipe requested: FilmLabTextRecipe? = nil) {
        let recipe = requested ?? FilmLabTextRecipe(text: textWords, style: textStyle,
                                                   postScriptName: textStyle == .hand ? textFace : nil)
        cancelText()
        guard !recipe.text.isEmpty, !session.exportHolds() else { return }
        if recipe.style == .hand,
           !FilmLabHandwriting.available(for: recipe.text).contains(where: { $0.id == recipe.postScriptName }) { return }
        let target = current, frameID = frame.id, request = textRequest, seed = textSeed
        textSeed = UUID()                   // Another click during the write must have a different file identity.
        textFocused = false
        textTask = Task { @MainActor in
            let made = await FilmLabTextMark.mark(for: recipe, id: seed, in: store)
            // A font click may finish after another click, a frame change or an export. Its asset can stay in the
            // library, but it must never replace the new frame's watermark or overwrite a more recent choice.
            guard !Task.isCancelled, request == textRequest, session.frame?.id == frameID,
                  current?.id == target?.id, current?.mark == target?.mark, !session.exportHolds() else { return }
            guard let mark = made else {
                refusal = L("The text could not be made into a watermark.")
                return
            }
            refusal = nil
            use(mark, replacingOnly: requested == nil)
            textSeed = UUID()
        }
    }

    private func openSignature() {
        guard !session.exportHolds() else { return }
        cancelText(); textFocused = false
        signatureTarget = current; signatureFrame = frame.id; signing = true
    }

    /// The check uses the same recipe writer, placement and signature action as the buttons above.
    private func checkLaunch() async {
        guard FilmLabPersonalizeCheck.mark != nil || FilmLabPersonalizeCheck.signaturePad,
              await FilmLabPersonalizeCheck.settle(session, frameID: frame.id), session.takesWatermarks else { return }
        if let recipe = FilmLabPersonalizeCheck.mark, FilmLabPersonalizeCheck.consume(.mark) {
            commitText(recipe: recipe)
            await textTask?.value
            if !Task.isCancelled, session.frame?.id == frame.id, let mark = current?.mark,
               FilmLabTextMark.recipe(of: mark) != nil { editText(mark, focus: false) }
        }
        guard FilmLabPersonalizeCheck.signaturePad,
              await FilmLabPersonalizeCheck.settle(session, frameID: frame.id),
              await FilmLabPersonalizeCheck.settle(session, frameID: frame.id),
              FilmLabPersonalizeCheck.consume(.signature) else { return }
        openSignature()
    }

    /// `mark` on the picture: in the current placement's place (its spot, size, turn and opacity kept), or a new
    /// placement bottom right. One step of Undo.
    private func use(_ mark: WatermarkMark, replacingOnly: Bool = false) {
        FilmLabTextMark.remember(mark.id)
        if let p = current {
            let owns = session.beginHistoryTransaction()
            session.changeWatermark(p.id) { $0.mark = mark.id; if !replacingOnly { $0.on = true } }
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

/// Font samples are small images from the same outline/ink code as the baked mark. A sample task owns only one
/// image; changing the draft cancels publication of its old result, rather than caching every keystroke or face.
private struct FilmLabHandwritingTile: View {
    let face: FilmLabHandwriting.Face
    let words: String
    let seed: UUID
    let width: CGFloat
    let selected: Bool
    let action: () -> Void
    @State private var sample: CGImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let sample { Image(uiImage: UIImage(cgImage: sample)).interpolation(.high) }
                    else { Color.clear.frame(width: 1, height: 1) }
                }
                .opacity(words.isEmpty ? 0.45 : 1)
                .frame(maxWidth: .infinity).frame(height: 72)
                .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(face.label).font(Theme.Font.ui(11, selected ? .semibold : .medium))
                    .foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Theme.selectionFrame : Theme.rule, lineWidth: selected ? 2 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(face.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("filmlab.personalize.mark.face." + face.id)
        .task(id: "\(face.id)|\(words)|\(seed)|\(width)") {
            sample = nil
            let face = face, seed = seed, text = words.isEmpty ? "xiaoxu" : words, available = max(24, width - 16)
            let made = await Task.detached(priority: .userInitiated) {
                FilmLabHandwriting.sample(text, face: face, seed: seed, width: available)
            }.value
            if !Task.isCancelled { sample = made }
        }
    }
}

/// A watermark made from typed text: the words drawn white on nothing, kept in the library as a PNG named by them, so
/// everything a mark can do (its colour, its place, 底片) a line of text can. Which marks are text, and their words, is
/// kept beside the app's settings (`filmlab.watermark.texts`): the library's own index is not touched.
@MainActor
enum FilmLabTextMark {
    private static let textsKey = "filmlab.watermark.texts"
    private static let lastKey = "filmlab.watermark.last"
    private static let recipesKey = "filmlab.watermark.textRecipes"

    private static var texts: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: textsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: textsKey) }
    }

    /// The words `mark` was made from; nil for a PNG the person brought.
    static func text(of mark: UUID) -> String? { recipe(of: mark)?.text ?? texts[mark.uuidString] }

    /// Each optional recipe is its own Codable blob: a future/invalid entry cannot erase the other recipes. The old
    /// text dictionary keeps its exact shape. Missing recipe means legacy Print, NEVER a request to re-bake its PNG.
    private static var recipes: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: recipesKey) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: recipesKey) }
    }

    static func recipe(of mark: UUID) -> FilmLabTextRecipe? {
        if let data = recipes[mark.uuidString] { return try? JSONDecoder().decode(FilmLabTextRecipe.self, from: data) }
        return texts[mark.uuidString].map { FilmLabTextRecipe(text: $0, style: .print, postScriptName: nil) }
    }

    static func existing(_ recipe: FilmLabTextRecipe, in store: WatermarkStore) -> WatermarkMark? {
        store.marks.first { Self.recipe(of: $0.id) == recipe }
    }

    static func remember(_ mark: UUID) { UserDefaults.standard.set(mark.uuidString, forKey: lastKey) }

    /// The mark last put on a picture, while the library still has it.
    static func lastUsed(in store: WatermarkStore) -> WatermarkMark? {
        UserDefaults.standard.string(forKey: lastKey).flatMap(UUID.init(uuidString:)).flatMap(store.mark)
    }

    /// The library's mark for `words`: the one made from them before, or a new PNG.
    static func mark(for words: String, in store: WatermarkStore) async -> WatermarkMark? {
        await mark(for: FilmLabTextRecipe(text: words, style: .print, postScriptName: nil), id: UUID(), in: store)
    }

    static func mark(for recipe: FilmLabTextRecipe, id: UUID, in store: WatermarkStore) async -> WatermarkMark? {
        if let mark = existing(recipe, in: store) { return mark }
        let data: Data?
        if recipe.style == .print {
            data = png(recipe.text)          // The original renderer below is deliberately unchanged.
        } else {
            guard let face = FilmLabHandwriting.faces.first(where: { $0.id == recipe.postScriptName }),
                  FilmLabHandwriting.font(face, text: recipe.text, points: 180) != nil else { return nil }
            data = await Task.detached(priority: .userInitiated) {
                FilmLabHandwriting.png(recipe.text, face: face, seed: id)
            }.value
        }
        guard !Task.isCancelled, let data,
              case .success(let added) = await store.add(data, name: recipe.text, id: id) else { return nil }
        // SHA dedup may have returned an existing asset. Do not relabel someone else's PNG or text recipe.
        if case .new = added {
            texts[added.mark.id.uuidString] = recipe.text
            if let encoded = try? JSONEncoder().encode(recipe) { recipes[added.mark.id.uuidString] = encoded }
        }
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
