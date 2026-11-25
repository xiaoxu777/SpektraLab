//  FilmLabLibraryCheck.swift — a check's launch only: 图库 driven from the command line, so a copy of the app can be
//  looked at without a hand on it (another FilmLab, the owner's, is usually open; nothing can click this one).
//
//      FilmLab --filmlab-library-check "wait:5,open,wait:3,pick:2,wait:1,key:p,say,…"
//
//  Steps, comma separated, run in order once the library page is up:
//    wait:S                seconds
//    open | home           the home page goes (a project opens: the entrance) | comes back
//    pick:0+3 | none       those rows chosen (indices into the rows shown) | nothing chosen
//    move:N                the arrow keys' move, N places
//    sidebar:on|off        the sidebar there or put away        sidebar-width:W   its width, Mac points (not kept)
//    preview:on|off        the preview offered or not           share:0.4         its share of the width (not kept)
//    flag:pick|reject|none on the chosen pictures               key:p | key:cmd+t | key:right | key:return
//                                                               a key, through the window's key registry
//    project:NAME          another project opened, as its card on the home page does      scroll:N   the grid to row N
//    mark:NAME             nothing here: the script outside takes a picture
//    filter:NAME           a roll filter (all, flagged, rejected, …)      hide-rejected:on|off
//    window:1500x900       the window's size, points
//    say                   one line of the state to ~/Library/Logs/FilmLab-library-check.txt
//  Every step also writes its name and the time to that file, so a script outside knows when to take its pictures.
//  `--filmlab-library-hover NAME` draws the cell whose file name starts with NAME as under the pointer.
//
//  A flag set here is written as a hand's would be (`FilmLabFlags`): a check clears what it set.

import SwiftUI
import UIKit

@MainActor
enum FilmLabLibraryCheck {
    static let hoverName = FilmLabCheckArgs.value("--filmlab-library-hover")
    private static var started = false

    static func startIfAsked(store: any MacLibraryData, library: FrameCatalog) {
        guard !started, let script = FilmLabCheckArgs.value("--filmlab-library-check") else { return }
        started = true
        Task { @MainActor in
            for step in script.split(separator: ",") {
                let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
                log(String(step))
                await run(parts[0], parts.count > 1 ? parts[1] : "", store, library)
            }
            log("done")
        }
    }

    private static func run(_ name: String, _ arg: String, _ store: any MacLibraryData, _ library: FrameCatalog) async {
        let browser = MacLibraryBrowser.shared
        let rows = FilmLabRollFilterState.shared.apply(store.images, library: library)
        let chosen = store.images.filter { browser.selection.contains($0.id) }
        switch name {
        case "wait": try? await Task.sleep(for: .milliseconds(Int((Double(arg) ?? 1) * 1000)))
        case "open": FilmLabHome.shared.hideHome()
        case "home": FilmLabHome.shared.showHome()
        case "pick":
            let ids = arg.split(separator: "+").compactMap { Int($0) }.filter { rows.indices.contains($0) }.map { rows[$0].id }
            browser.selection = Set(ids)
            browser.focus = ids.first
            browser.anchor = ids.first
            browser.scrollTarget = ids.first
        case "none": browser.selectNone()
        case "move": browser.move(Int(arg) ?? 1, extend: false, in: rows)
        case "sidebar": browser.sidebarShown = arg != "off"
        case "sidebar-width": if let w = Double(arg) { browser.sidebarWidth = CGFloat(w) }
        case "preview": FilmLabLibraryLayout.shared.previewShown = arg != "off"
        case "share": if let s = Double(arg) { FilmLabLibraryLayout.shared.previewShare = s }
        case "flag": FilmLabFlags.shared.set(FilmLabFlag(rawValue: arg), for: chosen)
        case "key":
            let bits = arg.split(separator: "+").map(String.init)
            var flags: UIKeyModifierFlags = []
            for b in bits.dropLast() {
                switch b {
                case "cmd": flags.insert(.command)
                case "shift": flags.insert(.shift)
                case "alt": flags.insert(.alternate)
                case "ctrl": flags.insert(.control)
                default: break
                }
            }
            let input: String = switch bits.last ?? "" {
            case "left": UIKeyCommand.inputLeftArrow
            case "right": UIKeyCommand.inputRightArrow
            case "up": UIKeyCommand.inputUpArrow
            case "down": UIKeyCommand.inputDownArrow
            case "return": "\r"
            case "esc": UIKeyCommand.inputEscape
            case let other: other
            }
            let command = UIKeyCommand(input: input, modifierFlags: flags, action: NSSelectorFromString("spkShortcut:"))
            log("key \(arg) · answered \(MacShortcutRegistry.shared.canPerform(command))")
            MacShortcutRegistry.shared.perform(command)
        case "project":
            guard let source = store.sources.first(where: { $0.name == arg }) else { log("no project \(arg)"); return }
            FilmLabHome.shared.hideHome()
            if source.id != store.selectedSourceID { await store.select(source: source.id) }
        case "scroll": if let n = Int(arg), rows.indices.contains(n) { browser.scrollTarget = rows[n].id }
        case "mark": break
        case "filter": FilmLabRollFilterState.shared.current = FilmLabRollFilter(rawValue: arg) ?? .all
        case "hide-rejected": FilmLabRollFilterState.shared.hideRejected = arg == "on"
        case "window":
            let size = arg.split(separator: "x").compactMap { Double($0) }
            guard size.count == 2, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
            var frame = scene.effectiveGeometry.systemFrame
            frame.size = CGSize(width: size[0], height: size[1])
            scene.requestGeometryUpdate(.Mac(systemFrame: frame))
        case "say":
            let flags = chosen.map { "\($0.fileName)=\(FilmLabFlags.shared.flag($0)?.rawValue ?? "none")" }.joined(separator: " ")
            let all = store.images
            log("state rows \(rows.count) of \(all.count) · chosen [\(flags)] · kept \(FilmLabFlags.shared.count(.pick, in: all))"
                + " rejected \(FilmLabFlags.shared.count(.reject, in: all)) · sidebar \(browser.sidebarShown) \(Int(browser.sidebarWidth))"
                + " · preview \(FilmLabLibraryLayout.shared.previewShown) \(FilmLabLibraryLayout.shared.previewShare)"
                + " · filter \(FilmLabRollFilterState.shared.current.rawValue) · project \(store.selectedSource?.name ?? "-")"
                + " · focus \(rows.firstIndex { $0.id == browser.focus }.map(String.init) ?? "-")"
                + " · develop \(MacShellBar.shared.develop != nil) · pro \(ProMode.shared.on) · hide \(FilmLabRollFilterState.shared.hideRejected)")
        default: log("unknown step \(name)")
        }
    }

    /// A line from the app itself while a check drives it (the entrance's steps); nothing otherwise.
    static func trace(_ line: @autoclosure () -> String) {
        if started { log(line()) }
    }

    private static func log(_ line: String) {
        let text = String(format: "%.3f  %@\n", Date().timeIntervalSince1970, line)
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/FilmLab-library-check.txt")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }
}
