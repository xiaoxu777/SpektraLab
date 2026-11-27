//  FilmLabExportPurposePreview.swift — 预览效果: the picture as the place it is going to will show it.
//
//  The owner, 2026-11-25: "最好还能有个阅览图，比方说看看放在 ins 上看是什么效果，还有微博啥的。" With a social purpose
//  chosen in 普通版's 导出 (`FilmLabExportPurpose.swift`), 预览效果 lays this over the viewer: a phone-sized sketch of that
//  place's layout with the real picture in it — the page's own picture, so its film edge, date back and watermarks
//  are there as they will be in the file.
//
//  **It takes the viewer's place rather than standing beside it**: at the window's smallest (1059 × 768) the viewer is
//  about 660 × 650 pt, room for one phone and not for a picture and a phone.
//
//  **A sketch, and drawn as one**: grey discs for people, bars for names and words, line symbols for the buttons, the
//  place's name in plain text. No logo, no brand colour, no typeface or artwork of theirs. Each place has two views (the
//  post and how it sits among others) and its feed in the light or the dark.
//
//  What the place does to the picture's shape is the point: the window the picture is shown through is clamped as the
//  place clamps it (`FilmLabExportPurpose.fits`, the squares of a nine-grid, a 3:4 profile tile), the picture fills it
//  and what falls outside is cut, exactly as the line under the phone says. With 加白边 chosen the picture is shown on
//  its white sheet, as its file will be.

import SwiftUI

/// Over the develop page's canvas: nothing unless 普通版's 导出 has 预览效果 on for a place with a feed.
struct FilmLabExportPurposePreview: View {
    let session: OpenFrameSession
    let frame: LibraryFrame

    @Environment(AppServices.self) private var model

    private var ui: FilmLabExportPurposeUI { .shared }

    var body: some View {
        if FeatureFlags.simpleWindow, ui.previewing, ui.purpose.isSocial, FilmLabFinish.shared.page == .export {
            stage(ui.purpose)
                .transition(.opacity)
        }
    }

