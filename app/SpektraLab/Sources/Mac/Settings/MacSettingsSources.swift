//  MacSettingsSources.swift — Settings › Sources on the Mac: the Mac library's sources, managed.
//
//  On the window, Sources *links* a folder: every picture in it becomes a frame of the library. On the Mac
//  a Capture One catalog linked that way became ~9,600 frames and as many develops (MAC-LIBRARY-DATA.md
//  §6.3), so the Mac's Sources lists what the Mac library (`model.macLibrary`, `MacLibraryData`) reads —
//  the SpektraLab library, SpektraLab catalogs and sessions, Capture One's catalogs and sessions, Finder
//  folders — and manages them with the store's own calls:
//  - *Open Catalog or Folder…* (`open`, the library sidebar's own panel and types);
//  - *New Catalog…* (a save panel, `MacCatalogActions`); on a Capture One catalog *Copy to SpektraLab
//    Catalog…*, and on a copy "Copied from <path> · updated <date>" with *Update Now* (2026-10-24);
//  - while the old app library has frames no catalog took, *Move into a Catalog…* (`MacLibraryMove`);
//  - per source: *Show in Library* (`select(source:)`, then the Library), *Read Again* (`synchronize`),
//    *Show in Finder* (a catalog's package is shown in its folder: opening it would start Capture One),
//    *Remove from List* (`remove(source:)`: nothing on disk is deleted);
//  - its kind, where it is (whole: never cut), its state, its count when known, and for the source the
//    library shows, the folders it keeps in step (`watchedFolders`).
//
//  Folders linked the window's way before the Mac library existed (`FrameCatalog.linkedFolders`) are listed
//  under them while there are any, with the window's own actions (`LinkedFolderMenu`, `LinkedFolderActions`:
//  Check Again, Reconnect…, Unlink…) and *Keep a local copy*. A new folder is never linked that way here.

import SwiftUI
import UniformTypeIdentifiers

struct MacSettingsSources: View {
    /// Closes Settings (for *Show in Library*).
    let close: () -> Void

    @Environment(AppServices.self) private var model
    @Environment(FrameCatalog.self) private var library
    @Environment(AppRouter.self) private var router
    @State private var picking = false
    @State private var refusal: String?
    @State private var reconnecting: LinkedFolder.ID?
    @State private var unlinking: LinkedFolder.ID?

