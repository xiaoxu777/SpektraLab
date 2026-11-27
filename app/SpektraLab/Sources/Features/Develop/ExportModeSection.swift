//  ExportModeSection.swift — FilmLab's 导出 mode: how the photo leaves the app, in the order it is done.
//
//  The owner (FilmLab, 2026-11-22): "把格式放在冲洗后，写为导出。在导出页面统一进行导出操作". The window's mode row is
//  图库 · 冲洗 · 导出; 导出 is the develop page on its Format step, and its column holds what the Export page's column holds
//  and runs the batch itself (`MacExportRun`, as `MacExportPage` runs it), so nothing about a file is decided elsewhere.
//
//  Redone 2026-11-24 (the owner: "左侧栏设计逻辑有问题。导出按钮应该在最下面。左侧预设按钮并没有做到预设本身的便利性，用户
//  不会去看这些小方块。视觉上就要对"). The column, top to bottom:
//  - `.presets`: what the photo is for — one card per saved recipe (`RecipeChips(cards:)`), the main choice here;
//  - `.details`: 文件 (format, quality, size, colour; folded, the preset set them) and 存到;
//  - `FilmLabExportFooter`, outside the column's scroll: what will be made and where, over the one amber 导出.
//  2026-11-25 ("导出界面只做导出"): the film edge, the date back and the watermark are 个性化's, the mode before this one
//  (`FilmLabPersonalizeColumn`); the foot names which of them the export carries, and while a batch runs it is the
//  tray the pictures land in (`FilmLabExportAnimation.swift`).
//
//  The recipe is the one Settings keeps (`AppSettings.recipe`): what is chosen here is what the next export uses, and
//  what the full Export page opens with.
//
//  2026-11-25, later ("导出页面专业和普通没区别啊，普通的应该直接写用途"): that column is 专业版's. In 普通版 `.presets` is where
//  the picture is going (`FilmLabExportPurposeCards`: 朋友圈, Instagram, 微博, 小红书, 发给朋友, 保存到电脑), there is no 文件
//  (the purpose decides it), and the foot names the purpose. The purpose's recipe is its own
//  (`FilmLabExportPurposeUI.recipe`): `AppSettings.recipe` stays 专业版's, but for 存到 and the naming, which both share.

import SwiftUI

/// What the parts of the 导出 column share: the folder, Finder's panel, and why a start was refused.
@MainActor
@Observable
final class FilmLabExportUI {
    static let shared = FilmLabExportUI()
    /// A check's launch (`--filmlab-export-folder <path>`): that folder for this run, the kept one untouched.
    var folder: URL? = FilmLabCheckArgs.value("--filmlab-export-folder").map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? MacExportFolder.saved()
    var picking = false
    var startsAfterPicking = false
    var refused: String?
}

/// The kept recipe, named as the saved one it matches (as the Export page opens it).
@MainActor
enum FilmLabExportRecipe {
    static func binding(_ settings: AppSettings, _ recipes: ExportRecipeStore) -> Binding<ExportRecipe> {
        Binding(get: {
            var r = ExportRecipe.opening(settings.recipe)
            if let saved = recipes.saved(as: r)
                ?? recipes.recipes.first(where: { ExportRecipe.opening($0).sameSettings(as: r) }) {
                r.id = saved.id
                r.title = saved.title
            }
            return r
        }, set: { settings.recipe = $0 })
    }

    static func sizeTitle(_ size: ExportRecipe.Size) -> String {
        switch size {
        case .longEdge(let e): L("Long edge \(e)")
        case .shortEdge(let e): L("Short edge \(e)")
        default: size.shownTitle
        }
    }

    /// What 个性化 has on for the pictures an export takes, in one line under the summary so nothing is a surprise:
    /// "带片边 · 日期 · 水印"; "部分" before it where only some of a batch have any. Nil where none has.
    static func extras(of ids: [LibraryFrame.ID], model: AppServices) -> String? {
        var edge = 0, date = 0, mark = 0
        for id in ids {
            guard let e = model.openSession(id)?.edit ?? model.library.frame(id)?.edit else { continue }
            if e.filmEdge.effective, e.appliesFilm { edge += 1 }
            if FeatureFlags.dateBack, e.dateBack.active, e.appliesFilm, !FilmEdgeOptions.printsNothing(e.dateBack, e.filmEdge) { date += 1 }
            if e.watermarks.contains(where: \.on) { mark += 1 }
        }
        var words: [String] = []
        if edge > 0 { words.append(L("Film edge", as: "the export has one")) }
        if date > 0 { words.append(L("Date", as: "the export has one")) }
        if mark > 0 { words.append(L("Watermark")) }
        guard !words.isEmpty else { return nil }
        let some = ids.count > 1 && [edge, date, mark].contains { $0 > 0 && $0 < ids.count }
        let list = words.joined(separator: Fmt.dot)
        return some ? L("Some with \(list)") : L("With \(list)", as: "the export carries")
    }

