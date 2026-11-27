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
import UIKit

/// Over the develop page's canvas: nothing unless 普通版's 导出 has 预览效果 on for a place with a feed.
struct FilmLabExportPurposePreview: View {
    let session: OpenFrameSession
    let frame: LibraryFrame

    @Environment(AppServices.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ui: FilmLabExportPurposeUI { .shared }
    @State private var displayed = FilmLabExportPreviewChoice(kind: .moments, second: false, dark: false, border: false)
    @State private var mounted = false
    @State private var moving = false
    @State private var travel = false
    @State private var progress: CGFloat = 0
    @State private var flight: FilmLabExportPreviewFlight?
    @State private var slot: FilmLabExportPreviewSlot?
    @State private var area: CGSize = .zero
    @State private var revision = 0
    @State private var flightFrame: LibraryFrame.ID?
    @State private var coachArmed = false
    @State private var coachVisible = false

    private var coachPreference: FilmLabExportCoachPreference {
        FilmLabExportCoachPreference(defaults: .standard, forced: CommandLine.arguments.contains("--filmlab-export-coach"))
    }
    // Read the same derivation as Export, including its current-photo fallback. Never make a second selection rule.
    private var postIDs: [LibraryFrame.ID] { MacDevelopExport.ids(current: frame.id, model: model) }
    private var coachReady: Bool { wanted && mounted && !moving && coachArmed }

    private var choice: FilmLabExportPreviewChoice {
        FilmLabExportPreviewChoice(kind: ui.kind, second: ui.second, dark: ui.dark, border: ui.border)
    }
    private var wanted: Bool {
        FeatureFlags.simpleWindow && FilmLabFinish.shared.page == .export && ui.previewing && ui.purpose.isSocial
    }
    private var calm: Bool { reduceMotion || FilmLabExportPreviewMotion.calmCheck }
    private var curve: Animation { travel ? FilmLabExportPreviewMotion.move : FilmLabExportPreviewMotion.crossfade }
    private var detailsVisible: Bool { mounted && wanted }

    var body: some View {
        if FeatureFlags.simpleWindow {
            ZStack {
                // Opaque from the first travel frame: the real canvas stays mounted, but never shows a second photo.
                // In Reduce Motion this same cover fades with the mock-up, giving a plain cross-fade instead.
                Theme.well.opacity(mounted ? (travel ? 1 : Double(progress)) : 0)
                    .animation(travel ? nil : FilmLabExportPreviewMotion.crossfade, value: progress)
                stage(displayed.purpose)
                if moving, let flight {
                    FilmLabExportPreviewMovingPhoto(flight: flight, progress: progress)
                        .onAppear { drive(to: wanted) }
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                area = size
                beginIfReady()
            }
            .allowsHitTesting(mounted && wanted)
            .accessibilityHidden(!mounted)
            // A purpose card's animation must not implicitly animate layout, mounting, or the handoff. Each moving
            // leaf reinstates its own opacity/transform animation, also below ShellContent's cleared transaction.
            .transaction { $0.animation = nil }
            .onAppear { ui.previewToggleIfAsked() }
            .simultaneousGesture(TapGesture().onEnded { dismissCoach() })
            .onChange(of: MacLibraryBrowser.shared.selection) { _, _ in
                if wanted { dismissCoach() }
            }
            .task(id: coachReady) {
                guard coachReady else { return }
                do { try await Task.sleep(for: .seconds(0.4)) } catch { return }
                guard coachReady else { return }
                withAnimation(.easeInOut(duration: 0.2)) { coachVisible = true }
            }
            .task(id: wanted) {
                guard wanted else { return }
                await ui.chooseWalkIfAsked(model: model)
            }
            .onChange(of: wanted, initial: true) { _, show in request(show) }
            .onChange(of: choice) { _, _ in
                guard !moving, choice.purpose.isSocial else { return }
                showChoice()
                beginIfReady()
            }
            .onDisappear {
                revision += 1
                mounted = false; moving = false; travel = false; progress = 0; flight = nil; flightFrame = nil
                coachVisible = false; coachArmed = false
            }
        }
    }

    private func shot(_ p: FilmLabExportPurpose, id: LibraryFrame.ID? = nil) -> FilmLabPurposeShot {
        let source = (id ?? postIDs.first).flatMap { model.library.frame($0) } ?? frame
        let open = source.id == frame.id ? session : model.openSession(source.id)
        let edit = open?.shownEdit ?? source.edit
        let aspect = CGFloat(max(0.05, DevelopedFrameView.shownAspect(frame: source, edit: edit, model: model,
                                                                      developed: open?.developed)))
        var shot = FilmLabPurposeShot(session: open, frame: source, aspect: aspect, sheet: sheet(p, aspect: aspect))
        shot.pixels = flightFrame == source.id ? flight?.pixels : nil
        return shot
    }

    private func dismissCoach() {
        guard coachArmed else { return }
        coachArmed = false
        withAnimation(.easeOut(duration: 0.2)) { coachVisible = false }
        coachPreference.dismiss()
    }

    private func showChoice() {
        guard choice.purpose.isSocial else { return }
        withAnimation(mounted ? FilmLabExportPreviewMotion.crossfade : nil) { displayed = choice }
    }

    private func request(_ show: Bool) {
        if show {
            coachArmed = coachPreference.shouldShow
            coachVisible = false
            if mounted {
                if moving { drive(to: true) }
                else { showChoice() }
            } else {
                showChoice()
                beginIfReady()
            }
        } else if mounted {
            coachArmed = false
            withAnimation(.easeOut(duration: 0.2)) { coachVisible = false }
            if !moving {
                flight = makeFlight()
                travel = flight != nil
                moving = true
                if travel { return } // mount the copy at progress one before its onAppear reverses it
            }
            drive(to: false)
        }
    }

    private func beginIfReady() {
        guard wanted, !mounted, displayed == choice, area.width > 0, area.height > 0,
              slot?.choice == displayed.id else { return }
        flight = makeFlight()
        travel = flight != nil
        mounted = true; moving = true
        // The copy first mounts at progress zero, then its onAppear starts the move. A cross-fade needs no copy;
        // the phone already has a stable place in the tree (its invisible slot was measured before the press).
        if !travel { drive(to: true) }
    }

    private func makeFlight() -> FilmLabExportPreviewFlight? {
        guard !calm, let slot, slot.choice == displayed.id else { return nil }
        let shot = shot(displayed.purpose)
        guard let pixels = shot.cachedPixels(model: model) else { return nil } // no decode just for a transition
        flightFrame = shot.frame.id
        let scale = phoneScale(in: area)
        guard scale > 0, slot.rect.width > 0, slot.rect.height > 0 else { return nil }
        let end = CGRect(x: (area.width - FilmLabPhoneMetrics.width * scale) / 2
                            + (FilmLabPhoneMetrics.bezel + slot.rect.minX) * scale,
                         y: Self.barHeight + 12 + (FilmLabPhoneMetrics.bezel + slot.rect.minY) * scale,
                         width: slot.rect.width * scale, height: slot.rect.height * scale)
        return FilmLabExportPreviewFlight(pixels: pixels, area: area,
                                          start: FilmLabExportPreviewMotion.viewerRect(in: area, aspect: shot.aspect),
                                          end: end, shot: shot, radius: slot.radius * scale,
                                          bottomRadius: slot.bottomRadius * scale)
    }

    private func drive(to show: Bool) {
        revision += 1
        let ticket = revision
        // Retarget the same scalar and the same copy. SwiftUI starts at its presentation value on reversal.
        withAnimation(curve, completionCriteria: .removed) { progress = show ? 1 : 0 } completion: {
            guard revision == ticket, wanted == show else { return }
            moving = false; flight = nil; flightFrame = nil
            if !show { mounted = false }
            travel = false
            showChoice()
        }
    }

    private static let barHeight: CGFloat = 42 // 28 pt controls + 14 pt top padding
    private func phoneScale(in size: CGSize) -> CGFloat {
        max(0, min((size.width - 24) / FilmLabPhoneMetrics.width,
                   (size.height - Self.barHeight - Self.notesHeight - Self.coachHeight - 24) / FilmLabPhoneMetrics.height))
    }

    private func stage(_ p: FilmLabExportPurpose) -> some View {
        @Bindable var ui = ui
        let content = displayed
        let shot = shot(p)
        let aspect = shot.aspect
        let shots = postIDs.map { self.shot(p, id: $0) }
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
                ui.previewing = false
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
        return VStack(spacing: 0) {
            bar.padding(.horizontal, 14).padding(.top, 14)
                .opacity(detailsVisible ? 1 : 0)
                .animation(FilmLabExportPreviewMotion.crossfade.delay(detailsVisible && !calm ? 0.1 * FilmLabExportPreviewMotion.slow : 0),
                           value: detailsVisible)
            GeometryReader { room in
                // `room` is what remains below the controls. Reserve the captions and 12 pt above/below;
                // fit the whole phone, bezel included, without a minimum size or a large-window height cap.
                let scale = phoneScale(in: area)
                VStack(spacing: 0) {
                    FilmLabPhoneFrame {
                        ZStack {
                            FilmLabPurposeFeed(kind: p.kind, second: content.second, dark: content.dark, name: p.name,
                                               shot: shot, shots: shots, showsPhoto: mounted && !travel)
                                .overlayPreferenceValue(FilmLabExportPreviewPhotoKey.self) { anchor in
                                    GeometryReader { feed in
                                        let measured = anchor.map {
                                            FilmLabExportPreviewSlot(choice: content.id, rect: feed[$0.bounds],
                                                                     radius: $0.radius, bottomRadius: $0.bottomRadius)
                                        }
                                        Color.clear.onChange(of: measured, initial: true) { _, value in
                                            // An outgoing screen may still publish a preference while fading out.
                                            guard let value, value.choice == displayed.id else { return }
                                            slot = value
                                            beginIfReady()
                                        }
                                    }
                                }
                                .id(content.id)
                                .transition(.opacity)
                        }
                        .animation(mounted ? FilmLabExportPreviewMotion.crossfade : nil, value: displayed)
                    }
                    .opacity(Double(progress))
                    .scaleEffect(scale, anchor: .topLeading)
                    // scaleEffect changes drawing, not layout: give the stack the actual displayed size.
                    .frame(width: FilmLabPhoneMetrics.width * scale,
                           height: FilmLabPhoneMetrics.height * scale, alignment: .topLeading)
                    .offset(y: calm || !travel ? 0 : 10 * (1 - progress))
                    .animation(curve, value: progress)
                    VStack(spacing: 3) {
                        Text(note(p, aspect: aspect)).font(Theme.Font.ui(13, .medium)).foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                            .accessibilityIdentifier("filmlab.export.preview.note")
                        Text(L("A sketch of the layout. The app itself may differ a little."))
                            .font(Theme.Font.ui(11)).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: Self.notesHeight)
                    .opacity(detailsVisible ? 1 : 0)
                    .animation(FilmLabExportPreviewMotion.crossfade.delay(detailsVisible && !calm ? 0.1 * FilmLabExportPreviewMotion.slow : 0),
                               value: detailsVisible)
                }
                .padding(.top, 12)
                .frame(width: room.size.width, height: room.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            ZStack {
                if coachVisible {
                    FilmLabExportCoachMark(calm: calm)
                        .padding(.horizontal, 12).padding(.bottom, 5)
                        .transition(.opacity)
                }
            }
            // The canvas host clears inherited transactions; reinstate this fade at the leaf, like the phone.
            .animation(.easeOut(duration: 0.2), value: coachVisible)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmlab.export.preview")
    }

    /// The two caption lines stay outside the scaled phone.
    private static let notesHeight: CGFloat = 62
    private static let coachHeight: CGFloat = 46

    /// The white sheet's shape, where 加白边 gives this picture one: the nearest shape the place shows.
    private func sheet(_ p: FilmLabExportPurpose, aspect: CGFloat) -> CGFloat? {
        guard displayed.border, let fits = p.fits, p.cropped(Double(aspect)) != nil else { return nil }
        return min(max(aspect, CGFloat(fits.lowerBound)), CGFloat(fits.upperBound))
    }

    private func viewTitle(_ p: FilmLabExportPurpose, second: Bool) -> String {
        switch (p.kind, second) {
        case (.instagram, false): L("Feed", as: "a preview")
        case (.instagram, true): L("Profile", as: "a preview")
        case (.xiaohongshu, false): L("Discover", as: "a preview")
        case (.xiaohongshu, true): L("Note", as: "a preview")
        case (_, false): postIDs.count > 1 ? L("Post", as: "export preview") : L("One Photo")
        case (_, true): L("Nine Photos")
        }
    }

    /// What the place does to this picture, in a line.
    private func note(_ p: FilmLabExportPurpose, aspect: CGFloat) -> String {
        if displayed.second || (postIDs.count > 1 && (p.kind == .moments || p.kind == .weibo)) {
            switch p.kind {
            case .instagram: return L("The profile shows a 3:4 tile. A tap opens the post.")
            case .moments, .weibo: return L("In a set, each thumbnail is a square. A tap shows it whole.")
            default: break
            }
        }
        // The preview's Instagram carousel uses 4:5, while the export recipe still allows its existing 3:4 sheet.
        // Describe the actual uploaded sheet through this window without changing the card or the export contract.
        let fileAspect = sheet(p, aspect: aspect) ?? aspect
        let cropped = p.kind == .instagram && fileAspect < 0.8 / 1.01
            ? FilmLabExportPurpose.Cropped.ends : p.cropped(Double(fileAspect))
        if let cropped { return FilmLabExportPurposeUI.cropLine((1, cropped), of: 1, place: p.name) }
        if displayed.border, p.cropped(Double(aspect)) != nil { return L("With the white border, all of it shows.") }
        if p.fits == nil, aspect > FilmLabPurposeFeed.single.upperBound * 1.01 || aspect < FilmLabPurposeFeed.single.lowerBound / 1.01 {
            return L("Very long pictures show their middle here. A tap shows it whole.")
        }
        return L("All of it shows. Nothing is cropped.")
    }
}

// MARK: - the picture

/// The page's own picture — the develop, Edit's pass over it (its 成片 watermarks), through Edit's crop — filling
/// whatever window a mock-up gives it, and cut by that window. On a white sheet first where 加白边 gave it one.
struct FilmLabPurposeShot {
    let session: OpenFrameSession?
    let frame: LibraryFrame
    /// The picture's shape, width over height.
    let aspect: CGFloat
    /// The white sheet's shape (加白边), nil for none.
    let sheet: CGFloat?
    var pixels: FilmLabExportPreviewPixels? = nil

    /// Only memory already held by the viewer/post. A cold cache uses the ordinary cross-fade instead.
    @MainActor func cachedPixels(model: AppServices) -> FilmLabExportPreviewPixels? {
        let edit = session?.shownEdit ?? frame.edit
        guard let made = session?.developed ?? frame.shownDevelop else { return nil }
        let image: UIImage?
        if let session, edit.finishedActs(isComposite: frame.isComposite), session.layer2.picture != nil, let shown = session.layer2.shown {
            image = UIImage(cgImage: shown)
        } else {
            let ref = session?.developed == nil ? (Layer2Copies.shared.served(frame) ?? made.picture) : made.picture
            image = ThumbnailStore.shared.cachedAny(ref)
        }
        guard let image else { return nil }
        let base = DevelopedFrameView.finishedSize(frame: frame, edit: edit, model: model, developed: session?.developed)
        return FilmLabExportPreviewPixels(image: image,
                                         crop: frame.isPair || edit.printCrop.isIdentity ? nil : edit.printCrop.onFinished(base),
                                         baseSize: base)
    }

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
            Group {
                if let pixels { pixels }
                else if let session { FilmLabPurposeLook(session: session, frame: frame, pointSize: max(width, height)) }
                else { DevelopedFrameView(frame: frame, pointSize: max(width, height)) }
            }
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

/// Logical points: an exact 19.5:9 screen, with an even bezel that is 2.5% of the outer width.
/// Keep these independent of the viewer: only the stage above scales the phone and its entire contents.
enum FilmLabPhoneMetrics {
    static let screenWidth: CGFloat = 402
    static let screenHeight: CGFloat = screenWidth * 19.5 / 9
    static let width: CGFloat = screenWidth / (1 - 2 * 0.025)
    static let bezel: CGFloat = width * 0.025
    static let height: CGFloat = screenHeight + 2 * bezel
    static let radius: CGFloat = width * 0.135
    static let screenRadius: CGFloat = radius - bezel
    static let statusHeight: CGFloat = 54
    static let titleHeight: CGFloat = 44
}

/// The hardware outline only; content is a separate, logical-size screen, ready to host another feed later.
struct FilmLabPhoneFrame<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: FilmLabPhoneMetrics.screenWidth, height: FilmLabPhoneMetrics.screenHeight, alignment: .top)
            .overlay(alignment: .top) {
                Capsule().fill(.black)
                    .frame(width: FilmLabPhoneMetrics.screenWidth * 0.31,
                           height: FilmLabPhoneMetrics.screenHeight * 0.036)
                    .padding(.top, 11)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: FilmLabPhoneMetrics.screenRadius, style: .continuous))
            .padding(FilmLabPhoneMetrics.bezel)
            .background(.black, in: RoundedRectangle(cornerRadius: FilmLabPhoneMetrics.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FilmLabPhoneMetrics.radius, style: .continuous)
                    .strokeBorder(Color(white: 0.42), lineWidth: 1)
            }
            .frame(width: FilmLabPhoneMetrics.width, height: FilmLabPhoneMetrics.height)
    }
}

/// One place's feed, laid out at 402 logical points wide before the whole phone is scaled once.
struct FilmLabPurposeFeed: View {
    let kind: FilmLabExportPurpose.Kind
    let second: Bool
    let dark: Bool
    let name: String
    let shot: FilmLabPurposeShot
    let shots: [FilmLabPurposeShot]
    var showsPhoto = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageID: LibraryFrame.ID?

    private var ids: [LibraryFrame.ID] { shots.map { $0.frame.id } }
    private var page: Int { pageID.flatMap { ids.firstIndex(of: $0) } ?? 0 }
    private var calm: Bool { reduceMotion || FilmLabExportPreviewMotion.calmCheck }
    private var selectionAnimation: Animation {
        calm ? .easeInOut(duration: 0.2)
            : .spring(response: 0.35, dampingFraction: 0.88)
    }
    private var width: CGFloat { FilmLabPhoneMetrics.screenWidth }
    private var height: CGFloat { FilmLabPhoneMetrics.screenHeight }

    /// The shapes one picture alone is shown at in a feed that has no stated range (朋友圈, 微博): a judgement, from
    /// how they look.
    static let single: ClosedRange<CGFloat> = 0.5...2.0

    private var paper: Color { dark ? Color(white: 0.07) : .white }
    private var ink: Color { dark ? Color(white: 0.92) : Color(white: 0.1) }
    private var bar: Color { dark ? Color(white: 0.24) : Color(white: 0.86) }
    private var faint: Color { dark ? Color(white: 0.16) : Color(white: 0.93) }
    private var hairline: Color { dark ? Color(white: 0.18) : Color(white: 0.9) }

    var body: some View {
        // A feed continues below the screen; FilmLabPhoneFrame clips it at the glass, not at a post boundary.
        VStack(spacing: 0) {
            HStack {
                Text("9:41").font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
                Spacer()
            }
            .padding(.horizontal, 27)
            .frame(height: FilmLabPhoneMetrics.statusHeight)
            .background(paper)
            .accessibilityHidden(true)
            // The place's name, in plain text; no platform artwork.
            Text(name).font(.system(size: 17, weight: .semibold)).foregroundStyle(ink)
                .frame(maxWidth: .infinity).frame(height: FilmLabPhoneMetrics.titleHeight)
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
            .frame(minHeight: height - FilmLabPhoneMetrics.statusHeight - FilmLabPhoneMetrics.titleHeight, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: width, height: height, alignment: .top)
        .background(kind == .xiaohongshu && !second ? faint : paper)
        .onChange(of: ids) { _, now in
            if let pageID, !now.contains(pageID) { self.pageID = nil }
        }
        .onChange(of: showsPhoto) { _, visible in
            if !visible { pageID = nil } // the first photo owns the enter/leave move
        }
    }

    /// Anchor the actual post window before the phone is scaled. Only this photo is hidden for the matched move;
    /// the surrounding feed/hardware can fade independently. No picture view is created while merely measuring.
    private func photo(_ width: CGFloat, _ height: CGFloat, radius: CGFloat = 0, bottomRadius: CGFloat = 0,
                       source: FilmLabPurposeShot? = nil) -> some View {
        let source = source ?? shot
        return Color.clear.frame(width: width, height: height)
            .overlay { if showsPhoto { source.filling(width, height) } }
            .anchorPreference(key: FilmLabExportPreviewPhotoKey.self, value: .bounds) {
                source.frame.id == shot.frame.id
                    ? FilmLabExportPreviewPhotoAnchor(bounds: $0, radius: radius, bottomRadius: bottomRadius) : nil
            }
    }

    /// One flat identity domain, even when 3 columns become 2: nested row ForEach would destroy moving cells.
    private func postGrid(_ layout: FilmLabExportPostLayout, cornerRadius: CGFloat = 0) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(shots.prefix(layout.rects.count)), id: \.frame.id) { source in
                let index = ids.firstIndex(of: source.frame.id) ?? 0
                let rect = layout.rects[index]
                photo(rect.width, rect.height, radius: cornerRadius, bottomRadius: cornerRadius, source: source)
                    .overlay {
                        if index == 8, layout.overflow > 0 {
                            Color.black.opacity(0.45)
                            Text("+\(layout.overflow)").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                        }
                    }
                    .offset(x: rect.minX, y: rect.minY)
                    .transition(calm ? .opacity : .opacity.combined(with: .scale(scale: 0.86)))
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .animation(selectionAnimation, value: ids)
    }

    /// Only these three pages have image views/tasks; the rest are IDs and metadata, never decoded here.
    private func carousel(_ w: CGFloat, aspect: CGFloat, radius: CGFloat = 0) -> some View {
        let h = w / aspect
        return VStack(spacing: 0) {
            Color.clear.frame(width: w, height: h)
                .overlay {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(shots.enumerated()).filter { abs($0.offset - page) <= 1 }, id: \.element.frame.id) { item in
                            if showsPhoto {
                                item.element.filling(w, h)
                                    .offset(x: CGFloat(item.offset - page) * w)
                                    .transition(calm ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
                            }
                        }
                    }
                    .frame(width: w, height: h, alignment: .topLeading)
                }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if shots.count > 1 {
                        Text("\(page + 1)/\(shots.count)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule()).padding(9)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in turnPage(point.x < w / 2 ? -1 : 1) }
                // This gesture is attached to the phone's photo only. Vertical drags do not change pages.
                .gesture(DragGesture(minimumDistance: 18).onEnded { drag in
                    let d = drag.translation
                    guard abs(d.width) > abs(d.height), abs(d.width) > 24 else { return }
                    turnPage(d.width < 0 ? 1 : -1)
                })
                .accessibilityLabel(L("Post", as: "export preview"))
                .accessibilityValue("\(page + 1)/\(shots.count)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: turnPage(1)
                    case .decrement: turnPage(-1)
                    @unknown default: break
                    }
                }
                .anchorPreference(key: FilmLabExportPreviewPhotoKey.self, value: .bounds) {
                    FilmLabExportPreviewPhotoAnchor(bounds: $0, radius: radius, bottomRadius: 0)
                }
                .animation(selectionAnimation, value: ids)
                .animation(calm ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3), value: pageID)
            if shots.count > 1 {
                HStack(spacing: 5) {
                    // A sliding window of at most ten indicators keeps the highlighted page visible in long sets.
                    let start = min(max(0, page - 4), max(0, shots.count - 10))
                    ForEach(start..<min(start + 10, shots.count), id: \.self) { i in
                        Circle().fill(i == page ? ink : bar).frame(width: 5, height: 5)
                    }
                }
                .frame(width: w, height: 22)
                .accessibilityHidden(true)
            }
        }
    }

    private func turnPage(_ step: Int) {
        guard showsPhoto, shots.count > 1 else { return }
        let next = min(max(0, page + step), shots.count - 1)
        guard next != page else { return }
        pageID = shots[next].frame.id
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

    /// The profile/second view keeps its placeholders; the chosen photographs occupy its first nine cells.
    private func grid(_ w: CGFloat, tile: CGFloat, gap: CGFloat, rows: Int) -> some View {
        let layout = FilmLabExportPostLayout.grid(count: min(shots.count, 9), side: (w - gap * 2) / 3,
                                                  columns: 3, gap: gap, tile: tile,
                                                  overflow: kind == .weibo ? max(0, shots.count - 9) : 0)
        let side = (w - gap * 2) / 3
        return ZStack(alignment: .topLeading) {
            ForEach(0..<(rows * 3), id: \.self) { i in
                Rectangle().fill((i / 3 + i % 3) % 2 == 0 ? bar : faint)
                    .frame(width: side, height: side / tile)
                    .offset(x: CGFloat(i % 3) * (side + gap), y: CGFloat(i / 3) * (side / tile + gap))
            }
            postGrid(layout)
        }
        .frame(width: w, height: CGFloat(rows) * (side / tile + gap) - gap, alignment: .topLeading)
    }

    // MARK: Instagram

    private var instagramFeed: some View {
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                face(26)
                words(72)
                Spacer()
                symbol("ellipsis", 14)
            }
            .padding(.horizontal, 10).frame(height: 44)
            carousel(width, aspect: FilmLabExportPostLayouts.instagram(aspect: shot.fileAspect))
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
                    postGrid(FilmLabExportPostLayouts.moments(count: shots.count, aspect: shot.fileAspect))
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
                    postGrid(FilmLabExportPostLayouts.weibo(count: shots.count, aspect: shot.fileAspect, width: column),
                             cornerRadius: shots.count == 1 ? 6 : 0)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) {
                cell(w) {
                    // The feed shows the note's first-photo cover; paging belongs to the open note below.
                    let aspect = FilmLabExportPostLayouts.xiaohongshu(aspect: shot.fileAspect)
                    photo(w, w / aspect, radius: 6)
                        .overlay(alignment: .topTrailing) {
                            if shots.count > 1 {
                                Text("1/\(shots.count)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.black.opacity(0.55), in: Capsule()).padding(9)
                            }
                        }
                }
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
            carousel(width, aspect: FilmLabExportPostLayouts.xiaohongshu(aspect: shot.fileAspect))
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

// MARK: - pure post geometry (phone points; no image work)

struct FilmLabExportPostLayout {
    let rects: [CGRect]
    let overflow: Int
    var size: CGSize {
        CGSize(width: rects.map(\.maxX).max() ?? 0, height: rects.map(\.maxY).max() ?? 0)
    }

    static func grid(count: Int, side: CGFloat, columns: Int, gap: CGFloat = 4, tile: CGFloat = 1,
                     overflow: Int = 0) -> Self {
        Self(rects: (0..<max(0, count)).map { i in
            CGRect(x: CGFloat(i % columns) * (side + gap), y: CGFloat(i / columns) * (side / tile + gap),
                   width: side, height: side / tile)
        }, overflow: overflow)
    }
}

enum FilmLabExportPostLayouts {
    static func moments(count: Int, aspect: CGFloat) -> FilmLabExportPostLayout {
        let n = min(max(1, count), 9)
        if n == 1 {
            let a = min(max(aspect, 0.5), 2)
            let box: CGFloat = (402 - 14 - 36 - 10 - 14) * 0.68
            return FilmLabExportPostLayout(rects: [CGRect(x: 0, y: 0, width: a >= 1 ? box : box * a,
                                                          height: a >= 1 ? box / a : box)], overflow: 0)
        }
        // Four stays two 86 pt cells wide; it never expands to fill the post's column.
        return .grid(count: n, side: 86, columns: n == 4 ? 2 : min(n, 3))
    }

    static func weibo(count: Int, aspect: CGFloat, width: CGFloat) -> FilmLabExportPostLayout {
        let n = min(max(1, count), 9)
        if n == 1 {
            let a = min(max(aspect, 0.75), 16.0 / 9.0)
            let w = a >= 1 ? width : width * 0.62
            return FilmLabExportPostLayout(rects: [CGRect(x: 0, y: 0, width: w, height: w / a)], overflow: 0)
        }
        return .grid(count: n, side: (width - 8) / 3, columns: n == 4 ? 2 : min(n, 3),
                     overflow: max(0, count - 9))
    }

    static func instagram(aspect: CGFloat) -> CGFloat { min(max(aspect, 4.0 / 5.0), 1.91) }
    static func xiaohongshu(aspect: CGFloat) -> CGFloat { min(max(aspect, 3.0 / 4.0), 4.0 / 3.0) }
}

// MARK: - coach preference (tests inject a private defaults suite)

struct FilmLabExportCoachPreference {
    static let key = "filmlab.export.previewCoachSeen"
    let defaults: UserDefaults
    let forced: Bool
    var shouldShow: Bool { forced || !defaults.bool(forKey: Self.key) }
    func dismiss() { if !forced { defaults.set(true, forKey: Self.key) } }
}

// MARK: - first preview's hint

private struct FilmLabExportCoachMark: View {
    let calm: Bool
    @State private var bob = false

    var body: some View {
        VStack(spacing: 4) {
            Text(L("Hold ⌘ and pick a few to see them together"))
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color(white: 0.94))
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Color.black.opacity(0.76), in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5) }
            FilmLabExportCoachArrow().stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
                .frame(width: 18, height: 15)
                .offset(y: calm ? 0 : (bob ? 3 : 0))
                .animation(calm ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: bob)
                .accessibilityHidden(true)
        }
        .task(id: calm) {
            bob = false
            guard !calm else { return }
            bob = true
        }
        .accessibilityIdentifier("filmlab.export.preview.coach")
        .allowsHitTesting(false)
    }
}

private struct FilmLabExportCoachArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