    private var store: any MacLibraryData { MacLibraryUI.store(model) }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(MacSettingsMetric.gap)) {
            if !store.move.candidates.isEmpty { moveGroup }
            sources
            if !library.linkedFolders.isEmpty { linked }
            if copiedInCount > 0 { copiedIn }
        }
        .task { await store.start() }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.openable) { result in
            guard case .success(let url) = result else { return }
            Task {
                do { _ = try await store.open(url) } catch { refusal = error.localizedDescription }
            }
        }
        .alert(L("This library cannot be shown"), isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(refusal.map { L(shown: $0) } ?? "")
        }
        .modifier(LinkedFolderActions(reconnecting: $reconnecting, unlinking: $unlinking))
    }

    /// What *Open Catalog or Folder…* may pick: the library sidebar's (`MacLibrarySidebar.openable`).
    static var openable: [UTType] {
        UTType.linkable + [UTType(filenameExtension: "spkcatalog", conformingTo: .package)].compactMap { $0 }
    }

    // MARK: the Mac library's sources

    private var sources: some View {
        let all = store.sources
        return MacSettingsGroup(title: L("Catalogs and folders")) {
            if all.isEmpty {
                MacSettingsRow(label: L("Reading the library…"), last: true)
            }
            ForEach(Array(all.enumerated()), id: \.element.id) { i, s in
                sourceRow(s, last: i == all.count - 1)
            }
            if let line = store.activity.working ?? store.activity.problem {
                MacSettingsCaption(L(shown: line))
                    .padding(.horizontal, MacMetric.pt(MacSettingsMetric.inset))
                    .padding(.bottom, MacMetric.pt(6))
            }
        } accessory: {
            HStack(spacing: MacMetric.pt(6)) {
                Button(L("New Catalog…")) { run { await MacCatalogActions.newCatalog(store) } }
                    .buttonStyle(MacSettingsButtonStyle())
                    .accessibilityIdentifier("mac.settings.sources.new")
                Button(L("Open Catalog or Folder…")) { picking = true }
                    .buttonStyle(MacSettingsButtonStyle())
                    .macSettingsItem("Link a Folder", "Reading the folder")
                    .accessibilityIdentifier("mac.settings.sources.open")
            }
        }
        .macSettingsItem("Library", "Sources", "Linked folders")
    }

    /// The old app library's frames, until they are moved into a catalog (`MacLibraryMove`).
    private var moveGroup: some View {
        MacSettingsGroup(title: L("SpektraLab Library")) {
            MacSettingsValueRow(label: L("\(store.move.candidates.count) pictures are not in a catalog yet"), value: "", last: true)
        } accessory: {
            Button(L("Move into a Catalog…")) {
                store.move.offer()
                close()
                router.toLibrary()
            }
            .buttonStyle(MacSettingsButtonStyle(kind: .primary))
            .accessibilityIdentifier("mac.settings.sources.move")
        }
    }

    /// A catalog command, its refusal shown.
    private func run(_ body: @escaping () async -> String?) {
        Task { if let why = await body() { refusal = why } }
    }

    /// The library sidebar's names (`MacLibrarySidebar.sourceName`): by what a source is, never by whose
    /// file it is.
    static func name(_ s: MacSource) -> String {
        switch s.kind {
        case .appLibrary: L("SpektraLab Library")
        case .captureOneCatalog, .catalog: L("Catalog: \(s.name)")
        case .captureOneSession, .session: L("Session: \(s.name)")
        case .folder: s.name
        }
    }

    /// "Connected", "Not connected", what failed; nothing before the source has been looked at.
    static func status(_ s: MacSource) -> (String, Bool)? {
        switch s.status {
        case .unknown: nil
        case .ready: (L("Connected"), false)
        case .offline: (L("Not connected"), true)
        case .busy: (L("Capture One is writing to it: read again in a moment"), false)
        case .inUse: (L("Open in another SpektraLab"), true)
        case .failed(let why): (L(shown: why), true)
        }
    }

    /// "Capture One 16.8.6.25 Pro Mac · 9,661 images".
    private func facts(_ s: MacSource) -> String {
        var parts: [String] = []
        switch s.kind {
        case .captureOneCatalog, .captureOneSession: parts.append(["Capture One", s.format].compactMap { $0 }.joined(separator: " "))
        default: if let f = s.format { parts.append(f) }
        }
        if let n = s.imageCount { parts.append(L("\(Fmt.thousands(n)) images")) }
        return parts.joined(separator: Fmt.dot)
    }

    private func sourceRow(_ s: MacSource, last: Bool) -> some View {
        let selected = store.selectedSourceID == s.id
        let hasWatched = selected && s.acceptsFolders && !store.watchedFolders.isEmpty
        let details = [facts(s), s.path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: Fmt.dot)
        return VStack(spacing: 0) {
            MacSettingsRow(label: Self.name(s) + (selected ? Fmt.dot + L("In the Library") : ""), detail: details.isEmpty ? nil : details,
                           caption: Self.status(s)?.0, last: last && s.copiedFrom == nil && !hasWatched) {
                actions(s)
            }
            if let c = s.copiedFrom { copiedLine(s, c) }
            if hasWatched { watched }
        }
        .contextMenu { menu(s) }
        .accessibilityIdentifier("mac.settings.source")
        .onAppear {
            #if DEBUG
            MacSettingsCheck.sawSource(s.id)
            #endif
        }
    }

    /// "Copied from ~/Pictures/Capture One Catalog.cocatalog · updated 24 Oct 2026 at 18:02", and *Update Now*.
    private func copiedLine(_ s: MacSource, _ c: MacCopiedFrom) -> some View {
        let from = c.path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? L("Capture One")
        let when = c.lastTaken.map { $0.formatted(date: .abbreviated, time: .shortened) }
        return MacSettingsRow(label: L("Capture One"),
                              detail: when.map { L("Copied from \(from) · updated \($0)") } ?? L("Copied from \(from)"), last: true) {
            Button(L("Update Now")) { run { await MacCatalogActions.update(store, s) } }
                .buttonStyle(MacSettingsButtonStyle())
                .disabled(store.activity.working != nil)
                .accessibilityIdentifier("mac.settings.sources.update")
        }
    }

    /// The folders a SpektraLab catalog or session keeps in step, for the source the library shows.
    private var watched: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacSettingsCaption(L("Folders kept in step")).padding(.horizontal, MacMetric.pt(MacSettingsMetric.inset))
            ForEach(store.watchedFolders) { f in
                MacSettingsRow(label: f.url.lastPathComponent, detail: (f.url.path as NSString).abbreviatingWithTildeInPath, last: true) {
                    Text(f.isOnline ? L("\(Fmt.thousands(f.imageCount)) images") : L("Not connected"))
                        .font(MacMetric.font(13)).foregroundStyle(f.isOnline ? Theme.secondaryText : Theme.danger)
                }
            }
        }
    }

    private func actions(_ s: MacSource) -> some View {
        HStack(spacing: MacMetric.pt(6)) {
            Button(L("Show in Library")) { showInLibrary(s) }
                .buttonStyle(MacSettingsButtonStyle())
            Menu { menu(s) } label: {
                Image(systemName: "ellipsis.circle").font(MacMetric.font(15)).foregroundStyle(Theme.secondaryText)
                    .frame(width: MacMetric.pt(34), height: MacMetric.pt(34)).contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(L("Source Actions"))
        }
    }

    @ViewBuilder private func menu(_ s: MacSource) -> some View {
        Button { showInLibrary(s) } label: { Label(L("Show in Library"), systemImage: "photo.on.rectangle") }
        if s.kind == .captureOneCatalog {
            Button { run { await MacCatalogActions.copyToCatalog(store, s) } } label: {
                Label(L("Copy to SpektraLab Catalog…"), systemImage: "doc.on.doc")
            }
        }
        if s.isCopiedFromCaptureOne {
            Button { run { await MacCatalogActions.update(store, s) } } label: {
                Label(L("Update from Capture One"), systemImage: "arrow.triangle.2.circlepath")
            }
        }
        if s.kind != .appLibrary {
            Button { Task { await store.synchronize(s.id) } } label: { Label(L("Read Again"), systemImage: "arrow.clockwise") }
            if let url = s.url {
                Button { showInFinder(url) } label: { Label(L("Show in Finder"), systemImage: "folder") }
            }
            Divider()
            Button(role: .destructive) { store.remove(source: s.id) } label: { Label(L("Remove from List"), systemImage: "minus.circle") }
        }
    }

    private func showInLibrary(_ s: MacSource) {
        Task {
            await store.select(source: s.id)
            router.toLibrary()
        }
    }

    /// A folder is opened in Finder; a package (a catalog) is shown in the folder that holds it.
    private func showInFinder(_ url: URL) {
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
            || ["cocatalog", "spkcatalog"].contains(url.pathExtension.lowercased())
        UIApplication.shared.open(isPackage ? url.deletingLastPathComponent() : url)
    }

    // MARK: folders linked the window's way

    private var linked: some View {
        MacSettingsGroup(title: L("Folders linked as frames")) {
            ForEach(Array(library.linkedFolders.enumerated()), id: \.element.id) { i, folder in
                linkedRow(folder, last: i == library.linkedFolders.count - 1)
            }
        }
        .task {
            await library.recheckFolders()
            await library.pollFolders()
        }
    }

    private func linkedRow(_ folder: LinkedFolder, last: Bool) -> some View {
        let menu = LinkedFolderMenu(folder: folder, reconnect: { reconnecting = folder.id }, unlink: { unlinking = folder.id })
        return MacSettingsRow(label: folder.title,
                              detail: [folder.place, folder.statusLine].joined(separator: Fmt.dot),
                              caption: folder.statusHint, last: last) {
            HStack(spacing: MacMetric.pt(10)) {
                if folder.kind == .disk {
                    Text(L("Keep a local copy")).font(MacMetric.font(13)).foregroundStyle(Theme.secondaryText)
                    MacSettingsCheckbox(label: L("Keep a local copy"), on: Binding(
                        get: { library.linkedFolders.first { $0.id == folder.id }?.keepsLocalCopy ?? false },
                        set: { library.setKeepsLocalCopy(folder.id, $0) }))
                        .macSettingsItem("Keep a local copy")
                }
                Menu { menu } label: {
                    Image(systemName: "ellipsis.circle").font(MacMetric.font(18))
                        .frame(width: MacMetric.pt(34), height: MacMetric.pt(34)).contentShape(Rectangle())
                }
                .accessibilityLabel(L("Folder Actions"))
            }
        }
        .contextMenu { menu }
        .macSettingsItem("Linked folder actions")
    }

    // MARK: copied in

    private var copiedInCount: Int {
        library.storage.copiedInFrames + library.frames.filter { $0.source == .copiedIn }.count
    }

    private var copiedIn: some View {
        let n = copiedInCount
        return MacSettingsGroup(title: L("Copied into SpektraLab")) {
            MacSettingsValueRow(label: L("\(n) frames"), value: Fmt.gigabytes(library.storage.copiedInOriginals),
                                last: true)
        }
        .macSettingsItem("Copied into SpektraLab", "%@ frames")
    }
}