    /// "TIFF 16-bit · ProPhoto · Full", and the quality where the format takes one.
    static func specs(_ r: ExportRecipe) -> String {
        var parts = [r.format.title, r.colour.rawValue, sizeTitle(r.size)]
        if r.format.takesQuality { parts.append(L("Quality \(r.quality)")) }
        return parts.joined(separator: Fmt.dot)
    }
}

struct ExportModeSection: View {
    enum Part { case presets, details }

    /// The pictures the button exports: the develop page's (`DevelopWorkspace.exportIDs`).
    let frameIDs: [LibraryFrame.ID]
    var part: Part = .presets

    @Environment(AppSettings.self) private var settings
    @Environment(ExportRecipeStore.self) private var recipes

    private var ui: FilmLabExportUI { .shared }

    /// The sizes offered here: the original's own, two pixel counts and three long edges; a custom size a recipe
    /// already has stays in the list.
    private func sizes(_ current: ExportRecipe.Size) -> [ExportRecipe.Size] {
        var list: [ExportRecipe.Size] = [.full, .megapixels(24), .megapixels(12), .longEdge(4096), .longEdge(2048), .longEdge(1080)]
        if !list.contains(current), current != .preview { list.append(current) }
        return list
    }

    /// The sections fold like 冲洗's, each saying what it is set to in its header. 文件 starts folded: the preset set it.
    @AppStorage("filmlab.export.fold.presets") private var presetsFolded = false
    @AppStorage("filmlab.export.fold.file2") private var fileFolded = true
    @AppStorage("filmlab.export.fold.save") private var saveFolded = false

    var body: some View {
        switch part {
        case .presets: presets
        case .details: details
        }
    }

    // MARK: 用途

    private var presets: some View {
        let recipe = FilmLabExportRecipe.binding(settings, recipes)
        let simple = FeatureFlags.simpleWindow
        return VStack(alignment: .leading, spacing: 0) {
            ColumnSectionHeader(title: L("What is it for?"), folded: presetsFolded, id: "export.presets", rule: false,
                                value: presetsFolded ? (simple ? FilmLabExportPurposeUI.shared.purpose.name : recipe.wrappedValue.name) : nil) {
                presetsFolded.toggle()
            }
            if !presetsFolded {
                if simple {
                    // 普通版: where it is going, not what format it is (`FilmLabExportPurpose.swift`).
                    FilmLabExportPurposeCards(frameIDs: frameIDs)
                        .padding(.top, 2).padding(.bottom, 10)
                } else {
                    RecipeChips(recipe: recipe, admit: { ExportRecipe.opening($0) }, wraps: true, cards: true)
                        .padding(.top, 2).padding(.bottom, 14)
                }
            }
        }
        // 预览效果 is this column's: leaving 导出 puts the photo back.
        .onDisappear { FilmLabExportPurposeUI.shared.previewing = false }
    }

    // MARK: 文件 and 存到

