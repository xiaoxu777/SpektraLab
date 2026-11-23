//  FilmStrip.swift — the browser as a strip of film along the bottom of the window, in every mode.
//
//  The owner, 2026-11-23: "图像预览应该放在下面，而不是右侧，而且还应该可以快捷打分". So the pictures the browser shows
//  are one row under the picture, scrolled sideways, each with its stars under it: a click on a star rates it (the
//  chosen pictures with it, when it is one of them; the same star again takes the rating off), and 0–5 still rate
//  from the keyboard. A click chooses as the grid does (⌘ adds, ⇧ runs), so in 冲洗 it opens the picture; a double
//  click opens it from 图库. Its menu holds Copy Settings…, Paste to Selected and Paste to All.
//
//  The grid that takes the whole window (G, `MacLibraryBrowser.fullGrid`) is still the floating panel.
//
//  It runs under the picture only, never under the column at the left (the owner, 2026-11-23: "下边的照片栏不应该干扰到左侧
//  的调参数的地方"): each page puts it in its own place under its picture (`ShellFilmStrip`) — the develop page in its
//  filmstrip slot (`DevelopRegions`), the library under its viewer (`BrowserViewerSplit`) — so the column keeps the
//  window's whole height.

import SwiftUI

/// The strip as a page puts it under its picture: the store's rows, read here so the page around it is not drawn again
/// for every row that changes. Shown while the browser is on and the grid does not have the window.
struct ShellFilmStrip: View {
    /// A double click (图库: onto the develop page). Nil where a click already opens (冲洗: the chosen row is the page's).
    var open: ((MacImage) -> Void)? = nil
    @Environment(AppServices.self) private var model

    static var shown: Bool { MacLibraryBrowser.shared.viewerShown && !MacLibraryBrowser.shared.fullGrid }

    var body: some View {
        let store = MacLibraryUI.store(model)
        FilmStripBar(store: store, rows: FilmLabRollFilterState.shared.apply(store.images, library: model.library), open: { open?($0) })
            .equatable()
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct FilmStripBar: View, Equatable {
    let store: any MacLibraryData
    let rows: [MacImage]
    /// A double click: in 图库 onto the develop page; in 冲洗 the page's own.
    let open: (MacImage) -> Void

    nonisolated static func == (a: Self, b: Self) -> Bool { a.store === b.store && a.rows == b.rows }

    static var height: CGFloat { MacMetric.pt(124) }
    private static var box: CGSize { CGSize(width: MacMetric.pt(104), height: MacMetric.pt(78)) }

    private var browser: MacLibraryBrowser { .shared }
    @Environment(AppRouter.self) private var router
    @State private var lastClick: (id: MacImage.ID, at: Date)?

    var body: some View {
        HStack(spacing: 0) {
            countLabel
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: MacMetric.pt(6)) {
                        ForEach(rows) { image in
                            FilmStripCell(image: image, box: Self.box,
                                          selected: browser.selection.contains(image.id),
                                          rate: { rate(image, $0) },
                                          choose: { browser.click(image.id, command: false, shift: false, in: rows) },
                                          open: { open(image) })
                                .id(image.id)
                                .modifier(MacClick { flags in click(image, flags) })
                                .contextMenu { menu(image) }
                                .onAppear { if image.id == rows.last?.id, store.hasMore { Task { await store.loadMore() } } }
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("filmlab.strip.cell")
                        }
                    }
                    .padding(.horizontal, MacMetric.pt(8))
                    .padding(.vertical, MacMetric.pt(6))
                }
                .scrollIndicators(.automatic)
                .onChange(of: browser.focus, initial: true) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: browser.scrollTarget) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .frame(height: Self.height)
        .background(Theme.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Theme.wall).frame(height: 1) }
        .overlay {
            if rows.isEmpty {
                Text(L("No pictures here")).font(MacMetric.font(12)).foregroundStyle(Theme.dim)
            }
        }
        .accessibilityIdentifier("filmlab.strip")
    }

    /// How many, and how many chosen, at the strip's start.
    private var countLabel: some View {
        VStack(spacing: MacMetric.pt(2)) {
            Text("\(store.total)").font(MacMetric.font(15, .bold)).foregroundStyle(Theme.text).monospacedDigit()
            Text(L("pictures")).font(MacMetric.font(10)).foregroundStyle(Theme.dim)
            if browser.selection.count > 1 {
                Text(L("\(browser.selection.count) chosen")).font(MacMetric.font(10, .semibold)).foregroundStyle(Theme.accent)
                    .padding(.top, MacMetric.pt(2))
            }
        }
        .frame(width: MacMetric.pt(64))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.wall).frame(width: 1) }
    }

    private func click(_ image: MacImage, _ flags: UIKeyModifierFlags) {
        let command = flags.contains(.command), shift = flags.contains(.shift)
        let now = Date()
        if !command, !shift, let last = lastClick, last.id == image.id, now.timeIntervalSince(last.at) < 0.5 {
            lastClick = nil
            open(image)
            return
        }
        lastClick = (image.id, now)
        browser.click(image.id, command: command, shift: shift, in: rows)
    }

    /// A star clicked: this picture, or every chosen one when it is among them. The same star again clears it.
    private func rate(_ image: MacImage, _ stars: Int) {
        guard store.selectedSource?.isHelperBacked == true else { return }
        let ids = browser.selection.contains(image.id) && browser.selection.count > 1
            ? rows.filter { browser.selection.contains($0.id) }.map(\.id) : [image.id]
        let value = image.rating == stars ? 0 : stars
        Task {
            do { try await store.setRating(value, for: ids) }
            catch { MacLibraryActions.shared.refusal = error.localizedDescription }
        }
    }

    /// A colour label from the menu: this picture, or every chosen one when it is among them (as a star is).
    private func label(_ image: MacImage, _ c: MacColorLabel) {
        guard store.selectedSource?.isHelperBacked == true else { return }
        let ids = browser.selection.contains(image.id) && browser.selection.count > 1
            ? rows.filter { browser.selection.contains($0.id) }.map(\.id) : [image.id]
        Task {
            do { try await store.setColorLabel(c, for: ids) }
            catch { MacLibraryActions.shared.refusal = error.localizedDescription }
        }
    }

    @ViewBuilder private func menu(_ image: MacImage) -> some View {
        let actions = MacLibraryActions.shared
        Button(L("Open")) { open(image) }
        Divider()
        Menu(L("Rating")) {
            ForEach((0...5).reversed(), id: \.self) { r in
                Button(MacWords.rating(r)) { rate(image, r == 0 ? image.rating : r) }
            }
        }
        Menu(L("Colour Label")) {
            ForEach(MacColorLabel.allCases.filter { $0 != .unlabelled }, id: \.self) { c in
                Button(MacWords.colorName(c.rawValue)) { label(image, c) }
            }
            Divider()
            Button(L("No Label")) { label(image, .unlabelled) }
        }
        Divider()
        if let id = image.develop?.frameID {
            Button(L("Copy Settings…")) { router.present(.copySettings(id)) }
        }
        Button(L("Paste to Selected Pictures")) {
            if !browser.selection.contains(image.id) { browser.selection = [image.id]; browser.focus = image.id }
            actions.pasteRequest = .selected
        }
        Button(L("Paste to All Pictures…")) { actions.pasteRequest = .all }
    }
}

