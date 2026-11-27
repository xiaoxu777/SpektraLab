//  FilmLabFlagViews.swift — how a flag (`FilmLabFlags`) is drawn and set: over a picture in the grid, as two chips
//  beside the preview's name, as a small mark under a frame of the strip, in a photo's menu, and from the keyboard.
//
//  留用 is a flag, 不要 a cross. Over a photo both are drawn in fixed colours (a white disc with a dark flag, a red disc
//  with a white cross), since the photo under them is not the theme's; on the app's own ground they are chips in the
//  theme's selection and danger colours. Amber stays the stars'.
//
//  Keys, in every mode like the rating's digits: P / Z 留用, X 不要, U takes the flag off (Lightroom's). P was the Light
//  Table's key in 专业版 (it keeps ⇧⌘L and the Image menu): these keys register a turn after the window's own, and the
//  registry answers a key with its newest registration (`MacShortcutRegistry.entry`).

import SwiftUI

/// The pictures a press on `image`'s flag acts on: every chosen one when it is among them, else itself (as a star is).
@MainActor
enum FilmLabFlagTargets {
    static func of(_ image: MacImage, in rows: [MacImage]) -> [MacImage] {
        let chosen = MacLibraryBrowser.shared.selection
        guard chosen.count > 1, chosen.contains(image.id) else { return [image] }
        return rows.filter { chosen.contains($0.id) }
    }
}

/// Over a picture: a disc per flag while the pointer is on the cell (`both`), else only the one that is set.
struct FilmLabFlagDiscs: View {
    let flag: FilmLabFlag?
    let both: Bool
    let press: (FilmLabFlag) -> Void
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: MacMetric.pt(4)) {
            ForEach(FilmLabFlag.allCases, id: \.self) { f in
                if both || flag == f { disc(f) }
            }
        }
    }

    private func disc(_ f: FilmLabFlag) -> some View {
        let on = flag == f
        return Button { press(f) } label: {
            Image(systemName: f.symbol)
                .font(.system(size: MacMetric.pt(size * 0.48), weight: .bold))
                .foregroundStyle(on ? (f == .pick ? Color.black.opacity(0.85) : Color.white) : Color.white.opacity(0.92))
                .frame(width: MacMetric.pt(size), height: MacMetric.pt(size))
                .background(on ? (f == .pick ? Color.white : Color(hex: 0xD9483B)) : Color.black.opacity(0.55), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(f.title + (f == .pick ? " (P / Z)" : " (X)"))
        .accessibilityLabel(f.title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("filmlab.flag.\(f.rawValue)")
    }
}

/// On the app's own ground (the preview's line): 留用 and 不要 as two chips, the one set filled.
struct FilmLabFlagChips: View {
    let flag: FilmLabFlag?
    let press: (FilmLabFlag) -> Void

    var body: some View {
        HStack(spacing: MacMetric.pt(4)) {
            ForEach(FilmLabFlag.allCases, id: \.self) { f in
                let on = flag == f
                Button { press(f) } label: {
                    HStack(spacing: MacMetric.pt(4)) {
                        Image(systemName: f.symbol).font(.system(size: MacMetric.pt(9), weight: .bold))
                        Text(f.title).font(MacMetric.font(11.5, on ? .semibold : .regular)).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(on ? Theme.onSelection : Theme.secondaryText)
                    .padding(.horizontal, MacMetric.pt(8)).frame(height: MacMetric.pt(22))
                    .background(on ? (f == .pick ? Theme.selection : Theme.danger) : Theme.card,
                                in: RoundedRectangle(cornerRadius: MacMetric.pt(6), style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(f.title + (f == .pick ? " (P / Z)" : " (X)"))
                .accessibilityLabel(f.title)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("filmlab.flag.chip.\(f.rawValue)")
            }
        }
        .fixedSize()
    }
}

/// Under a frame of the strip, beside the stars: the flag that is set; with none, a faint flag to press for 留用.
struct FilmLabFlagMark: View {
    let flag: FilmLabFlag?
    /// The pointer is over the frame: an empty mark shows where to press.
    let hovering: Bool
    let press: () -> Void

    var body: some View {
        Button(action: press) {
            Image(systemName: flag == .reject ? "xmark" : (flag == .pick ? "flag.fill" : "flag"))
                .font(.system(size: MacMetric.pt(8.5), weight: .bold))
                .foregroundStyle(flag == .pick ? Theme.text : flag == .reject ? Theme.danger : Theme.dim)
                .opacity(flag != nil || hovering ? 1 : 0)
                .frame(width: MacMetric.pt(13), height: MacMetric.pt(12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(flag?.title ?? FilmLabFlag.pick.title + " (P / Z)")
        .accessibilityLabel(flag?.title ?? L("Flag"))
    }
}

/// A photo's menu: 旗标 ▸ 留用 · 不要 · 取消旗标, for `images`.
struct FilmLabFlagItems: View {
    let images: [MacImage]

    var body: some View {
        Menu(L("Flag")) {
            Button(FilmLabFlag.pick.title) { FilmLabFlags.shared.set(.pick, for: images) }
            Button(FilmLabFlag.reject.title) { FilmLabFlags.shared.set(.reject, for: images) }
            Divider()
            Button(L("Remove Flag")) { FilmLabFlags.shared.set(nil, for: images) }
        }
    }
}

/// P / Z, X and U on the chosen pictures (`MainWindowLayout`, beside the rating's digits).
struct FilmLabFlagKeys: View {
    let store: any MacLibraryData
    let enabled: Bool
    /// Registered a turn after the window's own keys, so P is the flag's and not the Light Table's.
    @State private var late = false

    var body: some View {
        ZStack {
            Color.clear.frame(width: 0, height: 0)
                .onAppear {
                    FilmLabFlags.shared.attach(store)
                    DispatchQueue.main.async { late = true }
                }
            if late {
                // One owner for both plain keys: P stays canonical in the menu, whose title also shows Z.
                // The registry's default typing guard applies to both; modified Z remains Undo / Redo's.
                MacKeyRegistration(specs: [MacKeySpec(input: "p"), MacKeySpec(input: "z")],
                                   title: FilmLabFlag.pick.title + " (P / Z)", enabled: enabled) { apply(.pick) }
                    .frame(width: 0, height: 0).accessibilityHidden(true)
                HiddenKeyEquivalent(title: FilmLabFlag.reject.title, key: "x", enabled: enabled) { apply(.reject) }
                HiddenKeyEquivalent(title: L("Remove Flag"), key: "u", enabled: enabled) { apply(nil) }
            }
        }
        .accessibilityHidden(true)
    }

    private func apply(_ flag: FilmLabFlag?) {
        let chosen = MacLibraryBrowser.shared.selection
        let images = store.images.filter { chosen.contains($0.id) }
        guard !images.isEmpty else { return }
        FilmLabFlags.shared.set(flag, for: images)
    }
}
