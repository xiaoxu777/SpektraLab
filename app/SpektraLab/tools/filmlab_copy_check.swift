//  filmlab_copy_check.swift — FilmLab's import copy (`FilmLabCopier`) on a folder of real files:
//  copied once, skipped the second time, and a different file of the same name kept beside, never overwritten.
//
//  swiftc -parse-as-library Sources/Mac/FilmLab/FilmLabCopier.swift tools/filmlab_copy_check.swift -o /tmp/copycheck
//  /tmp/copycheck <card folder> <photo folder>

import Foundation

@main
struct CopyCheck {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3 else { print("usage: copycheck <card folder> <photo folder>"); exit(2) }
        let card = URL(fileURLWithPath: args[1]), photos = URL(fileURLWithPath: args[2])
        let target = photos.appendingPathComponent(card.lastPathComponent)
        var failed = false
        func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { failed = true } }

        func run() -> [FilmLabCopier.Outcome] {
            FilmLabCopier.pictures(under: card).map { f in
                let rel = String(f.path.dropFirst(card.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return FilmLabCopier.copyOne(f, to: target.appendingPathComponent(rel))
            }
        }
        let files = FilmLabCopier.pictures(under: card)
        check(!files.isEmpty, "\(files.count) pictures found under the card")
        let first = run()
        check(first.allSatisfy { $0 == .copied }, "first import copies every file")
        for f in files {
            let rel = String(f.path.dropFirst(card.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let copy = target.appendingPathComponent(rel)
            check(FileManager.default.contentsEqual(atPath: f.path, andPath: copy.path), "copy of \(rel) is byte-identical")
        }
        let second = run()
        check(second.allSatisfy { $0 == .skipped }, "second import skips what is already there")

        // A different file under a name already imported: kept beside, the first untouched.
        let other = card.appendingPathComponent("collide").appendingPathComponent(files[0].lastPathComponent)
        try? FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: other.path, contents: Data("not the same".utf8))
        let wanted = target.appendingPathComponent(String(files[0].path.dropFirst(card.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let r = FilmLabCopier.copyOne(other, to: wanted)
        let stem = wanted.deletingPathExtension().lastPathComponent
        let beside = wanted.deletingLastPathComponent().appendingPathComponent("\(stem) 2").appendingPathExtension(wanted.pathExtension)
        check(r == .copied && FileManager.default.fileExists(atPath: beside.path), "same name, other file: kept as \(beside.lastPathComponent)")
        check(FileManager.default.contentsEqual(atPath: files[0].path, andPath: wanted.path), "the first copy was not overwritten")
        try? FileManager.default.removeItem(at: other.deletingLastPathComponent())
        print(failed ? "FAILED" : "ALL PASS")
        exit(failed ? 1 : 0)
    }
}