    private func stage(_ p: FilmLabExportPurpose) -> some View {
        @Bindable var ui = ui
        let aspect = CGFloat(max(0.05, DevelopedFrameView.shownAspect(frame: frame, edit: session.shownEdit, model: model,
                                                                      developed: session.developed)))
        let shot = FilmLabPurposeShot(session: session, frame: frame, aspect: aspect,
                                      sheet: sheet(p, aspect: aspect))
        // The bar: which view, the feed light or dark, back to the photo.
        let bar = HStack(spacing: 10) {
            SegmentedSwitch(options: [false, true], selection: $ui.second, title: { viewTitle(p, second: $0) },
                            segmentWidth: 68, height: 28, track: Theme.card, size: 12.5)
                .accessibilityIdentifier("filmlab.export.preview.view")
            Spacer(minLength: 4)
            SegmentedSwitch(options: [false, true], selection: $ui.dark, title: { $0 ? L("Dark feed") : L("Light feed") },
                            segmentWidth: 46, height: 28, track: Theme.card, size: 12.5)
                .accessibilityIdentifier("filmlab.export.preview.dark")
            Button {
                withAnimation(.easeOut(duration: 0.2)) { ui.previewing = false }
            } label: {
                Label(L("Back to the Photo"), systemImage: "xmark").font(Theme.Font.ui(12.5, .semibold)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityIdentifier("filmlab.export.preview.close")
        }
        return GeometryReader { room in
            // A phone's screen, as tall as the room allows. Where the room is wide enough the bar's switches stand
            // beside the phone's top (the window's smallest size, the column at its narrowest); otherwise above it.
            let beside = room.size.width >= 2 * Self.barSide + 240
            let top: CGFloat = beside ? 14 : 52
            let h = max(200, min(room.size.height - top - Self.notesHeight, 700))
            let w = max(120, min(h * 0.56, room.size.width - (beside ? 2 * Self.barSide : 32)))
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    FilmLabPurposePhone(kind: p.kind, second: ui.second, dark: ui.dark, name: p.name, aspect: aspect,
                                        fits: p.fits, width: w, height: h, shot: shot)
                    VStack(spacing: 3) {
                        Text(note(p, aspect: aspect)).font(Theme.Font.ui(13, .medium)).foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                            .accessibilityIdentifier("filmlab.export.preview.note")
                        Text(L("A sketch of the layout. The app itself may differ a little."))
                            .font(Theme.Font.ui(11)).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: Self.notesHeight)
                }
                .padding(.top, top)
                .frame(maxWidth: .infinity)
                bar.padding(.horizontal, 14).padding(.top, 14)
            }
            .frame(width: room.size.width, height: room.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.well)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmlab.export.preview")
    }

    /// The room the bar's switches take on each side of the phone, and the two lines under it.
    private static let barSide: CGFloat = 250
    private static let notesHeight: CGFloat = 62

    /// The white sheet's shape, where 加白边 gives this picture one: the nearest shape the place shows.
    private func sheet(_ p: FilmLabExportPurpose, aspect: CGFloat) -> CGFloat? {
        guard ui.border, let fits = p.fits, p.cropped(Double(aspect)) != nil else { return nil }
        return min(max(aspect, CGFloat(fits.lowerBound)), CGFloat(fits.upperBound))
    }

    private func viewTitle(_ p: FilmLabExportPurpose, second: Bool) -> String {
        switch (p.kind, second) {
        case (.instagram, false): L("Feed", as: "a preview")
        case (.instagram, true): L("Profile", as: "a preview")
        case (.xiaohongshu, false): L("Discover", as: "a preview")
        case (.xiaohongshu, true): L("Note", as: "a preview")
        case (_, false): L("One Photo")
        case (_, true): L("Nine Photos")
        }
    }

    /// What the place does to this picture, in a line.
    private func note(_ p: FilmLabExportPurpose, aspect: CGFloat) -> String {
        if ui.second {
            switch p.kind {
            case .instagram: return L("The profile shows a 3:4 tile. A tap opens the post.")
            case .moments, .weibo: return L("In a set, each thumbnail is a square. A tap shows it whole.")
            default: break
            }
        }
        if let c = p.cropped(Double(aspect)) {
            if ui.border { return L("With the white border, all of it shows.") }
            return FilmLabExportPurposeUI.cropLine((1, c), of: 1, place: p.name)
        }
        if p.fits == nil, aspect > FilmLabPurposePhone.single.upperBound * 1.01 || aspect < FilmLabPurposePhone.single.lowerBound / 1.01 {
            return L("Very long pictures show their middle here. A tap shows it whole.")
        }
        return L("All of it shows. Nothing is cropped.")
    }
}

// MARK: - the picture

/// The page's own picture — the develop, Edit's pass over it (its 成片 watermarks), through Edit's crop — filling
/// whatever window a mock-up gives it, and cut by that window. On a white sheet first where 加白边 gave it one.
struct FilmLabPurposeShot {
    let session: OpenFrameSession
    let frame: LibraryFrame
    /// The picture's shape, width over height.
    let aspect: CGFloat
    /// The white sheet's shape (加白边), nil for none.
    let sheet: CGFloat?

    /// What is uploaded: the sheet, or the picture.
    var fileAspect: CGFloat { sheet ?? aspect }

