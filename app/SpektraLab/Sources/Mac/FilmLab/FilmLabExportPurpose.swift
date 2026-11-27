//  FilmLabExportPurpose.swift — 普通版's 导出: where the picture is going.
//
//  The owner, 2026-11-25: "导出页面专业和普通没区别啊，普通的应该直接写用途，比方说是朋友圈还是 ins，提供对应预设，最好还能
//  有个阅览图，比方说看看放在 ins 上看是什么效果，还有微博啥的。" So 普通版's 用在哪儿 is six places, not formats:
//  微信朋友圈, Instagram, 微博, 小红书, 发给朋友, 保存到电脑. 专业版 keeps its saved presets and its 文件 rows as they were.
//
//  **A purpose is a fixed recipe** (`FilmLabExportPurpose.recipe`): it is not in the recipe store and it is not
//  `AppSettings.recipe`, so what 普通版 chooses never moves 专业版's recipe, and back. Which purpose is chosen is its own
//  setting (`FilmLabExportPurposeUI.kind`). 存到 and the file's naming stay the shared ones.
//
//  **The numbers** (the owner's `round4/export-sizes.md`, 2026-11-27; evidence and uncertainty are recorded there):
//  - 朋友圈: short edge 1920. Instagram: short edge 1440. Neither enlarges a smaller picture.
//  - 微博: long edge 2048. 小红书: long edge 2560; notes are 3:4 to 4:3.
//  - sRGB and quality 90 for all four. A border's sheet meets the same target, not just the picture on it.
//  - 发给朋友: 24 MP, sRGB, quality 90. 保存到电脑: every pixel, Display P3 (the app's default), quality 100.
//
//  **Nothing is cropped silently.** The export never cuts the picture. Where a place shows only some shapes (`fits`)
//  and a picture is outside them, the chosen card says so over three choices: 原样导出 (the file is the picture; the place
//  crops it when it shows it), 加白边 or 加黑边 (the file is laid on a sheet of the nearest shape the place shows:
//  `FilmLabExportPurposeBorder`). 预览效果 shows which it will be (`FilmLabExportPurposePreview.swift`).

import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FilmLabExportPurpose: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case moments, instagram, weibo, xiaohongshu, friend, computer
    }

    let kind: Kind
    var id: String { kind.rawValue }

    static let all: [FilmLabExportPurpose] = Kind.allCases.map(FilmLabExportPurpose.init(kind:))

    /// The place, as its card names it.
    var name: String {
        switch kind {
        case .moments: L("WeChat Moments")
        case .instagram: "Instagram"
        case .weibo: L("Weibo")
        case .xiaohongshu: L("Xiaohongshu")
        case .friend: L("Send to a Friend")
        case .computer: L("Save to This Mac")
        }
    }

    /// A word after the name where the name alone does not say what the file is: 原图, 最高质量.
    var tag: String? {
        switch kind {
        case .friend: L("Original size")
        case .computer: L("Best quality")
        default: nil
        }
    }

    /// The foot's word for it: "发朋友圈".
    var footName: String {
        switch kind {
        case .moments: L("For Moments")
        case .instagram: L("For Instagram")
        case .weibo: L("For Weibo")
        case .xiaohongshu: L("For Xiaohongshu")
        case .friend, .computer: name
        }
    }

    /// A place with a feed to preview.
    var isSocial: Bool { kind != .friend && kind != .computer }

    /// The shapes (width over height) the place shows whole; a picture outside is cropped there. Nil: any shape.
    var fits: ClosedRange<Double>? {
        switch kind {
        case .instagram: 0.75...1.91
        case .xiaohongshu: 0.75...(4.0 / 3.0)
        default: nil
        }
    }

    /// What the export makes. Fixed ids, so the log names the same recipe in every build.
    var recipe: ExportRecipe {
        func made(_ n: Int, _ size: ExportRecipe.Size, _ colour: ExportRecipe.Colour = .sRGB, _ quality: Int = 90) -> ExportRecipe {
            ExportRecipe(id: UUID(uuidString: "F11B000\(n)-0000-4000-8000-46494C4D4C42")!, title: name, format: .jpeg, size: size,
                         colour: colour, quality: quality)
        }
        switch kind {
        case .moments: return made(1, .shortEdge(1920))
        case .instagram: return made(2, .shortEdge(1440))
        case .weibo: return made(3, .longEdge(2048))
        case .xiaohongshu: return made(4, .longEdge(2560))
        case .friend: return made(5, .megapixels(24))
        case .computer: return made(6, .full, .displayP3, 100)
        }
    }

    /// "2560 px", "全尺寸": the size as the foot says it.
    var sizeWord: String {
        switch recipe.size {
        case .longEdge(let e), .shortEdge(let e): "\(e) px"
        default: recipe.size.shownTitle
        }
    }

    /// "JPEG · 约 2.4 MB": the card and pinned foot share the button's export selection and estimate.
    @MainActor func specs(frameIDs: [LibraryFrame.ID], model: AppServices) -> String {
        FilmLabExportSizeEstimate.summary(recipe, frameIDs: frameIDs, model: model,
                                        borderFits: FilmLabExportPurposeUI.shared.border != .none ? fits : nil)
    }

    /// Which way a picture of shape `aspect` is outside what the place shows: nil where it is shown whole.
    func cropped(_ aspect: Double) -> Cropped? {
        guard let fits else { return nil }
        if aspect > fits.upperBound * 1.01 { return .sides }
        if aspect < fits.lowerBound / 1.01 { return .ends }
        return nil
    }

    enum Cropped { case sides, ends }
}