    private var details: some View {
        @Bindable var ui = ui
        let recipe = FilmLabExportRecipe.binding(settings, recipes)
        let r = recipe.wrappedValue
        // 普通版 has no 文件: the purpose decides the file, and says what it is on its card.
        let simple = FeatureFlags.simpleWindow
        return VStack(alignment: .leading, spacing: 0) {
            if !simple {
                ColumnSectionHeader(title: L("File"), folded: fileFolded, id: "export.file",
                                    value: FilmLabExportRecipe.specs(r)) { fileFolded.toggle() }
            }
            if !simple, !fileFolded {
                VStack(spacing: 0) {
                    ExportRow(label: L("Format"), height: 42) { FormatSwitch(recipe: recipe) }.modifier(Separated())
                    QualitySliderRow(recipe: recipe).modifier(Separated())
                    ExportRow(label: L("Size"), height: 42) {
                        Menu {
                            ForEach(sizes(r.size), id: \.self) { size in
                                Button(FilmLabExportRecipe.sizeTitle(size)) { recipe.wrappedValue.size = size }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(FilmLabExportRecipe.sizeTitle(r.size)).font(Theme.Font.ui(13, .medium)).foregroundStyle(Theme.text)
                                Image(systemName: "chevron.up.chevron.down").font(Theme.Font.ui(10, .semibold)).foregroundStyle(Theme.dim)
                            }
                        }
                        .menuIndicator(.hidden)
                        .accessibilityIdentifier("filmlab.export.size")
                    }
                    .modifier(Separated())
                    ColourRow(recipe: recipe)
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 8)
            }
            ColumnSectionHeader(title: L("Save to"), folded: saveFolded, id: "export.save",
                                value: r.destination == .files ? ui.folder.map { MacExportFolder.place($0) } : r.destination.shownTitle) {
                saveFolded.toggle()
            }
            if !saveFolded {
                VStack(alignment: .leading, spacing: 8) {
                    SegmentedSwitch(options: ExportRecipe.Destination.allCases, selection: recipe.destination,
                                    title: \.shownTitle, height: 28, track: Theme.card)
                    if r.destination == .files { folderField }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    /// 存到: the folder in a well-coloured field, 更改 beside it.
    private var folderField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(Theme.Font.ui(12)).foregroundStyle(Theme.dim)
                Text(ui.folder.map { MacExportFolder.place($0) } ?? L("No folder yet"))
                    .font(Theme.Font.ui(12)).foregroundStyle(ui.folder == nil ? Theme.dim : Theme.text)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
            Button { ui.startsAfterPicking = false; ui.picking = true } label: {
                Text(ui.folder == nil ? L("Choose…") : L("Change…")).font(Theme.Font.ui(12, .medium)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("filmlab.export.folder")
        }
    }
}

/// The 导出 column's foot, pinned under its scroll (the owner: "导出按钮应该在最下面"): what will be made and where, how many,
/// then the one amber 导出; while the batch runs, its progress, its problems and Stop in the button's place.
struct FilmLabExportFooter: View {
    let frameIDs: [LibraryFrame.ID]

    @Environment(AppSettings.self) private var settings
    @Environment(ExportService.self) private var exporter
    @Environment(ExportRecipeStore.self) private var recipes
    @Environment(AppServices.self) private var model

    private var ui: FilmLabExportUI { .shared }
    private var run: MacExportRun { .shared }
    private var busy: Bool { run.isRunning || exporter.isExporting || FilmLabExportShow.shared.running }

    var body: some View {
        @Bindable var ui = ui
        let r = recipeNow
        let show = FilmLabExportShow.shared
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if show.hasRun {
                    FilmLabExportTray()
                } else {
                    summary(r)
                }
            }
            .frame(height: 72, alignment: .leading)
            .transition(.opacity)
            // Animate this content only. Animating the whole foot also interpolated the Stop/Export fill,
            // briefly turning amber brown when the export finished.
            .animation(FilmLabExportMotion.fade(0.2), value: show.hasRun)
            if let refused = ui.refused {
                Text(refused).font(Theme.Font.ui(12, .medium)).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if busy {
                button(L("Stop"), primary: false) {
                    show.requestStop()
                    if show.demo { FilmLabExportCheck.stop() } else { run.stop() }
                }
                    .accessibilityIdentifier("filmlab.export.stop")
            } else {
                button(frameIDs.count > 1 ? L("Export \(frameIDs.count) Pictures") : L("Export"),
                       enabled: !frameIDs.isEmpty) { start(r) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("filmlab.export.go")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
        .fileImporter(isPresented: $ui.picking, allowedContentTypes: [.folder]) { result in
            let begins = ui.startsAfterPicking
            ui.startsAfterPicking = false
            guard case .success(let url) = result else { return }
            ui.folder = url
            MacExportFolder.remember(url)
            if begins { start(r, folder: url) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmlab.export.footer")
        .task {
            FilmLabExportCheck.launch(model: model, current: frameIDs.first) { chosen in
                guard !busy, let current = frameIDs.first else { return }
                start(recipeNow, checkFrames: chosen ?? MacDevelopExport.ids(current: current, model: model))
            }
        }
    }

    /// What the button exports with: 专业版's kept recipe, or in 普通版 the chosen purpose's (`FilmLabExportPurposeUI`).
    private var recipeNow: ExportRecipe {
        FeatureFlags.simpleWindow ? FilmLabExportPurposeUI.shared.recipe(settings)
                                  : FilmLabExportRecipe.binding(settings, recipes).wrappedValue
    }

    /// 普通版: the purpose whose place would crop a picture of this export, where 加白边 was chosen for it.
    private var bordered: FilmLabExportPurpose? {
        guard FeatureFlags.simpleWindow, FilmLabExportPurposeUI.shared.border else { return nil }
        let p = FilmLabExportPurposeUI.shared.purpose
        return FilmLabExportPurposeUI.cropped(frameIDs, by: p, model: model) != nil ? p : nil
    }

    /// The summary's first line: "TIFF 16-bit · ProPhoto · Full", or in 普通版 "JPEG · 约 2.4 MB".
    private func headline(_ r: ExportRecipe) -> String {
        guard FeatureFlags.simpleWindow else { return FilmLabExportRecipe.specs(r) }
        return FilmLabExportPurposeUI.shared.purpose.specs(frameIDs: frameIDs, model: model)
    }

    /// "TIFF 16-bit · ProPhoto · Full" over "→ ericxu › Desktop", the count at the right.
    private func summary(_ r: ExportRecipe) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline(r)).font(Theme.Font.ui(12, .medium)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .accessibilityIdentifier("filmlab.export.headline")
                HStack(spacing: 4) {
                    Image(systemName: r.destination == .files ? "folder" : "square.and.arrow.up").font(Theme.Font.ui(10.5))
                    Text(r.destination == .files ? (ui.folder.map { MacExportFolder.place($0) } ?? L("No folder yet"))
                                                 : r.destination.shownTitle)
                        .lineLimit(1).truncationMode(.middle)
                }
                .font(Theme.Font.ui(11.5)).foregroundStyle(Theme.dim)
                if let extras = FilmLabExportRecipe.extras(of: frameIDs, model: model) {
                    Text(extras).font(Theme.Font.ui(11.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        .accessibilityIdentifier("filmlab.export.extras")
                }
            }
            Spacer(minLength: 6)
            Text(frameIDs.count == 1 ? L("1 photo") : L("\(frameIDs.count) photos")).font(Theme.Font.ui(12, .semibold)).monospacedDigit()
                .foregroundStyle(Theme.secondaryText).fixedSize()
        }
    }

    /// The column's one big action: amber, squared like the bar's 导出.
    private func button(_ title: String, primary: Bool = true, enabled: Bool = true,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if primary { Image(systemName: "square.and.arrow.up").font(Theme.Font.ui(14, .semibold)) }
                Text(title).font(Theme.Font.ui(14, .semibold))
            }
            .foregroundStyle(primary ? Theme.onSelection : Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(primary ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .transaction { $0.animation = nil }
    }

    private func start(_ recipe: ExportRecipe, folder chosen: URL? = nil, checkFrames: [LibraryFrame.ID]? = nil) {
        let frameIDs = checkFrames ?? self.frameIDs
        ui.refused = nil
        let folder = chosen ?? ui.folder
        // Files with no folder yet (or one that has gone): Finder's panel first, then the batch.
        if recipe.destination == .files, folder.map({ FileManager.default.fileExists(atPath: $0.path) }) != true {
            ui.startsAfterPicking = true
            ui.picking = true
            return
        }
        // A check's export leaves the kept recipe as it is (it is the same one unless the check chose another); so does
        // 普通版's, whose recipe is its purpose's and not the kept one.
        if FilmLabCheckArgs.value("--filmlab-export-folder") == nil, !FeatureFlags.simpleWindow { settings.recipe = recipe }
        let border = bordered
        FilmLabExportShow.shared.reset()
        if !run.start(frameIDs, recipe: recipe, folder: folder, exporter: exporter) {
            ui.refused = L("The export could not begin. Try again in a moment.")
        } else if let border, let fits = border.fits {
            // 加白边: each picture the place would crop is laid on its white sheet as it is saved.
            FilmLabExportPurposeBorder.follow(run, fits: fits, quality: recipe.quality)
        }
    }
}

private struct Separated: ViewModifier {
    var shown = true
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) { if shown { RowSeparator(leading: 14).offset(y: 0.5) } }
    }
}
