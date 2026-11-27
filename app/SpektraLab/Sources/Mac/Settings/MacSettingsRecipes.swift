// Export defaults. Simple uses only naming and destination; Pro edits stored recipes in place.
import SwiftUI

struct MacSettingsRecipes: View {
    @Environment(ExportRecipeStore.self) private var recipes
    @Environment(AppSettings.self) private var settings

    @State private var shown: ExportRecipe.ID?
    @State private var name = ""
    @State private var edgeText = ""
    @State private var confirmingDelete = false

    /// The saved recipe Export opens with (the window page's `ticked`).
    private var ticked: ExportRecipe? { recipes.saved(as: settings.recipe) }
    private var current: ExportRecipe? { (shown.flatMap { recipes.recipe($0) }) ?? ticked ?? recipes.recipes.first }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(MacSettingsMetric.gap)) {
            if ProMode.shared.on {
                list
                if let recipe = current { editor(recipe) }
            } else {
                MacSettingsGroup(title: nil, footer: recipes.problem) { fileRows(sharedDefaults) }
            }
        }
        .onAppear { load(current) }
        .onChange(of: current?.id) { _, _ in load(current) }
        .confirmationDialog(L("Delete \(current?.name ?? "")?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(L("Delete"), role: .destructive) { delete() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Frames already exported keep their files."))
        }
    }

    // MARK: the list

    private var list: some View {
        MacSettingsGroup(title: L("Recipes")) {
            ForEach(Array(recipes.recipes.enumerated()), id: \.element.id) { i, recipe in
                row(recipe, last: i == recipes.recipes.count - 1)
            }
            .macSettingsItem("Export", "Recipes", "Recipe")
        } accessory: {
            HStack(spacing: MacMetric.pt(6)) {
                Button(L("New Recipe")) { add() }
                    .buttonStyle(MacSettingsButtonStyle())
                    .macSettingsItem("New Recipe", "Add Recipe")
                Button(L("Delete Recipe")) { confirmingDelete = true }
                    .buttonStyle(MacSettingsButtonStyle(kind: .destructive))
                    .disabled(!recipes.canRemove || current == nil)
                    .macSettingsItem("Delete Recipe")
            }
        }
    }

    private func row(_ recipe: ExportRecipe, last: Bool) -> some View {
        let isTicked = recipe.id == ticked?.id
        let selected = recipe.id == current?.id
        return MacSettingsRow(label: recipe.name, detail: RecipeWords.makes(recipe), last: last) {
            if isTicked {
                Text(L("Default", as: "recipe")).font(MacMetric.font(12, .medium)).foregroundStyle(Theme.accent)
            } else if selected {
                Button(L("Set as default")) { settings.recipe = recipe }
                    .buttonStyle(MacSettingsButtonStyle())
            }
        }
        .background {
            RoundedRectangle(cornerRadius: MacMetric.pt(8))
                .fill(selected ? Theme.card.opacity(0.45) : .clear)
                .padding(.horizontal, MacMetric.pt(4))
                .padding(.vertical, MacMetric.pt(2))
        }
        .contentShape(Rectangle()).onTapGesture { shown = recipe.id }
        .focusable()
        .onKeyPress(.space) { shown = recipe.id; return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { shown = recipe.id }
        .accessibilityIdentifier("mac.settings.recipe")
    }

    /// Read the latest default at each write, changing only the two fields Simple actually uses.
    /// Update a stored recipe only if it matched before the edit; a custom export must not overwrite it by id.
    private var sharedDefaults: Binding<ExportRecipe> {
        Binding(get: { settings.recipe }, set: { edited in
            let before = settings.recipe
            let saved = recipes.saved(as: before)
            var next = before
            next.naming = edited.naming
            next.destination = edited.destination
            if let saved { recipes.update(saved.id, with: next) }
            settings.recipe = next
        })
    }

    // MARK: the recipe

    private func editor(_ recipe: ExportRecipe) -> some View {
        let draft = Binding<ExportRecipe>(get: { recipes.recipe(recipe.id) ?? recipe }, set: { change(recipe.id, $0) })
        return MacSettingsGroup(title: recipe.name, footer: recipes.problem, capitals: false) {
            MacSettingsRow(label: L("Name")) {
                MacSettingsField(placeholder: recipe.builtName, text: $name, width: 220) { commitName(recipe.id) }
                    .accessibilityLabel(L("Recipe name"))
            }
            .macSettingsItem("Name")
            MacSettingsRow(label: L("Format")) {
                MacSettingsPopUp(label: L("Format"), options: ExportRecipe.Format.allCases.map { ($0, $0.title) },
                                 selection: draft.format)
            }
            .macSettingsItem("File", "Format")
            MacSettingsRow(label: L("Size")) { size(draft) }
                .macSettingsItem("Size")
            MacSettingsRow(label: L("Colour")) {
                MacSettingsPopUp(label: L("Colour"), options: ExportRecipe.Colour.allCases.map { ($0, $0.fullName) },
                                 selection: draft.colour)
            }
            .macSettingsItem("Colour")
            MacSettingsRow(label: L("Quality"), caption: draft.wrappedValue.mayBand ? L("In 8 bits ProPhoto can band in smooth tones") : nil) {
                if draft.wrappedValue.format.takesQuality {
                    MacSettingsPopUp(label: L("Quality"), options: Self.qualities.map { ($0, "\($0)") }, selection: draft.quality,
                                     other: "\(draft.wrappedValue.quality)")
                } else {
                    Text(L("\(draft.wrappedValue.format.bitDepth)-bit, lossless")).font(MacMetric.font(12)).foregroundStyle(Theme.secondaryText)
                        .fixedSize()
                }
            }
            .macSettingsItem("Quality")
            fileRows(draft)
        }
    }

    @ViewBuilder private func fileRows(_ draft: Binding<ExportRecipe>) -> some View {
        MacSettingsRow(label: L("File naming"), detail: L("For example: \(draft.wrappedValue.fileName(Self.sampleContext))")) {
            naming(draft)
        }
        .macSettingsItem("Naming")
        MacSettingsRow(label: L("Separator")) {
            MacSettingsSegments(label: L("Separator"), options: ExportRecipe.Naming.separators.map { ($0, $0 == " " ? L("Space") : $0) },
                                selection: draft.naming.separator)
        }
        MacSettingsRow(label: L("Save to"), last: true) {
            MacSettingsSegments(label: L("Save to"), options: ExportRecipe.Destination.allCases.map { ($0, $0.shownTitle) },
                                selection: draft.destination)
        }
        .macSettingsItem("Save to")
    }

    /// The name the Naming row's example is made from: 1.x's model frame.
    static let sampleContext = ExportRecipe.Naming.Context(originalName: "_DSC4037", filmStock: "Portra_400",
                                                           printStock: "Portra_Endura", date: Date())

    /// The file's name (issue #111): the four parts, lit when on, and the separator. The order is the Export
    /// page's to change (its chips are dragged); here a part is put in or left out.
    private func naming(_ draft: Binding<ExportRecipe>) -> some View {
        HStack(spacing: MacMetric.pt(6)) {
            ForEach(draft.wrappedValue.naming.order) { t in
                let on = draft.wrappedValue.naming.isOn(t)
                Button { draft.wrappedValue.naming.toggle(t) } label: {
                    Text(t.title).font(MacMetric.font(13, on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.onSelection : Theme.secondaryText)
                        .padding(.horizontal, MacMetric.pt(8))
                        .frame(minHeight: MacMetric.pt(MacSettingsMetric.control))
                        .background(Capsule().fill(on ? Theme.accent : Theme.field))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// The Quality steps the pop-up offers (the Export page's slider takes any of 1…100).
    static let qualities = [100, 95, 90, 85, 80, 75]

    private enum SizeKind: Hashable { case full, twelve, long, short }

    /// Full, 12 MP, or an edge typed in pixels (`ExportSizePage`'s four).
    private func size(_ draft: Binding<ExportRecipe>) -> some View {
        let r = draft.wrappedValue
        let kind: SizeKind = switch r.size {
        case .full, .preview: .full
        case .megapixels: .twelve
        case .longEdge: .long
        case .shortEdge: .short
        }
        let options: [(SizeKind, String)] = [(.full, L("Full size")), (.twelve, "\(Int(ExportRecipe.twelveMegapixels)) MP"),
                                             (.long, L("Long edge")), (.short, L("Short edge"))]
        return HStack(spacing: MacMetric.pt(6)) {
            if kind == .long || kind == .short {
                MacSettingsField(placeholder: "\(edge(of: r.size))", text: $edgeText, width: 64) { commitEdge(draft) }
                    .accessibilityLabel(kind == .long ? L("Long edge") : L("Short edge"))
                Text("px").font(MacMetric.font(12)).foregroundStyle(Theme.dim)
            }
            MacSettingsPopUp(label: L("Size"), options: options,
                             selection: Binding(get: { kind }, set: { new in
                                 let e = edge(of: r.size)
                                 switch new {
                                 case .full: draft.wrappedValue.size = .full
                                 case .twelve: draft.wrappedValue.size = .megapixels(ExportRecipe.twelveMegapixels)
                                 case .long: draft.wrappedValue.size = .longEdge(e)
                                 case .short: draft.wrappedValue.size = .shortEdge(e)
                                 }
                                 edgeText = ""
                             }))
        }
    }

    /// The edge a size names, or the one an edge starts at (`ExportSizePage`'s 2,048).
    private func edge(of size: ExportRecipe.Size) -> Int {
        switch size {
        case .longEdge(let e), .shortEdge(let e): e
        default: 2048
        }
    }

    private func commitEdge(_ draft: Binding<ExportRecipe>) {
        defer { edgeText = "" }
        guard let n = Int(edgeText.filter(\.isNumber)) else { return }
        let e = max(n, ExportSizePage.smallestEdge)
        switch draft.wrappedValue.size {
        case .longEdge: draft.wrappedValue.size = .longEdge(e)
        case .shortEdge: draft.wrappedValue.size = .shortEdge(e)
        default: break
        }
    }

    // MARK: changing (the window page's own calls)

    private func load(_ recipe: ExportRecipe?) {
        name = recipe?.title ?? ""
        edgeText = ""
    }

    private func change(_ id: ExportRecipe.ID, _ now: ExportRecipe) {
        let follows = ticked?.id == id
        recipes.update(id, with: now)
        if follows, let saved = recipes.recipe(id) { settings.recipe = saved }
    }

    private func commitName(_ id: ExportRecipe.ID) {
        guard let saved = recipes.recipe(id), ExportRecipe.cleanTitle(name) != saved.title else { return }
        recipes.rename(id, to: name)
        name = recipes.recipe(id)?.title ?? ""
        follow(id)
    }

    /// Export opens with this recipe: it opens with it as it is now.
    private func follow(_ id: ExportRecipe.ID) {
        guard ticked?.id == id, let now = recipes.recipe(id), now != settings.recipe else { return }
        settings.recipe = now
    }

    private func add() {
        var draft = settings.recipe
        draft.title = nil
        if draft.size == .preview { draft.size = ExportRecipe().size }
        let made = recipes.add(draft, named: "")
        shown = made.id
    }

    private func delete() {
        guard let id = current?.id else { return }
        let wasDefault = ticked?.id == id
        guard recipes.remove(id) else { return }
        if wasDefault, let first = recipes.recipes.first { settings.recipe = first }
        shown = nil
    }
}