    /// The file filling a `width` × `height` window, what does not fit cut away.
    @MainActor
    func filling(_ width: CGFloat, _ height: CGFloat) -> some View {
        let fa = fileAspect
        // The file, large enough to cover the window.
        let file = width / max(height, 1) > fa ? CGSize(width: width, height: width / fa) : CGSize(width: height * fa, height: height)
        // The picture on it: all of it, the sheet's white around it.
        let picture = file.width / max(file.height, 1) > aspect ? CGSize(width: file.height * aspect, height: file.height)
                                                                : CGSize(width: file.width, height: file.width / aspect)
        return ZStack {
            Color.white.frame(width: file.width, height: file.height)
            FilmLabPurposeLook(session: session, frame: frame, pointSize: max(picture.width, picture.height))
                .frame(width: picture.width, height: picture.height)
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The develop page's picture as its canvas draws it at rest (`DevelopCanvas.developedPicture`, `cut`).
private struct FilmLabPurposeLook: View {
    let session: OpenFrameSession
    let frame: LibraryFrame
    let pointSize: CGFloat

    @Environment(AppServices.self) private var model

    var body: some View {
        let edit = session.shownEdit
        if frame.isPair || edit.printCrop.isIdentity {
            whole(edit, pointSize)
        } else {
            let base = DevelopedFrameView.finishedSize(frame: frame, edit: edit, model: model, developed: session.developed)
            GeometryPicture(geometry: edit.printCrop.onFinished(base), imageSize: base) { points in
                whole(edit, max(points, pointSize))
            }
        }
    }

    @ViewBuilder private func whole(_ edit: FrameEdit, _ points: CGFloat) -> some View {
        let base = DevelopedFrameView(frame: frame, edit: edit, pointSize: points, developed: session.developed, cropsPrint: false)
        if edit.finishedActs(isComposite: frame.isComposite), session.layer2.picture != nil {
            Layer2Picture(live: session.layer2, pointSize: points) { base }
        } else {
            base
        }
    }
}

// MARK: - the phone

/// One place's screen, sketched.
struct FilmLabPurposePhone: View {
    let kind: FilmLabExportPurpose.Kind
    let second: Bool
    let dark: Bool
    let name: String
    let aspect: CGFloat
    let fits: ClosedRange<Double>?
    let width: CGFloat
    let height: CGFloat
    let shot: FilmLabPurposeShot

    /// The shapes one picture alone is shown at in a feed that has no stated range (朋友圈, 微博): a judgement, from
    /// how they look.
    static let single: ClosedRange<CGFloat> = 0.5...2.0

    private var paper: Color { dark ? Color(white: 0.07) : .white }
    private var ink: Color { dark ? Color(white: 0.92) : Color(white: 0.1) }
    private var bar: Color { dark ? Color(white: 0.24) : Color(white: 0.86) }
    private var faint: Color { dark ? Color(white: 0.16) : Color(white: 0.93) }
    private var hairline: Color { dark ? Color(white: 0.18) : Color(white: 0.9) }

    var body: some View {
        // The screen is the phone's size whatever is on it: a feed runs on past the bottom edge, as feeds do.
        RoundedRectangle(cornerRadius: 26, style: .continuous).fill(kind == .xiaohongshu && !second ? faint : paper)
            .frame(width: width, height: height)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    // The place's name, in plain text.
                    Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(paper)
                        .overlay(alignment: .bottom) { hairline.frame(height: 1) }
                    Group {
                        switch (kind, second) {
                        case (.instagram, false): instagramFeed
                        case (.instagram, true): instagramProfile
                        case (.xiaohongshu, false): discover
                        case (.xiaohongshu, true): noteOpen
                        case (.weibo, _): weibo
                        default: moments
                        }
                    }
                    .frame(width: width, alignment: .top)
                    .frame(minHeight: height - 40, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, height: height, alignment: .top)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color(white: dark ? 0.3 : 0.55), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
            .animation(.easeOut(duration: 0.2), value: second)
            .animation(.easeOut(duration: 0.2), value: dark)
    }

    // MARK: the parts

    private func words(_ w: CGFloat, _ h: CGFloat = 8) -> some View {
        Capsule().fill(bar).frame(width: w, height: h)
    }

    private func face(_ d: CGFloat, square: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: square ? d * 0.16 : d / 2, style: .continuous).fill(bar).frame(width: d, height: d)
    }

    private func symbol(_ name: String, _ size: CGFloat = 17) -> some View {
        Image(systemName: name).font(.system(size: size, weight: .regular)).foregroundStyle(ink)
    }

    /// The window the place shows the upload through: the file's shape, held inside `range`.
    private func window(_ w: CGFloat, in range: ClosedRange<CGFloat>) -> CGSize {
        let a = min(max(shot.fileAspect, range.lowerBound), range.upperBound)
        return CGSize(width: w, height: w / a)
    }

    private var range: ClosedRange<CGFloat> {
        fits.map { CGFloat($0.lowerBound)...CGFloat($0.upperBound) } ?? Self.single
    }

    /// A three-across grid of tiles, the picture in the first.
    private func grid(_ w: CGFloat, tile: CGFloat, gap: CGFloat, rows: Int) -> some View {
        let side = (w - gap * 2) / 3
        return VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { c in
                        if r == 0, c == 0 {
                            shot.filling(side, side / tile)
                        } else {
                            Rectangle().fill((r + c) % 2 == 0 ? bar : faint).frame(width: side, height: side / tile)
                        }
                    }
                }
            }
        }
    }

