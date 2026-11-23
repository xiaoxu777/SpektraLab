//  FilmLabOpen.swift — a photograph or a folder opened with FilmLab from outside: Finder's or Adobe Bridge's
//  Open With, a drop on the Dock icon.
//
//  The owner, 2026-11-22: "为什么我在 The bridge 里面都无法选择使用 Film Lab 打开？" The app declares photographs and folders
//  (Info.plist `CFBundleDocumentTypes`, as an Alternate handler, so it is offered and never takes over a type), and
//  what is opened is handled here:
//
//  - **A folder**: opened as a project where it is.
//  - **Photographs**: their folder is opened as a project where it is (Bridge's files are already where the person
//    keeps them: nothing is copied), they are chosen in the browser, and the first opens in 冲洗.
//
//  Several files arrive one call each, a moment apart: they are gathered and handled as one.

import SwiftUI

@MainActor
enum FilmLabOpen {
    private static var pending: [URL] = []
    private static var gathering: Task<Void, Never>?

    static func received(_ url: URL, model: AppServices) {
        guard url.isFileURL else { return }
        pending.append(url.standardizedFileURL)
        gathering?.cancel()
        gathering = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let urls = pending
            pending = []
            await open(urls, model: model)
        }
    }

    private static func open(_ urls: [URL], model: AppServices) async {
        guard let first = urls.first else { return }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir)
        let folder = isDir.boolValue ? first : first.deletingLastPathComponent()
        let files = urls.filter { !$0.hasDirectoryPath && FileManager.default.fileExists(atPath: $0.path) && !isDirectory($0) }
        let store = MacLibraryUI.store(model)
        let home = FilmLabHome.shared
        // Whatever covers the window steps aside: the tour (it comes back next launch), the home page.
        home.welcome = false
        do {
            _ = try await store.open(folder)
        } catch {
            MacLibraryActions.shared.refusal = error.localizedDescription
            return
        }
        model.router.dismissAllSheets()
        model.router.dismissCover()
        if MacShellPath.develop(model.router.path) != nil { model.router.toLibrary() }
        home.hideHome()
        guard !files.isEmpty else { return }
        // A folder seen for the first time is described a moment after it opens: the rows are waited for.
        let wanted = Set(files.map { key($0) })
        var found: [MacImage] = []
        for _ in 0..<40 {
            found = store.images.filter { wanted.contains(key($0.url)) }
            if found.count == wanted.count { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let image = found.first else { return }
        let browser = MacLibraryBrowser.shared
        browser.selection = Set(found.map(\.id))
        browser.focus = image.id
        MacDevelopWanted.surface = .develop
        MacDevelopWanted.step = .filmAndPaper
        MacLibraryGo.open(image, model: model)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping.lowercased()
    }
}