/// The sheet's colour is a choice; its geometry is identical for white and black.
enum FilmLabExportBorder: String, CaseIterable, Sendable {
    case none, white, black

    var title: String {
        switch self {
        case .none: L("Export As It Is")
        case .white: L("Add a White Border")
        case .black: L("Add a Black Border")
        }
    }

    var colour: Color { self == .black ? .black : .white }
}

/// What 普通版's 导出 column and the preview share: the purpose, the border, the preview's switches.
@MainActor
@Observable
final class FilmLabExportPurposeUI {
    static let shared = FilmLabExportPurposeUI()

    private static let kindKey = "filmlab.export.purpose"
    private static let borderKey = "filmlab.export.purpose.border"

    /// A check's launch may ask for one (`--filmlab-export-purpose instagram`); nothing is kept then.
    /// A check's launch that makes the choices itself keeps none of them.
    private static let checking = CommandLine.arguments.contains("--filmlab-export-border")
        || CommandLine.arguments.contains("--filmlab-export-border-black")
        || CommandLine.arguments.contains("--filmlab-export-walk")
        || CommandLine.arguments.contains("--filmlab-export-preview-toggle")
        || CommandLine.arguments.contains("--filmlab-export-choose-walk")
        || CommandLine.arguments.contains("--filmlab-export-trim")
    private static let asked = FilmLabCheckArgs.value("--filmlab-export-purpose").flatMap(FilmLabExportPurpose.Kind.init(rawValue:))

