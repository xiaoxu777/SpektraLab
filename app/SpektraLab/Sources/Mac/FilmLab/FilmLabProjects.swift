//  FilmLabProjects.swift — projects are made on the home page, and photos are dragged into them (the owner, 2026-11-24:
//  "在我截图的这个页面来创建项目，然后可以把图拖进项目里。在这个页面弹出子弹窗。进入到项目后图库页面仅针对看图选图").
//
//  - **新建项目** (`FilmLabNewProject`, `FilmLabNewProjectSheet`): a sheet over the home page — the project's name, a
//    large place to drop photos or folders, 选择照片… for Finder's panel, copy or leave them where they are, 创建.
//    Copying makes `<photo folder>/<name>` and copies the photos in (`FilmLabImport.createProject`); leaving them makes
//    the one folder dropped the project, as it is. Loose files are always copied (a project is a folder).
//  - **Dropping** goes through the window's own drop target (`MacImportDropZone`: SwiftUI's `onDrop` misses drags'
//    ends on Catalyst, MacDropOffer.swift), which asks `FilmLabDrop` first:
//      - the sheet up: the photos join the sheet's;
//      - the home page: onto a project's card, they go into that project (the card lit while the drag is over it);
//        anywhere else, the sheet opens with them in;
//      - a project open (any mode): into that project.
//    A project takes photos if it is a folder (copied into it) or a SpektraLab catalog or session (imported into it);
//    a Capture One catalog is read-only, and a drop on its card opens the sheet instead.
//  Projects are still the library's sources: nothing about the library's format changed.

import SwiftUI
import UIKit

/// Where a drag over the window goes, while FilmLab takes it.
@MainActor
@Observable
final class FilmLabDrop {
    static let shared = FilmLabDrop()
    private init() {}

    /// The window's model, so a drop reaches the library (set by the window).
    @ObservationIgnored weak var model: AppServices?
    /// Each project card's frame on the home page, in the window's points.
    @ObservationIgnored var cards: [MacSource.ID: CGRect] = [:]
    /// The card a drag is over now, lit.
    var hover: MacSource.ID?
    /// A drag FilmLab takes is over the window.
    var over = false

    private var store: (any MacLibraryData)? { model.map(MacLibraryUI.store) }

    /// FilmLab takes this drop (else the import page does, as before): the sheet or the home page is up, or the
    /// project open takes photos.
    func routes() -> Bool {
        guard let store else { return false }
        if FilmLabNewProject.shared.shown || FilmLabHome.shared.shown { return !FilmLabHome.shared.welcome }
        return store.selectedSource.map(FilmLabImport.takesPhotos) ?? false
    }

    /// The drag moved to `point` (the window's points).
    func moved(to point: CGPoint) {
        over = true
        guard FilmLabHome.shared.shown, !FilmLabNewProject.shared.shown, let store else { hover = nil; return }
        let id = cards.first { $0.value.contains(point) }?.key
        let takes = id.flatMap { id in store.sources.first { $0.id == id } }.map(FilmLabImport.takesPhotos) ?? false
        let lit = takes ? id : nil
        if lit != hover { withAnimation(.easeOut(duration: 0.12)) { hover = lit } }
    }

    func left() {
        over = false
        if hover != nil { withAnimation(.easeOut(duration: 0.12)) { hover = nil } }
    }

    /// The drop: its files read (`MacImportDrop.read`), then where `routes` says.
    func perform(_ providers: [NSItemProvider], router: AppRouter) {
        let target = hover
        left()
        guard let store else { return }
        Task {
            MacLibraryBrowser.shared.dropReading = providers.count
            let picks = await MacImportDrop.read(providers)
            MacLibraryBrowser.shared.dropReading = nil
            guard !picks.urls.isEmpty else { return }
            let sheet = FilmLabNewProject.shared
            if sheet.shown {
                sheet.add(picks.urls, copies: picks.copies)
            } else if FilmLabHome.shared.shown {
                if let target, let source = store.sources.first(where: { $0.id == target }) {
                    FilmLabImport.shared.add(picks.urls, to: source, store: store)
                } else {
                    sheet.open(with: picks.urls, copies: picks.copies)
                }
            } else if let source = store.selectedSource {
                FilmLabImport.shared.add(picks.urls, to: source, store: store)
            }
        }
    }

    /// The note while a drag is over the window outside the home page: where the photos will go.
    var note: String? {
        guard over, !FilmLabHome.shared.shown, !FilmLabNewProject.shared.shown, let source = store?.selectedSource else { return nil }
        return L("Drop to add to “\(source.name)”")
    }
}

// MARK: - 新建项目

@MainActor
@Observable
final class FilmLabNewProject {
    static let shared = FilmLabNewProject()
    private init() {}

    var shown = false
    var name = ""
    var items: [URL] = []
    /// Some of `items` are the system's temporary copies (another app's promise): they are always copied.
    var mustCopy = false

    func open(with urls: [URL] = [], copies: Bool = false) {
        items = urls
        mustCopy = copies
        name = Self.suggestedName(for: urls)
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { shown = true }
    }

