//  ExportModeSection.swift — FilmLab's 导出 mode: the export's own settings and its button, under the format.
//
//  The owner (FilmLab, 2026-11-22): "把格式放在冲洗后，写为导出。在导出页面统一进行导出操作". The window's mode row is
//  图库 · 冲洗 · 导出; 导出 is the develop page on its Format step, and this section over the format holds what the
//  Export page's column holds — Recipe, Format, Quality, Size, Colour, Save to — and runs the batch itself
//  (`MacExportRun`, as `MacExportPage` runs it), so nothing about a file is decided anywhere else.
//
//  The recipe is the one Settings keeps (`AppSettings.recipe`): what is chosen here is what the next export uses, and
//  what the full Export page opens with.

import SwiftUI

struct ExportModeSection: View {
    /// The pictures the button exports: the develop page's (`DevelopWorkspace.exportIDs`).
    let frameIDs: [LibraryFrame.ID]

    @Environment(AppSettings.self) private var settings
    @Environment(ExportService.self) private var exporter
    @Environment(ExportRecipeStore.self) private var recipes

    @State private var folder: URL? = MacExportFolder.saved()
    @State private var picking = false
    @State private var startsAfterPicking = false
    @State private var refused: String?

    private var run: MacExportRun { .shared }
    private var busy: Bool { run.isRunning || exporter.isExporting }