/// One frame of the strip: the picture fitted in its box, and its stars and colour label under it.
private struct FilmStripCell: View {
    let image: MacImage
    let box: CGSize
    let selected: Bool
    let rate: (Int) -> Void
    /// VoiceOver's (and any accessibility client's) press: the picture chosen, as a click; Open as a double click.
    let choose: () -> Void
    let open: () -> Void
    @Environment(FrameCatalog.self) private var library
    @Environment(AppServices.self) private var model
    @State private var hovering = false

    var body: some View {
        VStack(spacing: MacMetric.pt(3)) {
            picture
                .frame(width: box.width, height: box.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(image.fileName)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { choose() }
                .accessibilityAction(named: L("Open")) { open() }
            stars
        }
        .padding(MacMetric.pt(4))
        .background {
            RoundedRectangle(cornerRadius: MacMetric.pt(5), style: .continuous)
                .fill(selected ? Theme.card : (hovering ? Theme.card.opacity(0.5) : .clear))
                // Design A: selection is the white frame, never the accent (the accent is for actions and stars).
                .overlay(RoundedRectangle(cornerRadius: MacMetric.pt(5), style: .continuous)
                    .strokeBorder(selected ? Theme.selectionFrame : .clear, lineWidth: 1.5))
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var picture: some View {
        if let id = image.develop?.frameID, let kept = library.frame(id) {
            let frame = MacShownFrame.of(kept, model: model)
            let a = MacShownFrame.aspect(frame)
            let fit = box.width / box.height > a ? CGSize(width: box.height * a, height: box.height)
                                                 : CGSize(width: box.width, height: box.width / a)
            FrameView(frame: frame, pointSize: max(fit.width, fit.height), contentMode: .fit)
                .frame(width: fit.width, height: fit.height)
                .overlay { MacDevelopVeil(frame: frame, ring: MacMetric.pt(14)) }
        } else {
            MacFileThumb(url: image.url, box: box)
        }
    }

    /// Five stars, the set ones filled; shown faint until the pointer is over the frame or it has a rating.
    private var stars: some View {
        HStack(spacing: MacMetric.pt(1)) {
            ForEach(1...5, id: \.self) { s in
                Button { rate(s) } label: {
                    Image(systemName: s <= image.rating ? "star.fill" : "star")
                        .font(.system(size: MacMetric.pt(9), weight: .semibold))
                        .foregroundStyle(s <= image.rating ? Theme.accent : Theme.dim)
                        .frame(width: MacMetric.pt(12), height: MacMetric.pt(12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MacWords.rating(s))
            }
            if image.colorLabel != nil {
                MacColorTag(label: image.colorLabel).padding(.leading, MacMetric.pt(3))
            }
        }
        .opacity(hovering || image.rating > 0 || selected ? 1 : 0.35)
        .frame(height: MacMetric.pt(12))
    }
}
