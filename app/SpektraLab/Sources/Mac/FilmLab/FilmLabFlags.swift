//  FilmLabFlags.swift — 留用 / 不要: a flag on each photo (the owner, 2026-11-25: "图片加入可以选择旗子的功能，好或者不好").
//
//  Lightroom's pick and reject: a photo is kept (留用), not wanted (不要), or neither. The library helper has no field
//  for it (`API-SPEC-library-helper.md`: a rating 0–5, a colour tag 0–7, the trash), and its database is not ours to
//  add a column to: an older build must still read it. So the flags of a project are one small file of their own,
//  **beside the project's database, inside its library package**:
//
//      <library>.spkcatalog/FilmLabFlags.json      {"version": 1, "flags": {"<image uuid>[#<variant uuid>]": "pick" | "reject"}}
//
//  That package is where the project's ratings and labels already live (for a folder project, the catalog the app
//  keeps for it under Application Support; for a catalog or a session the person made, their own), so a flag goes
//  exactly as far as a rating does, survives a relaunch, and is left alone by the helper and by older builds (a file
//  they do not know). A project with no flag has no file: clearing the last flag removes it. Where a source has no
//  library folder (the old app library), the file is `Application Support/<bundle id>/FilmLabFlags/<source>.json`.
//
//  Read through `flag(_:)`, which a view may call in its body: the tables are kept outside observation and loaded the
//  first time a source is asked for; `revision` is what a view follows.

import Foundation
import Observation

enum FilmLabFlag: String, Codable, Sendable, CaseIterable {
    case pick, reject

    var title: String {
        switch self {
        case .pick: L("Keep")
        case .reject: L("Reject")
        }
    }

    var symbol: String {
        switch self {
        case .pick: "flag.fill"
        case .reject: "xmark"
        }
    }
}

@MainActor
@Observable
final class FilmLabFlags {
    static let shared = FilmLabFlags()

    /// Counts the changes: what a view that shows a flag follows.
    private(set) var revision = 0

    @ObservationIgnored private var tables: [MacSource.ID: [String: FilmLabFlag]] = [:]
    @ObservationIgnored private weak var store: (any MacLibraryData)?

    private struct File: Codable {
        var version = 1
        var flags: [String: FilmLabFlag] = [:]
    }

    /// The store whose sources say where each project's library is (`MacLibraryPage`, the strip).
    func attach(_ store: any MacLibraryData) {
        if self.store !== store { self.store = store }
    }

    // MARK: reading

    func flag(_ image: MacImage) -> FilmLabFlag? {
        _ = revision
        let table = table(image.id.source)
        guard !table.isEmpty else { return nil }
        if let f = table[key(image)] { return f }
        // An image that gained a second variant: its first cell's id took a variant, its flag was written without one.
        if image.id.variant != nil, image.isPrimaryVariant { return table[image.id.image] }
        return nil
    }

    /// How many of `rows` wear `flag`.
    func count(_ flag: FilmLabFlag, in rows: [MacImage]) -> Int {
        _ = revision
        guard let source = rows.first?.id.source, !table(source).isEmpty else { return 0 }
        return rows.reduce(0) { $0 + (self.flag($1) == flag ? 1 : 0) }
    }

    // MARK: writing

    /// `flag` on every one of `images`; nil takes the flag off.
    func set(_ flag: FilmLabFlag?, for images: [MacImage]) {
        var touched: Set<MacSource.ID> = []
        for image in images {
            let source = image.id.source
            var t = table(source)
            let k = key(image)
            let old = t[k] ?? (image.id.variant != nil && image.isPrimaryVariant ? t[image.id.image] : nil)
            guard old != flag else { continue }
            if image.id.variant != nil, image.isPrimaryVariant { t[image.id.image] = nil }
            t[k] = flag
            tables[source] = t
            touched.insert(source)
        }
        guard !touched.isEmpty else { return }
        for source in touched { save(source) }
        revision += 1
    }

    /// A press on a flag's own button: the same flag again takes it off.
    func toggle(_ flag: FilmLabFlag, on image: MacImage, among images: [MacImage]) {
        set(self.flag(image) == flag ? nil : flag, for: images)
    }

    // MARK: the files

    private func key(_ image: MacImage) -> String {
        image.id.variant.map { image.id.image + "#" + $0 } ?? image.id.image
    }

    private func table(_ source: MacSource.ID) -> [String: FilmLabFlag] {
        if let t = tables[source] { return t }
        // Not known where yet (the store has not listed its sources): asked again next time.
        guard let file = file(source) else { return [:] }
        var t: [String: FilmLabFlag] = [:]
        if let data = try? Data(contentsOf: file), let read = try? JSONDecoder().decode(File.self, from: data) { t = read.flags }
        tables[source] = t
        return t
    }

    private func file(_ source: MacSource.ID) -> URL? {
        guard let s = store?.sources.first(where: { $0.id == source }) else { return nil }
        if let path = s.libraryPath {
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("FilmLabFlags.json")
            }
        }
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "FilmLab", isDirectory: true)
            .appendingPathComponent("FilmLabFlags", isDirectory: true)
            .appendingPathComponent(source.uuidString + ".json")
    }

    private func save(_ source: MacSource.ID) {
        guard let file = file(source) else { return }
        let t = tables[source] ?? [:]
        if t.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(File(flags: t)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
