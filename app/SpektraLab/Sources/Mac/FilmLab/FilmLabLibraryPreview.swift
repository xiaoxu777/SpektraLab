//  FilmLabLibraryPreview.swift — 图库: the chosen photo large at the right of the grid.
//
//  The owner, 2026-11-25: "应该选择图像后右侧可以阅览照片". With a photo chosen the page's centre is grid | preview, a line
//  between them that is dragged; with nothing chosen (or the preview switched off: the grid header's button, ⌥⌘V) the
//  grid has the whole width. The picture is `BrowserViewerSplit`'s — the frame's develop where the photo has been
//  opened in 冲洗, else the file's own preview, exactly what its cell shows, larger — and under it FilmLab's own two
//  lines: the name, 留用 / 不要, the stars and the label; then the exposure, the lens and the film. A double click
//  opens 冲洗, as a cell's does; the arrows walk the roll through the grid's selection.
//
//  The split is a `Layout` over a kept share of the width (`FilmLabLibraryLayout.previewShare`), so a window resize
//  writes no state and re-makes nothing but the grid's own reader, as before.

import SwiftUI

/// What 图库's centre keeps for this Mac: whether the preview is offered, and its share of the width.
@MainActor
@Observable
final class FilmLabLibraryLayout {
    static let shared = FilmLabLibraryLayout()
    static let shownKey = "filmlab.library.previewShown"
    static let shareKey = "filmlab.library.previewShare"
    static let shareRange: ClosedRange<Double> = 0.25...0.8
    /// The least each side keeps, Mac points.
    static let gridLeast: CGFloat = 300
    static let previewLeast: CGFloat = 320

    var previewShown: Bool { didSet { if previewShown != oldValue { UserDefaults.standard.set(previewShown, forKey: Self.shownKey) } } }
    /// The preview's share of the centre's width. Written when a drag ends (`save`).
    var previewShare: Double

    private init() {
        let d = UserDefaults.standard
        previewShown = d.object(forKey: Self.shownKey) == nil ? true : d.bool(forKey: Self.shownKey)
        let share = d.double(forKey: Self.shareKey)
        previewShare = share > 0 ? share.clamped(to: Self.shareRange) : 0.55
    }

    func save() { UserDefaults.standard.set(previewShare, forKey: Self.shareKey) }

    /// The preview's width in a centre `room` wide (this page's points).
    static func previewWidth(room: CGFloat, share: Double) -> CGFloat {
        FilmLabLibrarySplit.previewWidth(room: room, share: share, least: MacMetric.pt(previewLeast), gridLeast: MacMetric.pt(gridLeast))
    }
}

/// grid | line | preview by the kept share; a lone subview (no preview) takes everything.
struct FilmLabLibrarySplit: Layout {
    let share: Double
    /// The least the preview and the grid keep, in this page's points (`FilmLabLibraryLayout`'s figures).
    let least: CGFloat
    let gridLeast: CGFloat

    @MainActor init(share: Double) {
        self.share = share
        least = MacMetric.pt(FilmLabLibraryLayout.previewLeast)
        gridLeast = MacMetric.pt(FilmLabLibraryLayout.gridLeast)
    }

    static func previewWidth(room: CGFloat, share: Double, least: CGFloat, gridLeast: CGFloat) -> CGFloat {
        let most = room - gridLeast
        guard most > least else { return max((room / 2).rounded(), 0) }
        return min(max((room * CGFloat(share)).rounded(), least), most)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else {
            for s in subviews { s.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
            return
        }
        let line = subviews[1].sizeThatFits(ProposedViewSize(width: nil, height: bounds.height)).width
        let preview = Self.previewWidth(room: bounds.width - line, share: share, least: least, gridLeast: gridLeast)
        let grid = max(bounds.width - line - preview, 0)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: grid, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + grid, y: bounds.minY), proposal: ProposedViewSize(width: line, height: bounds.height))
        subviews[2].place(at: CGPoint(x: bounds.minX + grid + line, y: bounds.minY),
                          proposal: ProposedViewSize(width: preview, height: bounds.height))
    }
}