    var kind: FilmLabExportPurpose.Kind = FilmLabExportPurposeUI.asked
        ?? UserDefaults.standard.string(forKey: FilmLabExportPurposeUI.kindKey).flatMap(FilmLabExportPurpose.Kind.init(rawValue:)) ?? .moments {
        didSet { if Self.asked == nil, !Self.checking { UserDefaults.standard.set(kind.rawValue, forKey: Self.kindKey) } }
    }
    /// The old Bool shares this key: true is white, false (or no setting) is none. New choices are raw strings.
    private static var openingBorder: FilmLabExportBorder {
        if CommandLine.arguments.contains("--filmlab-export-border-black") { return .black }
        if CommandLine.arguments.contains("--filmlab-export-border") { return .white }
        if let raw = UserDefaults.standard.string(forKey: borderKey), let saved = FilmLabExportBorder(rawValue: raw) { return saved }
        return UserDefaults.standard.bool(forKey: borderKey) ? .white : .none
    }
    var border: FilmLabExportBorder = FilmLabExportPurposeUI.openingBorder {
        didSet { if !Self.checking { UserDefaults.standard.set(border.rawValue, forKey: Self.borderKey) } }
    }
    /// 预览效果: the viewer shows the place's mock-up (`FilmLabExportPurposePreview`). Not kept: 导出 opens on the photo.
    var previewing = CommandLine.arguments.contains("--filmlab-export-preview")
    /// The mock-up's second view (主页, 九宫格, 笔记).
    var second = CommandLine.arguments.contains("--filmlab-export-preview-second")
    /// The mock-up's feed in the dark.
    var dark = CommandLine.arguments.contains("--filmlab-export-preview-dark")

    var purpose: FilmLabExportPurpose { FilmLabExportPurpose(kind: kind) }

    /// Reproduce a post mounted after OS-style cache trimming. No render, reload or picture repair here.
    @ObservationIgnored private var trimStarted = false
    func trimIfAsked(model: AppServices) async {
        guard !trimStarted, let seconds = FilmLabCheckArgs.value("--filmlab-export-trim").flatMap(Double.init),
              seconds.isFinite, seconds >= 0 else { return }
        trimStarted = true
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        guard let signals = model.signals else { return }
        signals.deliver(.warning)
        Log.note(.export, "filmlab check trim", ["phase": "pressure", "seconds": seconds])
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        previewing = true
        do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
        var fields: [String: Any] = ["phase": "preview", "picture": "no current session"]
        if case .develop(let frameID)? = MacShellPath.develop(model.router.path),
           let picture = model.openSession(frameID)?.developed?.picture {
            fields["frame"] = frameID.uuidString
            if case .rendered(let id) = picture {
                fields["picture"] = "rendered"
                fields["resolves"] = RenderedPictures.shared.image(id) != nil
            } else {
                fields["picture"] = "not rendered"
            }
        }
        Log.note(.export, "filmlab check trim", fields)
    }