    /// The kept recipe, named as the saved one it matches (as the Export page opens it).
    private var recipe: Binding<ExportRecipe> {
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

    /// The sizes offered here: the original's own, two pixel counts and three long edges; a custom size a recipe
    /// already has stays in the list.
    private func sizes(_ current: ExportRecipe.Size) -> [ExportRecipe.Size] {
        var list: [ExportRecipe.Size] = [.full, .megapixels(24), .megapixels(12), .longEdge(4096), .longEdge(2048), .longEdge(1080)]
        if !list.contains(current), current != .preview { list.append(current) }
        return list
    }

    /// Design A (2026-11-24): the column's sections fold like 冲洗's, each saying what it is set to in its header.
    @AppStorage("filmlab.export.fold.presets") private var presetsFolded = false
    @AppStorage("filmlab.export.fold.file") private var fileFolded = false
    @AppStorage("filmlab.export.fold.save") private var saveFolded = false

    var body: some View {
        let recipe = self.recipe
        let r = recipe.wrappedValue
        VStack(alignment: .leading, spacing: 0) {
            // 普通版 (FilmLab): Format, Quality, Size and Save to; the saved recipes and the colour space are 专业版's.
            if !FeatureFlags.simpleWindow {
                ColumnSectionHeader(title: L("Presets"), folded: presetsFolded, id: "export.presets",
                                    value: r.name) { presetsFolded.toggle() }
                if !presetsFolded {
                    RecipeChips(recipe: recipe, admit: { ExportRecipe.opening($0) }, wraps: true, small: true)
                        .padding(.top, 2).padding(.bottom, 14)
                }
            }
            ColumnSectionHeader(title: L("File"), folded: fileFolded, id: "export.file",
                                value: r.builtName + Fmt.dot + sizeTitle(r.size)) { fileFolded.toggle() }
            if !fileFolded {
                VStack(spacing: 0) {
                    ExportRow(label: L("Format"), height: 42) { FormatSwitch(recipe: recipe) }.modifier(Separated())
                    QualitySliderRow(recipe: recipe).modifier(Separated())
                    ExportRow(label: L("Size"), height: 42) {
                        Menu {
                            ForEach(sizes(r.size), id: \.self) { size in
                                Button(sizeTitle(size)) { recipe.wrappedValue.size = size }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(sizeTitle(r.size)).font(Theme.Font.ui(13, .medium)).foregroundStyle(Theme.text)
                                Image(systemName: "chevron.up.chevron.down").font(Theme.Font.ui(10, .semibold)).foregroundStyle(Theme.dim)
                            }
                        }
                        .menuIndicator(.hidden)
                        .accessibilityIdentifier("filmlab.export.size")
                    }
                    .modifier(FeatureFlags.simpleWindow ? Separated(shown: false) : Separated())
                    if !FeatureFlags.simpleWindow { ColourRow(recipe: recipe) }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 8)
            }
            ColumnSectionHeader(title: L("Save to"), folded: saveFolded, id: "export.save",
                                value: r.destination == .files ? folder.map { MacExportFolder.place($0) } : r.destination.shownTitle) {
                saveFolded.toggle()
            }
            if !saveFolded {
                VStack(alignment: .leading, spacing: 8) {
                    SegmentedSwitch(options: ExportRecipe.Destination.allCases, selection: recipe.destination,
                                    title: \.shownTitle, height: 28, track: Theme.card)
                    if r.destination == .files { folderField }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            footer(r)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            FoldRule()
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            let begins = startsAfterPicking
            startsAfterPicking = false
            guard case .success(let url) = result else { return }
            folder = url
            MacExportFolder.remember(url)
            if begins { start(recipe.wrappedValue, folder: url) }
        }
    }

    /// 存到: the folder in a well-coloured field, 更改 beside it (design A).
    private var folderField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(Theme.Font.ui(12)).foregroundStyle(Theme.dim)
                Text(folder.map { MacExportFolder.place($0) } ?? L("No folder yet"))
                    .font(Theme.Font.ui(12)).foregroundStyle(folder == nil ? Theme.dim : Theme.text)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
            Button { startsAfterPicking = false; picking = true } label: {
                Text(folder == nil ? L("Choose…") : L("Change…")).font(Theme.Font.ui(12, .medium)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("filmlab.export.folder")
        }
    }

    /// The column's one big action: amber, squared like the bar's 导出 (design A), not a capsule.
    private func exportButton(_ title: String, primary: Bool = true, enabled: Bool = true,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if primary { Image(systemName: "square.and.arrow.up").font(Theme.Font.ui(13, .semibold)) }
                Text(title).font(Theme.Font.ui(13.5, .semibold))
            }
            .foregroundStyle(primary ? Theme.onSelection : Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(primary ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    @ViewBuilder private func footer(_ recipe: ExportRecipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if run.isRunning || run.isFinished {
                HStack(spacing: 8) {
                    if run.isRunning { ProgressView(value: run.fraction).tint(Theme.accent) }
                    Text(run.isRunning ? run.countText : L("\(run.saved) saved"))
                        .font(Theme.Font.ui(12, .medium)).foregroundStyle(Theme.secondaryText)
                        .fixedSize()
                }
                ForEach(run.problems, id: \.id) { line in
                    Text(line.name + Fmt.dot + L(shown: line.problem ?? ""))
                        .font(Theme.Font.ui(11.5)).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let refused {
                Text(refused).font(Theme.Font.ui(12, .medium)).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if busy {
                exportButton(L("Stop"), primary: false) { run.stop() }
                    .accessibilityIdentifier("filmlab.export.stop")
            } else {
                exportButton(frameIDs.count > 1 ? L("Export \(frameIDs.count) Pictures") : L("Export"),
                             enabled: !frameIDs.isEmpty) { start(recipe) }
                    .accessibilityIdentifier("filmlab.export.go")
            }
        }
    }

    private func sizeTitle(_ size: ExportRecipe.Size) -> String {
        switch size {
        case .longEdge(let e): L("Long edge \(e)")
        default: size.shownTitle
        }
    }

    private func start(_ recipe: ExportRecipe, folder chosen: URL? = nil) {
        refused = nil
        let folder = chosen ?? self.folder
        // Files with no folder yet (or one that has gone): Finder's panel first, then the batch.
        if recipe.destination == .files, folder.map({ FileManager.default.fileExists(atPath: $0.path) }) != true {
            startsAfterPicking = true
            picking = true
            return
        }
        settings.recipe = recipe
        if !run.start(frameIDs, recipe: recipe, folder: folder, exporter: exporter) {
            refused = L("The export could not begin. Try again in a moment.")
        }
    }
}

private struct Separated: ViewModifier {
    var shown = true
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) { if shown { RowSeparator(leading: 14).offset(y: 0.5) } }
    }
}
