// About, agent access and the read-only shortcut list. Shared row primitives keep the same rhythm as the settings.
import SwiftUI
import UIKit
import ImageIO

struct FilmLabSettingsAbout: View {
    @Environment(Diagnostics.self) private var diagnostics

    private var icon: UIImage? {
        let info = Bundle.main.infoDictionary ?? [:]
        let icons = info["CFBundleIcons"] as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let files = primary?["CFBundleIconFiles"] as? [String] ?? []
        let names = Array(files.reversed()) + [primary?["CFBundleIconName"] as? String
            ?? info["CFBundleIconName"] as? String ?? "SpektraLab", "AppIcon"]
        if let image = names.lazy.compactMap({ UIImage(named: $0) }).first { return image }
        // Catalyst may package Icon Composer's output as an icns rather than a named UIKit image.
        if let file = info["CFBundleIconFile"] as? String,
           let url = Bundle.main.url(forResource: file, withExtension: nil)
                ?? Bundle.main.url(forResource: file, withExtension: "icns"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { return UIImage(cgImage: image) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(MacSettingsMetric.gap)) {
            MacSettingsGroup(title: nil) {
                HStack(spacing: MacMetric.pt(16)) {
                    Group {
                        if let icon { Image(uiImage: icon).resizable().scaledToFit() }
                        else { Image(systemName: "camera.aperture").resizable().scaledToFit().foregroundStyle(Theme.accent) }
                    }
                    .frame(width: MacMetric.pt(64), height: MacMetric.pt(64))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: MacMetric.pt(6)) {
                        Text(Brand.name).font(MacMetric.font(22, .semibold)).foregroundStyle(Theme.text)
                        Text(diagnostics.build.text).font(MacMetric.font(13)).foregroundStyle(Theme.secondaryText)
                        Text(Brand.name + " · " + L("Made for and by ericxu"))
                            .font(MacMetric.font(13)).foregroundStyle(Theme.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(MacMetric.pt(20))
                .macSettingsItem("About", "This app")
            }
            MacSettingsGroup(title: L("Licences and credits")) {
                VStack(alignment: .leading, spacing: MacMetric.pt(16)) {
                    // This modified-version notice and both profile attributions must remain visible in full.
                    Text(verbatim: "FilmLab is a personal, modified version of SpektraLab by JamesQiu2005 "
                         + "(github.com/JamesQiu2005/SpektraLab), GPL-3.0-or-later. Its engine is a C++/Metal "
                         + "implementation derived from spektrafilm by Andrea Volpato (github.com/andreavolpato/spektrafilm).")
                        .macSettingsItem("SpektraLab engine")
                    Text(L("Film and paper")).font(MacMetric.font(13, .semibold))
                        .macSettingsItem("Film and paper")
                    Text(L("The colour film and paper profiles are from spektrafilm by Andrea Volpato, under CC BY-SA 4.0."))
                    Text(L("The black-and-white films and their paper are SpektraLab's own profiles, built from their makers' "
                           + "published data sheets, under CC BY-SA 4.0 as well."))
                }
                .font(MacMetric.font(13)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MacMetric.pt(20))
                .macSettingsItem("Licences and credits", "Licences")
            }
        }
    }
}

struct FilmLabSettingsAgents: View {
    @Environment(AppSettings.self) private var settings
    @State private var copied = false

    var body: some View {
        MacSettingsGroup(title: nil) {
            MacSettingsRow(label: L("Allow agents to use SpektraLab")) {
                MacSettingsCheckbox(label: L("Allow agents to use SpektraLab"),
                                    on: Binding(get: { settings.agentAccess }, set: { settings.agentAccess = $0 }))
            }
            .macSettingsItem("Agents", "Allow agents to use SpektraLab")
            MacSettingsRow(label: L("Command line"), detail: Self.quoted(Self.executable) + " cli tools", wrapsDetail: true)
                .macSettingsItem("Command line")
            MacSettingsRow(label: L("MCP server"), detail: Self.quoted(Self.executable) + " mcp", wrapsDetail: true, last: true) {
                Button(copied ? L("Copied") : L("Copy MCP Configuration")) {
                    UIPasteboard.general.string = Self.mcpConfiguration
                    copied = true
                }
                .buttonStyle(MacSettingsButtonStyle())
            }
            .macSettingsItem("MCP server", "Copy MCP Configuration")
        }
    }

    static var executable: String { Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? "SpektraLab" }
    static func quoted(_ path: String) -> String {
        path.contains(where: { $0 == " " || $0 == "'" }) ? "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" : path
    }
    static var mcpConfiguration: String {
        let v: JSONValue = ["mcpServers": ["spektralab": ["command": .string(executable), "args": ["mcp"]]]]
        return v.text(pretty: true)
    }
}

struct FilmLabSettingsShortcuts: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(MacSettingsMetric.gap)) {
            MacSettingsGroup(title: nil) {
                MacSettingsRow(label: L("Space bar"), last: true) {
                    MacSettingsSegments(label: L("Space bar"),
                                        options: [(AppSettings.SpaceOriginal.hold, L("Hold", as: "space bar")), (.toggle, L("Toggle", as: "space bar"))],
                                        selection: Binding(get: { settings.spaceOriginal }, set: { settings.spaceOriginal = $0 }))
                }
                .macSettingsItem("Keyboard", "Space bar")
            }
            group(L("Mode"), rows: modeRows)
            group(L("Selection", as: "shortcuts"), rows: selectionRows)
            group(L("Viewing", as: "shortcuts"), rows: viewingRows)
            group(L("Edit"), rows: editingRows)
            group(L("Library"), rows: libraryRows)
        }
    }