    /// Capture the matched move without clicks. Keep the two-second gaps in slow mode too: a 4× move takes 1.4 s.
    /// Like export-walk, this check never persists its purpose/border choices.
    @ObservationIgnored private var previewToggled = false
    func previewToggleIfAsked() {
        guard !previewToggled,
              let wait = FilmLabCheckArgs.value("--filmlab-export-preview-toggle").flatMap(Double.init),
              wait.isFinite, wait >= 0 else { return }
        previewToggled = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            if !self.purpose.isSocial { self.kind = .moments }
            self.previewing = true
            try? await Task.sleep(for: .seconds(2))
            self.previewing = false
            try? await Task.sleep(for: .seconds(2))
            self.kind = .instagram
            self.previewing = true
            try? await Task.sleep(for: .seconds(2))
            self.second.toggle()
        }
    }

    /// A check's launch only (`--filmlab-export-walk SECONDS`, for `--capture-window`): the choices made one after
    /// another with that long between them, as clicks would make them, so each state can be captured while the app
    /// runs: Instagram, its preview, the second view, the dark feed, 小红书, the white border, the photo back, 保存到电脑.
    @ObservationIgnored private var walked = false
    func walkIfAsked() {
        guard !walked, let step = FilmLabCheckArgs.value("--filmlab-export-walk").flatMap(Double.init) else { return }
        walked = true
        Task { @MainActor in
            let steps: [() -> Void] = [
                { self.kind = .instagram }, { self.previewing = true }, { self.second = true }, { self.dark = true },
                { self.kind = .xiaohongshu }, { self.border = .white }, { self.previewing = false }, { self.kind = .computer },
            ]
            for act in steps {
                try? await Task.sleep(for: .seconds(step))
                withAnimation(.easeOut(duration: 0.2)) { act() }
            }
        }
    }

    /// Preview-only selection walk. The view owns/cancels the task when the preview closes. No frame is opened,
    /// rendered or exported here. Reuse the launch check's existing frame-adoption entry point when necessary;
    /// no image loader or rendering path is introduced for the walk.
    func chooseWalkIfAsked(model: AppServices) async {
        guard let seconds = FilmLabCheckArgs.value("--filmlab-export-choose-walk").flatMap(Double.init),
              seconds.isFinite, seconds > 0 else { return }
        let counts = [2, 3, 4, 1, 4]
        let platforms: [FilmLabExportPurpose.Kind] = [.instagram, .weibo, .xiaohongshu, .moments]
        var step = 0
        var platform = 0
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard previewing, FilmLabFinish.shared.page == .export, purpose.isSocial else { continue }
            guard !model.exporter.isExporting else { continue }
            let store = MacLibraryUI.store(model)
            let rows = Array(FilmLabRollFilterState.shared.apply(store.images, library: model.library).prefix(4))
            guard !rows.isEmpty else { continue }
            if step == counts.count {
                kind = platforms[platform % platforms.count]
                platform += 1
                step = 0
            } else {
                let chosen = Array(rows.prefix(counts[step]))
                let source = store.selectedSourceID, collection = store.selectedCollectionID
                if chosen.contains(where: { $0.develop?.frameID == nil }) {
                    guard (try? await store.frames(for: chosen.map(\.id), focus: nil)) != nil else { continue }
                }
                guard !Task.isCancelled, previewing, FilmLabFinish.shared.page == .export,
                      !model.exporter.isExporting, source == store.selectedSourceID,
                      collection == store.selectedCollectionID else { continue }
                MacLibraryBrowser.shared.selection = Set(chosen.map(\.id))
                step += 1
            }
        }
    }

    /// The recipe 普通版 exports with: the purpose's file, the shared 存到 and naming.
    func recipe(_ settings: AppSettings) -> ExportRecipe {
        var r = purpose.recipe
        r.destination = settings.recipe.destination
        r.naming = settings.recipe.naming
        return r
    }

    /// The shape (width over height) a frame leaves in: its picture as the page shows it, film edge and Edit's crop
    /// with it.
    static func aspect(of id: LibraryFrame.ID, model: AppServices) -> Double? {
        guard let frame = model.library.frame(id) else { return nil }
        if let s = model.openSession(id) {
            return DevelopedFrameView.shownAspect(frame: frame, edit: s.shownEdit, model: model, developed: s.developed)
        }
        return DevelopedFrameView.shownAspect(frame: frame, edit: frame.edit, model: model)
    }

    /// How many of `ids` the purpose's place would crop, and which way the first of them (for the card's line).
    static func cropped(_ ids: [LibraryFrame.ID], by purpose: FilmLabExportPurpose, model: AppServices) -> (count: Int, how: FilmLabExportPurpose.Cropped)? {
        guard purpose.fits != nil else { return nil }
        var count = 0
        var how: FilmLabExportPurpose.Cropped?
        for id in ids {
            guard let a = aspect(of: id, model: model), let c = purpose.cropped(a) else { continue }
            count += 1
            if how == nil { how = c }
        }
        return how.map { (count, $0) }
    }

    /// "这张太宽，Instagram 会裁掉两边。"
    static func cropLine(_ c: (count: Int, how: FilmLabExportPurpose.Cropped), of total: Int, place: String) -> String {
        let line: String
        if total > 1 {
            line = L("\(c.count) of these do not fit. \(place) will crop them.")
        } else {
            switch c.how {
            case .sides: line = L("This one is too wide. \(place) will crop its sides.")
            case .ends: line = L("This one is too tall. \(place) will crop its top and bottom.")
            }
        }
        // A name in Chinese runs on into the Chinese after it; only a Latin one ("Instagram") keeps the space.
        return place.last?.isASCII == false ? line.replacingOccurrences(of: place + " ", with: place) : line
    }
}