/// The line between the grid and the preview: one point of wall, a 10 pt reach that takes the drag (the resize cursor,
/// a line drawn while the pointer is on it, as `DividerGrip`). Dragged left, the preview grows.
struct FilmLabPreviewGrip: View {
    /// The centre's width as last laid out, in a box nothing observes (`MacLibraryPage`).
    let room: () -> CGFloat
    @State private var base: CGFloat?
    @State private var hot = false

    var body: some View {
        let layout = FilmLabLibraryLayout.shared
        Rectangle().fill(Theme.wall).frame(width: 1)
            .overlay {
                Color.clear.frame(width: DividerGrip.reach)
                    .contentShape(Rectangle())
                    .overlay {
                        if hot || base != nil { Rectangle().fill(Theme.dim.opacity(0.8)).frame(width: 3).allowsHitTesting(false) }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { v in
                            let width = max(room() - 1, 1)
                            let start = base ?? FilmLabLibraryLayout.previewWidth(room: width, share: layout.previewShare)
                            if base == nil { base = start }
                            let least = MacMetric.pt(FilmLabLibraryLayout.previewLeast)
                            let most = max(width - MacMetric.pt(FilmLabLibraryLayout.gridLeast), least)
                            let wanted = (start - v.translation.width).clamped(to: least...most)
                            layout.previewShare = Double(wanted / width).clamped(to: FilmLabLibraryLayout.shareRange)
                            MacCursor.resize(sideways: true)
                        }
                        .onEnded { _ in
                            base = nil
                            if !hot { MacCursor.arrow() }
                            layout.save()
                        })
                    .onContinuousHover { phase in
                        switch phase {
                        case .active: hot = true; MacCursor.resize(sideways: true)
                        case .ended: hot = false; if base == nil { MacCursor.arrow() }
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(L("Preview width"))
                    .accessibilityValue("\(Int(layout.previewShare * 100)) %")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: layout.previewShare = (layout.previewShare + 0.05).clamped(to: FilmLabLibraryLayout.shareRange)
                        case .decrement: layout.previewShare = (layout.previewShare - 0.05).clamped(to: FilmLabLibraryLayout.shareRange)
                        @unknown default: return
                        }
                        layout.save()
                    }
                    .accessibilityIdentifier("filmlab.library.preview.grip")
            }
            .zIndex(1)
    }
}

/// The chosen photo, large, and what is set on it.
struct FilmLabLibraryPreview: View {
    let store: any MacLibraryData
    let rows: [MacImage]
    let open: (MacImage) -> Void

    private var browser: MacLibraryBrowser { .shared }

    var body: some View {
        let image = browser.primary(rows)
        VStack(spacing: 0) {
            BrowserViewerSplit(image: image, open: open, chosen: browser.selection.count, infoStrip: false)
            if let image { foot(image) }
        }
        .background(Theme.well)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmlab.library.preview")
    }

