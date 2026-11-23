//  FilmLabCopier.swift — the import's file work, apart from the app so `tools/filmlab_copy_check.swift` runs it as it is.

import Foundation

enum FilmLabCopier {
    /// The photographs an import copies and a project's cover is found among.
    static let pictureExtensions: Set<String> = ["3fr", "fff", "dng", "jpg", "jpeg", "tif", "tiff", "png", "heic", "heif",
                                                  "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "pef", "srw", "iiq"]

    enum Outcome: Sendable, Equatable { case copied, skipped, failed(String) }

    static func pictures(under root: URL) -> [URL] {
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let url as URL in walk where pictureExtensions.contains(url.pathExtension.lowercased()) {
            out.append(url)
        }
        return out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// One file into place: skipped where the same file is there already, beside it under a free name where another
    /// file has its name. Never overwrites.
    static func copyOne(_ file: URL, to wanted: URL) -> Outcome {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: wanted.deletingLastPathComponent(), withIntermediateDirectories: true)
            let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int) ?? -1
            var dest = wanted
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                let there = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? -2
                if there == size { return .skipped }
                let stem = wanted.deletingPathExtension().lastPathComponent, ext = wanted.pathExtension
                dest = wanted.deletingLastPathComponent().appendingPathComponent("\(stem) \(n)").appendingPathExtension(ext)
                n += 1
            }
            try fm.copyItem(at: file, to: dest)
            return .copied
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