    // MARK: Instagram

    private var instagramFeed: some View {
        let size = window(width, in: range)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                face(26)
                words(72)
                Spacer()
                symbol("ellipsis", 14)
            }
            .padding(.horizontal, 10).frame(height: 44)
            shot.filling(size.width, size.height)
            HStack(spacing: 14) {
                symbol("heart")
                symbol("bubble.right")
                symbol("paperplane")
                Spacer()
                symbol("bookmark")
            }
            .padding(.horizontal, 12).frame(height: 40)
            VStack(alignment: .leading, spacing: 7) {
                words(64)
                words(width * 0.7)
                words(width * 0.45)
            }
            .padding(.horizontal, 12)
            hairline.frame(height: 1).padding(.top, 14)
            HStack(spacing: 8) {
                face(26)
                words(56)
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 44)
            Rectangle().fill(faint).frame(height: width)
        }
    }

    private var instagramProfile: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                face(54)
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 6) { words(22, 10); words(34, 6) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.top, 14)
            VStack(alignment: .leading, spacing: 7) {
                words(86)
                words(width * 0.55)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
            // The profile's tiles are 3:4.
            grid(width, tile: 0.75, gap: 2, rows: 3)
        }
    }

    // MARK: 朋友圈

    private var moments: some View {
        let column = width - 14 - 36 - 10 - 14
        return VStack(alignment: .leading, spacing: 0) {
            post(column: column) {
                if second {
                    grid(column * 0.92, tile: 1, gap: 4, rows: 3)
                } else {
                    // One picture alone: about two thirds of the column, at its own shape.
                    let box = column * 0.68
                    let a = min(max(shot.fileAspect, Self.single.lowerBound), Self.single.upperBound)
                    let size = a >= 1 ? CGSize(width: box, height: box / a) : CGSize(width: box * a, height: box)
                    shot.filling(size.width, size.height)
                }
            }
            hairline.frame(height: 1)
            post(column: column) { Rectangle().fill(faint).frame(width: column * 0.68, height: column * 0.45) }
            hairline.frame(height: 1)
            post(column: column) { EmptyView() }
        }
    }

    /// A moment: a square face, a name, a line of words, what was posted, when.
    private func post<Posted: View>(column: CGFloat, @ViewBuilder _ posted: () -> Posted) -> some View {
        HStack(alignment: .top, spacing: 10) {
            face(36, square: true)
            VStack(alignment: .leading, spacing: 9) {
                words(70, 9)
                words(column * 0.8)
                posted()
                HStack {
                    words(40, 6)
                    Spacer()
                    RoundedRectangle(cornerRadius: 3).fill(faint).frame(width: 26, height: 16)
                        .overlay { symbol("ellipsis", 10) }
                }
            }
            .frame(width: column, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
    }

    // MARK: 微博

    private var weibo: some View {
        let column = width - 28
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    face(36)
                    VStack(alignment: .leading, spacing: 6) { words(78, 9); words(52, 6) }
                    Spacer()
                    symbol("chevron.down", 11)
                }
                words(column * 0.9)
                words(column * 0.6)
                if second {
                    grid(column, tile: 1, gap: 4, rows: 3)
                } else {
                    // One picture alone: the column's width lying down, narrower standing up.
                    let a = min(max(shot.fileAspect, 0.75), 16.0 / 9.0)
                    let w = a >= 1 ? column : column * 0.62
                    shot.filling(w, w / a).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, 14).padding(.top, 14)
            HStack {
                ForEach(["arrowshape.turn.up.right", "bubble.left", "hand.thumbsup"], id: \.self) { s in
                    HStack(spacing: 5) { symbol(s, 14); words(18, 6) }.frame(maxWidth: .infinity)
                }
            }
            .frame(height: 42)
            faint.frame(height: 8)
            HStack(spacing: 9) {
                face(36)
                VStack(alignment: .leading, spacing: 6) { words(64, 9); words(44, 6) }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 14)
            VStack(alignment: .leading, spacing: 8) { words(column * 0.85); words(column * 0.5) }
                .padding(.horizontal, 14).padding(.top, 10)
        }
    }

    // MARK: 小红书

    private var discover: some View {
        let gap: CGFloat = 6
        let w = (width - gap * 3) / 2
        let cover = window(w, in: range)
        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) {
                cell(w) { shot.filling(cover.width, cover.height) }
                cell(w) { Rectangle().fill(bar).frame(width: w, height: w * 1.1) }
                cell(w) { Rectangle().fill(bar).frame(width: w, height: w) }
            }
            VStack(spacing: gap) {
                cell(w) { Rectangle().fill(bar).frame(width: w, height: w) }
                cell(w) { Rectangle().fill(bar).frame(width: w, height: w * 4 / 3) }
                cell(w) { Rectangle().fill(bar).frame(width: w, height: w * 1.2) }
            }
        }
        .padding(gap)
    }

    /// A note in the two-column feed: its cover, its title, who and how many hearts.
    private func cell<Cover: View>(_ w: CGFloat, @ViewBuilder _ cover: () -> Cover) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cover()
            VStack(alignment: .leading, spacing: 7) {
                words(w * 0.8)
                words(w * 0.5)
                HStack(spacing: 5) {
                    face(14)
                    words(min(38, w * 0.3), 6)
                    Spacer(minLength: 2)
                    symbol("heart", 11)
                }
            }
            .padding(8)
        }
        .frame(width: w)
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var noteOpen: some View {
        let size = window(width, in: range)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                symbol("chevron.left", 14)
                face(26)
                words(64)
                Spacer()
                Capsule().strokeBorder(bar, lineWidth: 1.5).frame(width: 48, height: 22)
                symbol("square.and.arrow.up", 14)
            }
            .padding(.horizontal, 10).frame(height: 44)
            shot.filling(size.width, size.height)
            HStack(spacing: 5) {
                Circle().fill(ink).frame(width: 5, height: 5)
                Circle().fill(bar).frame(width: 5, height: 5)
                Circle().fill(bar).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity).frame(height: 22)
            VStack(alignment: .leading, spacing: 9) {
                words(width * 0.6, 11)
                words(width * 0.82)
                words(width * 0.74)
                words(width * 0.4)
            }
            .padding(.horizontal, 14).padding(.top, 4)
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Capsule().fill(faint).frame(height: 28)
                symbol("heart", 16)
                symbol("star", 16)
                symbol("bubble.right", 16)
            }
            .padding(.horizontal, 12).frame(height: 46)
            .overlay(alignment: .top) { hairline.frame(height: 1) }
        }
    }
}