    /// Two lines under the picture: the name, the flag, the stars and the label; then the facts and where it is in the roll.
    private func foot(_ image: MacImage) -> some View {
        let targets = FilmLabFlagTargets.of(image, in: rows)
        let flag = FilmLabFlags.shared.flag(image)
        let editable = store.selectedSource?.isHelperBacked == true
        let place = rows.firstIndex { $0.id == image.id }.map { "\($0 + 1) / \(rows.count)" }
        let chosen = browser.selection.count
        return VStack(alignment: .leading, spacing: MacMetric.pt(6)) {
            // What does not fit is left off whole: the label first, then the stars; the name and the flag stay.
            ViewThatFits(in: .horizontal) {
                marks(image, targets, flag, editable, stars: true, label: true)
                marks(image, targets, flag, editable, stars: true, label: false)
                marks(image, targets, flag, editable, stars: false, label: false)
            }
            HStack(alignment: .firstTextBaseline, spacing: MacMetric.pt(10)) {
                // As much of the line as fits, whole parts only (no "…"): the lens goes first, then the film.
                ViewThatFits(in: .horizontal) {
                    ForEach(facts(image), id: \.self) { line in
                        Text(line).font(MacMetric.font(11)).monospacedDigit().foregroundStyle(Theme.dim).lineLimit(1).fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if chosen > 1 {
                    Text(L("\(chosen) chosen")).font(MacMetric.font(11)).monospacedDigit().foregroundStyle(Theme.secondaryText).fixedSize()
                } else if let place {
                    Text(place).font(MacMetric.font(11)).monospacedDigit().foregroundStyle(Theme.dim).fixedSize()
                }
            }
        }
        .padding(.horizontal, MacMetric.pt(14))
        .padding(.top, MacMetric.pt(8)).padding(.bottom, MacMetric.pt(11))
        .background(Theme.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Theme.wall).frame(height: 1) }
    }

    private func marks(_ image: MacImage, _ targets: [MacImage], _ flag: FilmLabFlag?, _ editable: Bool,
                       stars: Bool, label: Bool) -> some View {
        HStack(spacing: MacMetric.pt(10)) {
            Text(image.fileName).font(MacMetric.font(13, .semibold)).foregroundStyle(Theme.text)
                .lineLimit(1).fixedSize()
            Spacer(minLength: MacMetric.pt(6))
            FilmLabFlagChips(flag: flag) { FilmLabFlags.shared.toggle($0, on: image, among: targets) }
            if stars {
                HStack(spacing: 0) {
                    ForEach(1...5, id: \.self) { r in
                        Button { rate(image.rating == r ? 0 : r, targets) } label: {
                            Image(systemName: "star.fill").font(.system(size: MacMetric.pt(12.5), weight: .semibold))
                                .foregroundStyle(r <= image.rating ? Theme.accent : Theme.starOff)
                                .frame(width: MacMetric.pt(17), height: MacMetric.pt(22)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(MacWords.rating(r))
                    }
                }
                .disabled(!editable)
                .opacity(editable ? 1 : Theme.disabledOpacity)
                .fixedSize()
            }
            if label, image.colorLabel != nil { MacColorTag(label: image.colorLabel) }
        }
        .frame(height: MacMetric.pt(22))
    }

    /// "1/250 s · f/5.6 · ISO 100 · Portra 400 · XCD 45", and the same with parts left off its end, longest first.
    private func facts(_ i: MacImage) -> [String] {
        var parts = (i.exposure ?? "").components(separatedBy: " · ").filter { !$0.isEmpty }
        parts.append(i.develop?.film ?? L("Not developed"))
        // A lens the file does not name is written as dashes by some cameras: not shown.
        if let lens = i.lens, lens.contains(where: { $0.isLetter || $0.isNumber }) { parts.append(lens) }
        return (1...parts.count).reversed().map { parts.prefix($0).joined(separator: " · ") }
    }

    private func rate(_ stars: Int, _ images: [MacImage]) {
        Task {
            do { try await store.setRating(stars, for: images.map(\.id)) }
            catch { MacLibraryActions.shared.refusal = error.localizedDescription }
        }
    }
}

/// The grid header's switch for the preview: a picture with a column of thumbnails at its left, as the layout is.
struct FilmLabPreviewToggle: View {
    var body: some View {
        let layout = FilmLabLibraryLayout.shared
        Button { layout.previewShown.toggle() } label: {
            Image(systemName: "rectangle.righthalf.inset.filled").font(MacMetric.font(13))
                .foregroundStyle(layout.previewShown ? Theme.text : Theme.dim)
                .frame(width: MacMetric.pt(24), height: MacMetric.pt(22)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(layout.previewShown ? L("Hide the preview (⌥⌘V)") : L("Show the preview (⌥⌘V)"))
        .accessibilityLabel(L("Preview"))
        .accessibilityAddTraits(layout.previewShown ? .isSelected : [])
        .accessibilityIdentifier("filmlab.library.preview.toggle")
    }
}