// MARK: - the cards

/// 普通版's 用在哪儿: one card a place, the chosen one raised, with its preview and — where the place would crop a picture
/// of this export — the three choices about it.
struct FilmLabExportPurposeCards: View {
    let frameIDs: [LibraryFrame.ID]

    @Environment(AppServices.self) private var model

    private var ui: FilmLabExportPurposeUI { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(FilmLabExportPurpose.all) { p in
                card(p, on: p.kind == ui.kind)
            }
        }
        .padding(.horizontal, 12)
        .task { ui.walkIfAsked() }
    }

    private func card(_ p: FilmLabExportPurpose, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { ui.kind = p.kind }
            } label: {
                HStack(spacing: 12) {
                    FilmLabExportPurposeGlyph(kind: p.kind, on: on)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(p.name).font(Theme.Font.ui(15, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            if let tag = p.tag {
                                Text(tag).font(Theme.Font.ui(12, .medium)).foregroundStyle(on ? Theme.accent : Theme.secondaryText).lineLimit(1)
                            }
                        }
                        Text(p.specs(frameIDs: frameIDs, model: model)).font(Theme.Font.ui(11)).monospacedDigit().foregroundStyle(Theme.dim)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    FilmLabRadioMark(on: on)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("filmlab.export.purpose." + p.id)
            if on, p.isSocial { chosen(p) }
        }
        .background(on ? Theme.card : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(on ? Theme.selectionFrame : Theme.rule, lineWidth: on ? 1.5 : 1))
    }

    /// Under the chosen place's name: what it would crop and the three choices, then 预览效果.
    @ViewBuilder private func chosen(_ p: FilmLabExportPurpose) -> some View {
        @Bindable var ui = ui
        VStack(alignment: .leading, spacing: 8) {
            if let c = FilmLabExportPurposeUI.cropped(frameIDs, by: p, model: model) {
                cropTag(c, place: p.name)
                FilmLabExportBorderSwitch(selection: $ui.border)
                    .accessibilityIdentifier("filmlab.export.purpose.border")
            }
            Button {
                ui.previewing.toggle() // the preview owns the move and retains the phone through its return
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: ui.previewing ? "photo" : "iphone").font(Theme.Font.ui(13, .medium))
                    Text(ui.previewing ? L("Back to the Photo") : L("Preview the Post")).font(Theme.Font.ui(13, .semibold))
                }
                .foregroundStyle(ui.previewing ? Theme.onSelection : Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(ui.previewing ? Theme.selection : Theme.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.rule, lineWidth: ui.previewing ? 0 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .accessibilityIdentifier("filmlab.export.purpose.preview")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private func cropTag(_ c: (count: Int, how: FilmLabExportPurpose.Cropped), place: String) -> some View {
        let protected = ui.border != .none
        let title = protected ? L("Not cropped") : frameIDs.count > 1
            ? String(format: L("%lld will be cropped"), Int64(c.count))
            : (c.how == .sides ? L("Sides get cropped") : L("Top and bottom get cropped"))
        return ZStack(alignment: .leading) {
            HStack(spacing: 4) {
                Image(systemName: protected ? "checkmark" : "exclamationmark")
                Text(title)
            }
            .font(Theme.Font.ui(11, .semibold))
            .foregroundStyle(protected ? Theme.secondaryText : Color.white)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(protected ? Theme.secondaryText.opacity(0.1) : Color(red: 0.78, green: 0.15, blue: 0.15), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .id(protected)
            .transition(.opacity)
        }
        .frame(height: 22, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: protected)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("filmlab.export.purpose.crop")
        .accessibilityLabel(Text(FilmLabExportPurposeUI.cropLine(c, of: frameIDs.count, place: place)))
        .accessibilityValue(Text(title))
    }
}

/// SegmentedSwitch's same thumb and tap animation, with widths that fit all three full English labels at 12.5 pt.
/// At the 393 pt column minimum there are 349 pt here (393 − 2×12 − 2×10). Each label gets 4 pt per side;
/// the remaining width is shared. Measure semibold for every segment so selecting one cannot move its neighbours.
private struct FilmLabExportBorderSwitch: View {
    @Binding var selection: FilmLabExportBorder
    @Namespace private var thumb

    var body: some View {
        let options = FilmLabExportBorder.allCases
        let titles = options.map(\.title)
        let font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        let widths = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 8 }
        GeometryReader { room in
            let extra = max(0, (room.size.width - widths.reduce(0, +)) / CGFloat(options.count))
            HStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { i in
                    let option = options[i]
                    let on = option == selection
                    Text(titles[i])
                        .font(Theme.Font.ui(12.5, on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.onSelection : Theme.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: widths[i] + extra, height: 30)
                        .background {
                            if on {
                                Capsule().fill(Theme.selection).padding(2)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !on else { return }
                            withAnimation(.easeOut(duration: 0.15)) { selection = option }
                        }
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
            .background(Capsule().fill(Theme.background))
        }
        .frame(height: 30)
    }
}

/// A place's shape, drawn small: nine squares, a tall post, a post with words over it, two uneven columns. No logos.
struct FilmLabExportPurposeGlyph: View {
    let kind: FilmLabExportPurpose.Kind
    let on: Bool

    var body: some View {
        let ink = on ? Theme.accent : Theme.secondaryText
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Theme.background : Theme.card)
            switch kind {
            case .moments:
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in block(6.5, 6.5) } }
                    }
                }
            case .instagram:
                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 2.5) { Circle().frame(width: 4.5, height: 4.5); block(9, 2.5).opacity(0.6) }
                    block(18, 22.5)
                }
            case .weibo:
                VStack(alignment: .leading, spacing: 2.5) {
                    block(20, 2.5).opacity(0.6)
                    block(13, 2.5).opacity(0.6)
                    block(22, 13)
                }
            case .xiaohongshu:
                HStack(alignment: .top, spacing: 2.5) {
                    VStack(spacing: 2.5) { block(10, 15); block(10, 7) }
                    VStack(spacing: 2.5) { block(10, 8); block(10, 14) }
                }
            case .friend:
                Image(systemName: "paperplane").font(Theme.Font.ui(17, .medium))
            case .computer:
                Image(systemName: "desktopcomputer").font(Theme.Font.ui(17, .medium))
            }
        }
        .foregroundStyle(ink)
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    private func block(_ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous).frame(width: w, height: h)
    }
}

