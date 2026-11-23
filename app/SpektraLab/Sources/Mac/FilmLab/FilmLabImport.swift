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

    /// Import Photos…: a folder picked in Finder, copied or left where it is, then opened as a project.
    func importPhotos(store: any MacLibraryData, router: AppRouter, then done: @escaping () -> Void = {}) {
        guard run?.finished != false else { return }
        Task {
            guard let picked = await MacOpenPanel.choose(multiple: false)?.first else { return }
            let source = picked.standardizedFileURL
            let inside = source.path.hasPrefix(folder.standardizedFileURL.path + "/") || source == folder.standardizedFileURL
            if mode == .inPlace || inside {
                await open(source, store: store, router: router, done: done)
            } else {
                copy(source, store: store, router: router, done: done)
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
        run = Run(name: source.lastPathComponent)
        task = Task {
            let files = await Task.detached(priority: .userInitiated) { Self.pictures(under: source) }.value
            run?.total = files.count
            guard !files.isEmpty else {
                run?.finished = true
                run?.problem = L("There are no photographs in this folder.")
                return
            }
            for file in files {
                if Task.isCancelled { break }
                let rel = String(file.path.dropFirst(source.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let outcome = await Task.detached(priority: .userInitiated) { Self.copyOne(file, to: target.appendingPathComponent(rel)) }.value
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
            if (run?.copied ?? 0) + (run?.skipped ?? 0) > 0 {
                await open(target, store: store, router: router, done: done)
            }
            // The note stays a moment, so "you can take the card out" is read.
            if !stopped, run?.problem == nil {
                try? await Task.sleep(for: .seconds(2.5))
                if run?.finished == true, run?.problem == nil { run = nil }
            }
        }
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