    private struct Row: Identifiable {
        let id: String
        let title: String
        let keys: [String]
        var caption: String? = nil
    }
    private func shortcut(_ key: MacShortcut) -> Row {
        Row(id: key.rawValue, title: key.title, keys: key.bindings.map(Self.keycap))
    }
    private func group(_ title: String, rows: [Row]) -> some View {
        MacSettingsGroup(title: title) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                MacSettingsRow(label: row.title + (row.caption.map { " · " + $0 } ?? ""), compact: true, last: i == rows.count - 1) {
                    HStack(spacing: MacMetric.pt(6)) {
                        ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in
                            Text(verbatim: key).font(MacMetric.font(12, .medium).monospaced())
                                .foregroundStyle(Theme.text).fixedSize()
                                .padding(.horizontal, MacMetric.pt(8)).frame(minHeight: MacMetric.pt(24))
                                .background(Theme.field, in: RoundedRectangle(cornerRadius: MacMetric.pt(5)))
                        }
                    }
                }
            }
        }
    }

    private var modeRows: [Row] {
        var keys: [MacShortcut] = [.modeLibrary, .modeDevelop]
        if ProMode.shared.on { keys.append(.modeGrading) }
        keys += [.modePersonalize, .modeExport]
        var rows = keys.map(shortcut)
        // P is the pick flag in both editions. The menu's actual Light Table key is ⇧⌘L.
        if ProMode.shared.on { rows.append(Row(id: "table", title: L("Light Table"), keys: ["⇧⌘L"])) }
        rows.append(Row(id: MacShortcut.proMode.rawValue, title: L("Switch Simple / Pro"),
                        keys: MacShortcut.proMode.bindings.map(Self.keycap)))
        return rows
    }
    private var selectionRows: [Row] {
        [Row(id: "pick", title: FilmLabFlag.pick.title, keys: ["P", "Z"]),
         Row(id: "reject", title: FilmLabFlag.reject.title, keys: ["X"]),
         Row(id: "unflag", title: L("Remove Flag"), keys: ["U"]),
         Row(id: "stars", title: L("Rating"), keys: ["1–5"]),
         Row(id: "no-stars", title: L("Clear rating"), keys: ["0"])]
        + [MacShortcut.red, .yellow, .green, .blue].map(shortcut)
        + [MacShortcut.selectAll, .selectNone, .invert].map(shortcut)
    }
    private var viewingRows: [Row] {
        var rows = [MacShortcut.original, .compare, .fit, .actualSize, .zoomIn, .zoomOut, .fullScreen, .browser, .column].map(shortcut)
        if ProMode.shared.on {
            rows += [MacShortcut.tableDrag, .tableClick, .tableLoupe, .tableFit, .tableActual, .tableZoomIn, .tableZoomOut, .tableRight, .tableLeft].map { key in
                // Keep P labelled only as 留用; L is the Light Table loupe's other shipped binding.
                let specs = key == .tableLoupe ? key.bindings.filter { $0.input != "p" } : key.bindings
                return Row(id: key.rawValue, title: key.title, keys: specs.map(Self.keycap), caption: L("Light Table"))
            }
        }
        return rows
    }
    private var editingRows: [Row] {
        var rows = [Row(id: "undo", title: L("Undo"), keys: ["⌘Z"]),
                    Row(id: "redo", title: L("Redo"), keys: ["⇧⌘Z"])]
        rows += [MacShortcut.crop, .copy, .copyChoosing, .paste, .pasteChoosing, .pasteAll, .reset, .newVariant, .cloneVariant].map(shortcut)
        if ProMode.shared.on {
            rows += MaskKey.allCases.map { key in
                Row(id: "mask.\(key.title)", title: key.title, keys: key.specs.prefix(1).map(Self.keycap), caption: L("Local"))
            }
        }
        return rows
    }
    private var libraryRows: [Row] {
        [Row(id: "arrows", title: L("Move selection"), keys: ["←", "→", "↑", "↓"]),
         Row(id: "extend", title: L("Extend selection"), keys: ["⇧←", "⇧→", "⇧↑", "⇧↓"]),
         Row(id: "open", title: L("Open in Develop"), keys: ["↩"]),
         Row(id: "remove", title: L("Remove from Library"), keys: ["⌫"]),
         Row(id: "escape", title: L("Select None"), keys: ["Esc"])]
        + [MacShortcut.previous, .next, .first, .last, .grid, .filters, .libraryTab, .filtersTab, .infoTab, .export].map(shortcut)
        + [Row(id: "import", title: L("Import"), keys: [Self.keycap(MacKeySpec(MacShortcut.importKey, modifiers: MacShortcut.importModifiers))]),
           Row(id: "home", title: L("Home"), keys: ["⇧⌘H"]),
           Row(id: "settings", title: L("Settings"), keys: ["⌘,"]),
           Row(id: "back", title: L("Back"), keys: ["⌘["])]
    }

    private static func keycap(_ spec: MacKeySpec) -> String {
        var prefix = ""
        if spec.flags.contains(.control) { prefix += "⌃" }
        if spec.flags.contains(.alternate) { prefix += "⌥" }
        if spec.flags.contains(.shift) { prefix += "⇧" }
        if spec.flags.contains(.command) { prefix += "⌘" }
        let key: String
        switch spec.input {
        case UIKeyCommand.inputLeftArrow: key = "←"
        case UIKeyCommand.inputRightArrow: key = "→"
        case UIKeyCommand.inputUpArrow: key = "↑"
        case UIKeyCommand.inputDownArrow: key = "↓"
        case UIKeyCommand.inputHome: key = "↖"
        case UIKeyCommand.inputEnd: key = "↘"
        case UIKeyCommand.inputEscape: key = "Esc"
        case UIKeyCommand.f2: key = "F2"
        case UIKeyCommand.f3: key = "F3"
        case " ": key = L("Space bar")
        default: key = spec.input.uppercased()
        }
        return prefix + key
    }
}
