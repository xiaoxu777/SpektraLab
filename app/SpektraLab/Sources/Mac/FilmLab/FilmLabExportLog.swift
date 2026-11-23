//  FilmLabExportLog.swift — when each picture was last exported (the owner, 2026-11-23: "开始记录每张照片的导出时间，
//  并加上「已导出」筛选").
//
//  Kept apart from the library's own records, in one small file of its own (`filmlab-exports.json` in Application
//  Support, frame id → the last export's time), so the library's format is not touched: the 图库 sidebar's 已导出 filter
//  and the home page's "all exported" read it. Written by the Mac's export batch for each picture saved
//  (`MacExportRun`). A picture removed from the library leaves a line nobody reads, which is harmless.

import Foundation
import Observation

@MainActor
@Observable
final class FilmLabExportLog {
    static let shared = FilmLabExportLog()

    /// Frame → when it was last exported.
    private(set) var exported: [UUID: Date] = [:]

    @ObservationIgnored private let file: URL?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        file = support?.appendingPathComponent("filmlab-exports.json")
        if let file, let data = try? Data(contentsOf: file),
           let read = try? JSONDecoder().decode([String: Date].self, from: data) {
            exported = Dictionary(uniqueKeysWithValues: read.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
        }
    }

    func exportedAt(_ id: UUID) -> Date? { exported[id] }
    func wasExported(_ id: UUID) -> Bool { exported[id] != nil }

    /// A picture saved by an export: now.
    func record(_ id: UUID, at date: Date = Date()) {
        exported[id] = date
        save()
    }

    private func save() {
        guard let file else { return }
        let out = Dictionary(uniqueKeysWithValues: exported.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(out) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