// MARK: - the border

/// 加白边 / 加黑边: after the exporter has saved a picture the place would crop, its file is laid on a sheet of the nearest
/// shape the place shows, and written over itself.
///
/// A step after the export, not inside it: the exporter is not asked for anything new, and a picture that already fits
/// is never touched. The saved JPEG is read once and written once more at the same quality, with its profile and its
/// EXIF. Margins start at multiples of 16 px; if the sheet exceeds the recipe's target, picture and margins shrink
/// together in the same draw/encode. A gain map (an HDR frame's) does not survive it.
@MainActor
enum FilmLabExportPurposeBorder {
    private static var task: Task<Void, Never>?

    /// Follows `run`'s batch: each picture saved is given its border where it needs one.
    static func follow(_ run: MacExportRun, fits: ClosedRange<Double>, quality: Int, border: FilmLabExportBorder, size: ExportRecipe.Size) {
        task?.cancel()
        task = Task { @MainActor in
            var seen = Set<Int>()
            while !Task.isCancelled {
                let ended = !run.isRunning
                for line in run.lines where !seen.contains(line.id) {
                    guard case .saved(let url) = line.state else { continue }
                    seen.insert(line.id)
                    let folder = run.folder
                    let padded = await Task.detached(priority: .userInitiated) {
                        let scoped = folder?.startAccessingSecurityScopedResource() ?? false
                        defer { if scoped { folder?.stopAccessingSecurityScopedResource() } }
                        return pad(url, fits: fits, quality: quality, border: border, size: size)
                    }.value
                    if padded { Log.note(.export, "filmlab border", ["file": url.lastPathComponent]) }
                }
                if ended { break }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    /// The sheet a `width` × `height` picture is laid on so its shape is inside `fits`; nil where it already is.
    nonisolated static func sheet(width w: Int, height h: Int, fits: ClosedRange<Double>) -> (width: Int, height: Int)? {
        guard w > 0, h > 0 else { return nil }
        let a = Double(w) / Double(h)
        func margin(_ need: Int) -> Int { ((need + 1) / 2 + 15) / 16 * 16 }
        if a > fits.upperBound * 1.01 {
            return (w, h + 2 * margin(Int((Double(w) / fits.upperBound).rounded(.up)) - h))
        }
        if a < fits.lowerBound / 1.01 {
            return (w + 2 * margin(Int((Double(h) * fits.lowerBound).rounded(.up)) - w), h)
        }
        return nil
    }

    /// Size the whole sheet, never up: the encoder and the estimate share these final pixels and placement.
    nonisolated static func layout(width w: Int, height h: Int, fits: ClosedRange<Double>, size: ExportRecipe.Size)
        -> (sheet: PixelSize, picture: CGRect)? {
        guard let base = sheet(width: w, height: h, fits: fits) else { return nil }
        let whole = PixelSize(width: base.width, height: base.height)
        let final: PixelSize
        switch size {
        case .shortEdge(let e): final = whole.scaled(toShortEdge: e)
        case .longEdge(let e): final = whole.scaled(toLongEdge: e)
        case .megapixels(let mp): final = whole.scaled(toMegapixels: mp)
        case .full, .preview: final = whole
        }
        let scale = min(CGFloat(final.width) / CGFloat(whole.width), CGFloat(final.height) / CGFloat(whole.height))
        let picture = CGSize(width: CGFloat(w) * scale, height: CGFloat(h) * scale)
        return (final, CGRect(x: (CGFloat(final.width) - picture.width) / 2, y: (CGFloat(final.height) - picture.height) / 2,
                              width: picture.width, height: picture.height))
    }

    /// True where the file was given a border.
    nonisolated static func pad(_ url: URL, fits: ClosedRange<Double>, quality: Int, border: FilmLabExportBorder = .white,
                                size: ExportRecipe.Size = .full) -> Bool {
        guard border != .none, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        // A turned file's width is not its picture's: left as it is (the exporter writes them upright).
        if let turn = properties[kCGImagePropertyOrientation] as? Int, turn != 1 { return false }
        guard let layout = layout(width: image.width, height: image.height, fits: fits, size: size) else { return false }
        let sheet = layout.sheet
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? srgb
        guard let context = CGContext(data: nil, width: sheet.width, height: sheet.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        let level: CGFloat = border == .black ? 0 : 1
        context.setFillColor(CGColor(colorSpace: space, components: [level, level, level, 1]) ?? CGColor(gray: level, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
        context.interpolationQuality = layout.picture.width < CGFloat(image.width) ? .high : .none
        context.draw(image, in: layout.picture)
        guard let made = context.makeImage() else { return false }
        // The sheet's size is the file's now.
        properties[kCGImagePropertyPixelWidth] = nil
        properties[kCGImagePropertyPixelHeight] = nil
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = nil
            exif[kCGImagePropertyExifPixelYDimension] = nil
            properties[kCGImagePropertyExifDictionary] = exif
        }
        properties[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 100
        let part = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).spkpart")
        guard let destination = CGImageDestinationCreateWithURL(part as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, made, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: part)
            return false
        }
        // Over the picture's own file, whole or not at all.
        guard rename(part.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: part)
            return false
        }
        return true
    }
}
