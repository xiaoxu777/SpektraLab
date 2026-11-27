//  FilmLabImport.swift — where FilmLab keeps the photographs it imports, and the import itself.
//
//  The owner, 2026-11-22: "开始应该选一个目标目录用于存储导入的照片，照片不要停在卡上。或者让用户自己选". So:
//
//  - **Copy to my photo folder** (the default): Import Photos… copies every picture under the folder picked — a
//    card's DCIM folder, say — into `<photo folder>/<the picked folder's name>`, then opens that copy as the
//    project. The card can be taken out once it is done; the originals are only read. A file already there with
//    the same name and size is skipped, so importing the same card again copies only what is new; a different
//    file with the same name is kept beside it ("B0001281 2.3FR"). Nothing is ever overwritten or deleted.
//  - **Leave them where they are**: the folder picked is opened as it is, as before.
//
//  The choice and the folder are asked for in the welcome tour and changed from the home page (`StorageChoice`).

import SwiftUI

@MainActor
@Observable
final class FilmLabImport {
    static let shared = FilmLabImport()

    enum Mode: String { case copy, inPlace }

    private static let modeKey = "filmlab.import.mode"
    private static let folderKey = "filmlab.import.folder"

    var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }
    var folder: URL {
        didSet { UserDefaults.standard.set(folder.path, forKey: Self.folderKey) }
    }

    /// The import running, or just finished (shown for a moment), or nil.
    var run: Run?

    struct Run: Equatable {
        var name: String
        var copied = 0
        var skipped = 0
        var total = 0
        var finished = false
        var problem: String?
        var fraction: Double { total == 0 ? 0 : Double(copied + skipped) / Double(total) }
    }

    @ObservationIgnored private var task: Task<Void, Never>?
    /// The panel's grants bridge presentation; the import session acquires its own before these are returned.
    @ObservationIgnored private var panelPicks: [URL] = []

    func takePanelPicks() -> [URL] {
        let access = panelPicks
        panelPicks = []
        return access
    }

    func releasePanelPicks() {
        for url in takePanelPicks() { url.stopAccessingSecurityScopedResource() }
    }

    /// `~/Pictures/FilmLab`: the default photo folder.
    static var defaultFolder: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("FilmLab", isDirectory: true)
    }

    private init() {
        let d = UserDefaults.standard
        mode = Mode(rawValue: d.string(forKey: Self.modeKey) ?? "") ?? .copy
        folder = d.string(forKey: Self.folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.defaultFolder
    }

    /// The photo folder as a person reads it: `~/Pictures/FilmLab`.
    var folderShown: String {
        let home = NSHomeDirectory()
        let p = folder.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    /// Asks for another photo folder (Finder's panel).
    func chooseFolder() async {
        guard let url = await MacOpenPanel.choose(multiple: false)?.first else { return }
        folder = url
    }

    /// One folder keeps the project shortcut. Files and mixed picks go through the import page unchanged.
    func importPhotos(store: any MacLibraryData, router: AppRouter, then done: @escaping () -> Void = {}) {
        guard run?.finished != false else { return }
        Task {
            let answer: [URL]?
            if let urls = FilmLabCheckArgs.importURLs("--filmlab-import-answer") { answer = urls }
            else { answer = await MacOpenPanel.choose(multiple: true) }
            guard let urls = answer, let picked = urls.first else { return }
            let access = urls.filter { $0.startAccessingSecurityScopedResource() }
            guard urls.count == 1, (try? picked.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                releasePanelPicks()
                panelPicks = access
                if MacShellPath.develop(router.path) != nil { router.toLibrary() }
                FilmLabHome.shared.hideHome()
                MacLibraryBrowser.shared.finderPicks = urls
                MacLibraryBrowser.shared.importAsked = true
                return
            }
            defer { for url in access { url.stopAccessingSecurityScopedResource() } }
            let source = picked.standardizedFileURL
            let inside = source.path.hasPrefix(folder.standardizedFileURL.path + "/") || source == folder.standardizedFileURL
            if mode == .inPlace || inside {
                await open(picked, store: store, router: router, done: done)
            } else {
                copy(picked, store: store, router: router, done: done)
            }
        }
    }

    func stop() { task?.cancel() }

    private func open(_ url: URL, store: any MacLibraryData, router: AppRouter, done: () -> Void) async {
        do {
            _ = try await store.open(url)
            if MacShellPath.develop(router.path) != nil { router.toLibrary() }
            done()
            FilmLabHome.shared.hideHome()
        } catch {
            run = Run(name: url.lastPathComponent, finished: true, problem: error.localizedDescription)
        }
    }

    private func copy(_ source: URL, store: any MacLibraryData, router: AppRouter, done: @escaping () -> Void) {
        let target = folder.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        copyItems([source], into: target, name: source.lastPathComponent) { [weak self] in
            await self?.open(target, store: store, router: router, done: done)
        }
    }

    /// Every picture among `items` — a dropped file as it is, a folder's pictures with their sub-folders — copied
    /// into `target`, then `landed` (when anything is there). Skips what is there already; never overwrites.
    private func copyItems(_ items: [URL], into target: URL, name: String, landed: @escaping () async -> Void) {
        let access = items.filter { $0.startAccessingSecurityScopedResource() }
        run = Run(name: name)
        task = Task {
            defer { for url in access { url.stopAccessingSecurityScopedResource() } }
            let jobs = await Task.detached(priority: .userInitiated) { Self.jobs(items, into: target) }.value
            run?.total = jobs.count
            guard !jobs.isEmpty else {
                run?.finished = true
                run?.problem = L("There are no photographs in this folder.")
                return
            }
            for (file, dest) in jobs {
                if Task.isCancelled { break }
                let outcome = await Task.detached(priority: .userInitiated) { Self.copyOne(file, to: dest) }.value
                switch outcome {
                case .copied: run?.copied += 1
                case .skipped: run?.skipped += 1
                case .failed(let why):
                    run?.problem = why
                    run?.finished = true
                    return
                }
            }
            let stopped = Task.isCancelled
            run?.finished = true
            if stopped { run?.problem = L("The import was stopped. What was copied is kept.") }
            if (run?.copied ?? 0) + (run?.skipped ?? 0) > 0 { await landed() }
            MacImportDrop.discard(items)   // a drop's temporary copies (another app's promise), if any; else nothing
            // The note stays a moment, so "you can take the card out" is read.
            if !stopped, run?.problem == nil {
                try? await Task.sleep(for: .seconds(2.5))
                if run?.finished == true, run?.problem == nil { run = nil }
            }
        }
    }

    /// Each picture of `items` and where it goes under `target`: a file at the top, a folder's with its own sub-folders.
    private nonisolated static func jobs(_ items: [URL], into target: URL) -> [(URL, URL)] {
        var out: [(URL, URL)] = []
        for item in items {
            var dir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &dir) else { continue }
            if dir.boolValue {
                for file in pictures(under: item) {
                    let rel = String(file.path.dropFirst(item.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    out.append((file, target.appendingPathComponent(rel)))
                }
            } else if FilmLabCopier.pictureExtensions.contains(item.pathExtension.lowercased()) {
                out.append((item, target.appendingPathComponent(item.lastPathComponent)))
            }
        }
        return out
    }

    // MARK: projects (the owner, 2026-11-24: "在[主页]来创建项目，然后可以把图拖进项目里")

    /// 新建项目's 创建: copied into `<photo folder>/<name>` and opened as the project; or, leaving them where they are,
    /// the one folder dropped opened as it is. Loose files are always copied: a project is a folder, and they have none.
    func createProject(named name: String, items: [URL], copies: Bool, store: any MacLibraryData, router: AppRouter) {
        guard run?.finished != false, !items.isEmpty else { return }
        let folders = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        if mode == .inPlace, !copies, items.count == 1, let only = folders.first {
            Task { await open(only, store: store, router: router, done: {}) }
            return
        }
        let target = Self.freeFolder(folder.appendingPathComponent(Self.folderName(name), isDirectory: true))
        copyItems(items, into: target, name: name) { [weak self] in
            await self?.open(target, store: store, router: router, done: {})
        }
    }

    /// Whether a project takes photos dropped on it: a folder (copied into it), or a SpektraLab catalog or session
    /// (imported as it imports, `MacLibraryData.importFiles`). A Capture One catalog is read-only; one offline is away.
    static func takesPhotos(_ source: MacSource) -> Bool {
        guard source.url != nil, source.status != .offline else { return false }
        return source.kind == .folder || source.kind == .catalog || source.kind == .session
    }

    /// Photos dropped on a project's card, or on 图库's grid: into that project, which is then looked at again.
    func add(_ items: [URL], to source: MacSource, store: any MacLibraryData) {
        guard run?.finished != false, Self.takesPhotos(source), let url = source.url else { return }
        if source.kind == .folder {
            copyItems(items, into: url, name: source.name) {
                ProjectCovers.shared.forget(source)
                await store.synchronize(source.id)
            }
        } else {
            run = Run(name: source.name)
            task = Task {
                let files = await Task.detached(priority: .userInitiated) { Self.jobs(items, into: url).map(\.0) }.value
                run?.total = files.count
                do {
                    let n = try await store.importFiles(files, into: source.id, mode: nil)
                    run?.copied = n
                    run?.skipped = max(files.count - n, 0)
                    run?.finished = true
                    ProjectCovers.shared.forget(source)
                    try? await Task.sleep(for: .seconds(2.5))
                    if run?.finished == true, run?.problem == nil { run = nil }
                } catch {
                    run?.finished = true
                    run?.problem = error.localizedDescription
                }
            }
        }
    }

    /// A project's name as a folder's: no slash or colon, not empty.
    nonisolated static func folderName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? L("Untitled Project") : cleaned
    }

    /// `wanted`, or "wanted 2", "wanted 3"… where a folder of that name already holds something else.
    nonisolated static func freeFolder(_ wanted: URL) -> URL {
        let fm = FileManager.default
        var url = wanted, n = 2
        while let inside = try? fm.contentsOfDirectory(atPath: url.path), !inside.filter({ !$0.hasPrefix(".") }).isEmpty {
            url = wanted.deletingLastPathComponent().appendingPathComponent("\(wanted.lastPathComponent) \(n)", isDirectory: true)
            n += 1
        }
        return url
    }

    func dismiss() { if run?.finished == true { run = nil } }

    private typealias Outcome = FilmLabCopier.Outcome
    private nonisolated static func pictures(under root: URL) -> [URL] { FilmLabCopier.pictures(under: root) }
    private nonisolated static func copyOne(_ file: URL, to wanted: URL) -> Outcome { FilmLabCopier.copyOne(file, to: wanted) }
}

// MARK: - the choice

/// Copy to my photo folder, or leave them where they are: two cards, and the folder under the first.
struct StorageChoice: View {
    var compact = false
    private var imports: FilmLabImport { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(10)) {
            option(.copy, symbol: "externaldrive.badge.checkmark", title: L("Copy to my photo folder (recommended)"),
                   text: L("The photos are copied from the card onto this Mac. When it is done you can take the card out, and the photos are still here."))
            if imports.mode == .copy {
                Button { Task { await imports.chooseFolder() } } label: {
                    HStack(spacing: MacMetric.pt(8)) {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("Photo folder")).font(MacMetric.font(11)).foregroundStyle(Theme.dim)
                            Text(imports.folderShown).font(MacMetric.font(12.5, .semibold)).foregroundStyle(Theme.text)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: MacMetric.pt(8))
                        Text(L("Change…")).font(MacMetric.font(12, .semibold)).foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, MacMetric.pt(12)).padding(.vertical, MacMetric.pt(8))
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, MacMetric.pt(compact ? 0 : 28))
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityIdentifier("filmlab.storage.folder")
            }
            option(.inPlace, symbol: "sdcard", title: L("Leave them where they are"),
                   text: L("Nothing is copied: FilmLab works from the folder you choose. The card has to stay in while you work."))
        }
        .animation(.spring(duration: 0.3), value: imports.mode)
    }

    private func option(_ mode: FilmLabImport.Mode, symbol: String, title: String, text: String) -> some View {
        let chosen = imports.mode == mode
        return Button { imports.mode = mode } label: {
            HStack(alignment: .top, spacing: MacMetric.pt(12)) {
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(MacMetric.font(17)).foregroundStyle(chosen ? Theme.accent : Theme.dim)
                VStack(alignment: .leading, spacing: MacMetric.pt(3)) {
                    HStack(spacing: MacMetric.pt(6)) {
                        Image(systemName: symbol).font(MacMetric.font(13, .semibold)).foregroundStyle(Theme.secondaryText)
                        Text(title).font(MacMetric.font(14, .semibold)).foregroundStyle(Theme.text)
                    }
                    Text(text).font(MacMetric.font(12.5)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(MacMetric.pt(compact ? 12 : 14))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(chosen ? Theme.accent : Theme.wall, lineWidth: chosen ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScale())
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The import's card over the window: what is being copied, how far, and Stop; then "you can take the card out".
struct ImportProgressCard: View {
    let run: FilmLabImport.Run
    private var imports: FilmLabImport { .shared }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(alignment: .leading, spacing: MacMetric.pt(12)) {
                HStack(spacing: MacMetric.pt(10)) {
                    Image(systemName: run.finished ? (run.problem == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                                   : "arrow.down.doc.fill")
                        .font(MacMetric.font(22)).foregroundStyle(run.problem == nil ? Theme.accent : Theme.danger)
                        .contentTransition(.symbolEffect(.replace))
                    Text(title).font(MacMetric.font(16, .bold)).foregroundStyle(Theme.text)
                }
                if !run.finished {
                    ProgressView(value: run.fraction).tint(Theme.accent)
                    Text(L("\(run.copied + run.skipped) of \(run.total)")).font(MacMetric.font(12)).foregroundStyle(Theme.dim)
                        .monospacedDigit()
                }
                Text(detail).font(MacMetric.font(12.5)).foregroundStyle(run.problem == nil ? Theme.secondaryText : Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    if run.finished {
                        CapsuleButton(title: L("OK"), primary: true, height: 32, width: 90) { imports.dismiss() }
                    } else {
                        CapsuleButton(title: L("Stop"), primary: false, height: 32, width: 90) { imports.stop() }
                    }
                }
            }
            .padding(MacMetric.pt(22))
            .frame(width: MacMetric.pt(400))
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.wall, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        }
        .accessibilityIdentifier("filmlab.import.progress")
    }

    private var title: String {
        if !run.finished { return L("Copying “\(run.name)”…") }
        return run.problem == nil ? L("Import finished") : L("Import stopped")
    }

    private var detail: String {
        if let problem = run.problem { return L(shown: problem) }
        if !run.finished { return L("Copying to \(imports.folderShown). Keep the card in until this is done.") }
        if run.skipped > 0 { return L("\(run.copied) copied, \(run.skipped) were already there. You can take the card out now.") }
        return L("\(run.copied) photos copied. You can take the card out now.")
    }
}