    func add(_ urls: [URL], copies: Bool) {
        let known = Set(items.map(\.standardizedFileURL))
        items += urls.filter { !known.contains($0.standardizedFileURL) }
        mustCopy = mustCopy || copies
        if name.isEmpty || name == Self.suggestedName(for: []) { name = Self.suggestedName(for: items) }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.2)) { shown = false }
        items = []
        mustCopy = false
    }

    /// The one folder dropped names the project; else today's date, as a roll is named.
    static func suggestedName(for urls: [URL]) -> String {
        if urls.count == 1, (try? urls[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return urls[0].lastPathComponent
        }
        let f = DateFormatter()
        f.locale = Language.shared.current.locale
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f.string(from: Date())
    }
}

/// The sheet, over the home page.
struct FilmLabNewProjectSheet: View {
    let store: any MacLibraryData
    let router: AppRouter
    @FocusState private var naming: Bool

    private var sheet: FilmLabNewProject { .shared }
    private var imports: FilmLabImport { .shared }

    var body: some View {
        @Bindable var sheet = sheet
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { sheet.close() }
            VStack(alignment: .leading, spacing: MacMetric.pt(16)) {
                HStack {
                    Text(L("New Project")).font(MacMetric.font(18, .bold)).foregroundStyle(Theme.text)
                    Spacer()
                    Button { sheet.close() } label: {
                        Image(systemName: "xmark").font(MacMetric.font(12, .semibold)).foregroundStyle(Theme.dim)
                            .frame(width: MacMetric.pt(26), height: MacMetric.pt(26))
                            .background(Circle().fill(Theme.card))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filmlab.newproject.close")
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(L("Cancel"))
                }
                VStack(alignment: .leading, spacing: MacMetric.pt(6)) {
                    Text(L("Name")).font(MacMetric.font(11.5, .semibold)).foregroundStyle(Theme.dim)
                    TextField(L("Project name"), text: $sheet.name)
                        .textFieldStyle(.plain)
                        .font(MacMetric.font(15, .semibold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, MacMetric.pt(12)).frame(height: MacMetric.pt(36))
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.field))
                        .focused($naming)
                        .accessibilityIdentifier("filmlab.newproject.name")
                }
                dropZone
                storage
                HStack(spacing: MacMetric.pt(10)) {
                    Text(summary).font(MacMetric.font(12)).foregroundStyle(Theme.dim).lineLimit(1)
                    Spacer()
                    Button { sheet.close() } label: {
                        Text(L("Cancel")).font(MacMetric.font(13, .semibold)).foregroundStyle(Theme.text)
                            .padding(.horizontal, MacMetric.pt(16)).frame(height: MacMetric.pt(32))
                            .background(Capsule().fill(Theme.card))
                    }
                    .buttonStyle(.plain)
                    Button(action: create) {
                        Text(L("Create")).font(MacMetric.font(13, .semibold)).foregroundStyle(Theme.onSelection)
                            .padding(.horizontal, MacMetric.pt(20)).frame(height: MacMetric.pt(32))
                            .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(PressScale())
                    .keyboardShortcut(.defaultAction)
                    .disabled(sheet.items.isEmpty)
                    .opacity(sheet.items.isEmpty ? Theme.disabledOpacity : 1)
                    .accessibilityIdentifier("filmlab.newproject.create")
                }
            }
            .padding(MacMetric.pt(22))
            .frame(width: MacMetric.pt(520))
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.popover))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        .onAppear { if sheet.items.isEmpty { naming = true } }
        .accessibilityIdentifier("filmlab.newproject")
    }

    /// The large place to drop photos; the files so far, and 选择照片….
    private var dropZone: some View {
        let lit = FilmLabDrop.shared.over
        return VStack(spacing: MacMetric.pt(10)) {
            if sheet.items.isEmpty {
                Image(systemName: "square.and.arrow.down.on.square").font(.system(size: MacMetric.pt(30), weight: .light))
                    .foregroundStyle(lit ? Theme.accent : Theme.dim)
                Text(L("Drag photos or folders here")).font(MacMetric.font(14, .semibold)).foregroundStyle(Theme.text)
                Text(L("From Finder, Bridge or a card. RAW, 3FR, DNG, JPEG, TIFF and HEIC."))
                    .font(MacMetric.font(11.5)).foregroundStyle(Theme.dim)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: MacMetric.pt(4)) {
                        ForEach(sheet.items, id: \.self) { url in
                            HStack(spacing: MacMetric.pt(8)) {
                                Image(systemName: isFolder(url) ? "folder.fill" : "photo").font(MacMetric.font(12))
                                    .foregroundStyle(isFolder(url) ? Theme.accent : Theme.secondaryText)
                                    .frame(width: MacMetric.pt(16))
                                Text(url.lastPathComponent).font(MacMetric.font(12.5)).foregroundStyle(Theme.text)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                                Button { sheet.items.removeAll { $0 == url } } label: {
                                    Image(systemName: "minus.circle").font(MacMetric.font(12)).foregroundStyle(Theme.dim)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("Remove"))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: MacMetric.pt(110))
                Text(L("Drop more here to add them")).font(MacMetric.font(11)).foregroundStyle(Theme.dim)
            }
            Button {
                Task {
                    if let picked = await MacOpenPanel.choose(multiple: true) { sheet.add(picked, copies: false) }
                }
            } label: {
                Label(L("Choose Photos…"), systemImage: "folder").font(MacMetric.font(12.5, .semibold)).foregroundStyle(Theme.text)
                    .padding(.horizontal, MacMetric.pt(14)).frame(height: MacMetric.pt(28))
                    .background(Capsule().fill(Theme.card))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("filmlab.newproject.choose")
        }
        .padding(MacMetric.pt(18))
        .frame(maxWidth: .infinity, minHeight: MacMetric.pt(190))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(lit ? Theme.accent.opacity(0.08) : Theme.well.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(lit ? Theme.accent : Theme.field, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .animation(.easeOut(duration: 0.15), value: lit)
    }

    /// Copy (the default) or leave them where they are, compact; the photo folder under it.
    private var storage: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(8)) {
            HStack(spacing: MacMetric.pt(6)) {
                choice(.copy, L("Copy into my photo folder"))
                choice(.inPlace, L("Leave them where they are"))
                Spacer(minLength: 0)
            }
            Text(storageNote).font(MacMetric.font(11.5)).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choice(_ mode: FilmLabImport.Mode, _ title: String) -> some View {
        let on = imports.mode == mode
        return Button { imports.mode = mode } label: {
            HStack(spacing: MacMetric.pt(6)) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.accent : Theme.dim)
                Text(title).foregroundStyle(on ? Theme.text : Theme.secondaryText)
            }
            .font(MacMetric.font(12.5, .medium))
            .padding(.horizontal, MacMetric.pt(10)).frame(height: MacMetric.pt(28))
            .background(Capsule().fill(on ? Theme.card : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var leavesInPlace: Bool {
        imports.mode == .inPlace && !sheet.mustCopy && sheet.items.count == 1 && isFolder(sheet.items[0])
    }

    private var storageNote: String {
        if imports.mode == .copy {
            return L("The photos are copied into \(imports.folderShown)/\(FilmLabImport.folderName(sheet.name)). The originals are only read.")
        }
        return leavesInPlace ? L("The folder is opened where it is; nothing is copied.")
            : L("Single photos are always copied into the project's folder — leaving them in place works for one folder.")
    }

    private var summary: String {
        let folders = sheet.items.filter(isFolder).count, files = sheet.items.count - folders
        if sheet.items.isEmpty { return L("Nothing added yet") }
        var parts: [String] = []
        if folders > 0 { parts.append(folders == 1 ? L("1 folder") : L("\(folders) folders")) }
        if files > 0 { parts.append(files == 1 ? L("1 photo") : L("\(files) photos")) }
        return parts.joined(separator: " · ")
    }

    private func isFolder(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

    private func create() {
        let items = sheet.items, name = sheet.name, copies = sheet.mustCopy
        sheet.close()
        FilmLabImport.shared.createProject(named: name, items: items, copies: copies, store: store, router: router)
    }
}

/// The home page's 新建项目 button, beside 导入照片….
struct FilmLabNewProjectButton: View {
    var body: some View {
        Button { FilmLabNewProject.shared.open() } label: {
            HStack(spacing: MacMetric.pt(6)) {
                Image(systemName: "plus").font(MacMetric.font(12, .bold))
                Text(L("New Project")).font(MacMetric.font(12.5, .semibold)).fixedSize()
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, MacMetric.pt(14))
            .frame(height: MacMetric.pt(30))
            .background(RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous).fill(Theme.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityIdentifier("filmlab.home.new")
    }
}

/// A card the new-project's first tile: a dashed "新建项目" that also takes a drop.
struct FilmLabNewProjectCard: View {
    @State private var hovering = false
    var body: some View {
        Button { FilmLabNewProject.shared.open() } label: {
            VStack(spacing: MacMetric.pt(10)) {
                Image(systemName: "plus").font(.system(size: MacMetric.pt(26), weight: .light)).foregroundStyle(Theme.accent)
                Text(L("New Project")).font(MacMetric.font(14, .semibold)).foregroundStyle(Theme.text)
                Text(L("Drag photos onto the page, or click to choose")).font(MacMetric.font(11.5)).foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
            }
            .padding(MacMetric.pt(14))
            .frame(maxWidth: .infinity, minHeight: MacMetric.pt(200), maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel.opacity(hovering ? 0.9 : 0.55)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(hovering ? Theme.accent : Theme.field, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScale())
        .onHover { hovering = $0 }
        .accessibilityIdentifier("filmlab.home.newcard")
    }
}

/// While photos are dragged over an open project: "松手加入「…」", at the top of the window.
struct FilmLabDropNote: View {
    var body: some View {
        if let note = FilmLabDrop.shared.note {
            Label(note, systemImage: "plus.circle.fill")
                .font(MacMetric.font(13, .semibold)).foregroundStyle(Theme.onSelection)
                .padding(.horizontal, MacMetric.pt(16)).frame(height: MacMetric.pt(34))
                .background(Capsule().fill(Theme.accent))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                .padding(.top, MacMetric.pt(56))
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}
