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

    var body: some View {
        let recipe = self.recipe
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(L("Export")).padding(.horizontal, 16).padding(.top, 12)
            // 普通版 (FilmLab): Format, Quality, Size and Save to; the saved recipes and the colour space are 专业版's.
            if !FeatureFlags.simpleWindow {
                RecipeChips(recipe: recipe, admit: { ExportRecipe.opening($0) }, wraps: true)
                    .padding(.top, 8)
            }
            GroupBox(radius: 12) {
                ExportRow(label: L("Format"), height: 42) { FormatSwitch(recipe: recipe) }.modifier(Separated())
                QualitySliderRow(recipe: recipe).modifier(Separated())
                ExportRow(label: L("Size"), height: 42) {
                    Menu {
                        ForEach(sizes(recipe.wrappedValue.size), id: \.self) { size in
                            Button(sizeTitle(size)) { recipe.wrappedValue.size = size }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(sizeTitle(recipe.wrappedValue.size)).font(Theme.Font.ui(13, .medium)).foregroundStyle(Theme.text)
                            Image(systemName: "chevron.up.chevron.down").font(Theme.Font.ui(10, .semibold)).foregroundStyle(Theme.dim)
                        }
                    }
                    .menuIndicator(.hidden)
                    .accessibilityIdentifier("filmlab.export.size")
                }
                .modifier(FeatureFlags.simpleWindow ? Separated(shown: false) : Separated())
                if !FeatureFlags.simpleWindow { ColourRow(recipe: recipe) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            SectionLabel(L("Save to")).padding(.horizontal, 16).padding(.top, 14)
            SegmentedSwitch(options: ExportRecipe.Destination.allCases, selection: recipe.destination,
                            title: \.shownTitle, height: 30, track: Theme.card)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            if recipe.wrappedValue.destination == .files {
                Button { startsAfterPicking = false; picking = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder").foregroundStyle(Theme.secondaryText)
                        Text(folder.map { MacExportFolder.place($0) } ?? L("Choose a Folder…"))
                            .font(Theme.Font.ui(12, .medium)).foregroundStyle(Theme.text)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Chevron()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .accessibilityIdentifier("filmlab.export.folder")
            }
            footer(recipe.wrappedValue)
                .padding(.horizontal, 12)
                .padding(.top, 14)
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
                CapsuleButton(title: L("Stop"), primary: false, height: 40) { run.stop() }
                    .accessibilityIdentifier("filmlab.export.stop")
            } else {
                CapsuleButton(title: frameIDs.count > 1 ? L("Export \(frameIDs.count) Pictures") : L("Export"),
                              height: 40, enabled: !frameIDs.isEmpty) { start(recipe) }
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
