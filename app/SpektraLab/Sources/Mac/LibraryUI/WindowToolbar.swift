//  WindowToolbar.swift — the window's one top bar, and the floating browser it collapses (the owner,
//  2026-10-27).
//
//  "Always have those buttons at the very right, and treat the library as something collapsible and
//  below it, somewhat floating, but no liquid glass effects." One bar runs the window's whole width in
//  every mode — 图库, 冲洗 and 编辑 alike: the shared controls (column, split, loupe, 裁剪, sort,
//  direction) at its leading edge, the picture's actions (undo, redo, ⋯, paste, compare, Export) pinned
//  to the window's trailing edge, and the browser's toggle last. Nothing the browser's width does can
//  clip or move them, and nothing moves when the mode row is pressed.
//
//  The browser is a panel below that bar, inset from the window's edges, its own rounded solid ground
//  with a hairline and a soft shadow — no material, no blur. Its header (the count and what is chosen,
//  the thumbnails' size, the search) is inside it, at its top. Its leading edge is dragged for its
//  width (kept, `MacLibraryBrowser.browserWidth`); ⌥⌘B or the bar's toggle puts it away, and the
//  picture takes the room.

import SwiftUI

/// Intrinsic widths, in the bar's own points. The probes report labels, never another live button or popover.
enum WindowBarPiece: Hashable {
    case home, title, sidebar, mode, actions, edition, export, strip
    case cropFull, cropCompact, copyFull, copyCompact, pasteFull, pasteCompact
}

struct WindowBarMeter {
    let report: (WindowBarPiece, CGFloat) -> Void
}

private struct WindowBarInputs: Equatable {
    let width: CGFloat
    let hasCrop: Bool
    let hasClipboard: Bool
    let hasExport: Bool
    let hasStrip: Bool
    let centreAllowed: Bool
}

/// Plain reference storage on purpose: a geometry callback may change these numbers at every resize step,
/// but no body observes them. Only a different fitting level or centring answer writes SwiftUI state.
@MainActor
private final class WindowBarWidths {
    var inputs: WindowBarInputs?
    var pieces: [WindowBarPiece: CGFloat] = [:]

    func budget(level: Int) -> (required: CGFloat, centreClearance: CGFloat)? {
        guard let inputs else { return nil }
        var needed: [WindowBarPiece] = [.home, .title, .sidebar, .mode, .actions, .edition]
        if inputs.hasCrop { needed += [.cropFull, .cropCompact] }
        if inputs.hasClipboard { needed += [.copyFull, .copyCompact, .pasteFull, .pasteCompact] }
        if inputs.hasExport { needed += [.export] }
        if inputs.hasStrip { needed += [.strip] }
        guard needed.allSatisfy({ pieces[$0] != nil }) else { return nil }
        func width(_ part: WindowBarPiece) -> CGFloat { pieces[part] ?? 0 }

        let gap = MacMetric.pt(level == 4 ? 4 : 10)
        let title = level == 4 ? 0 : min(width(.title), MacMetric.pt(level == 0 ? 160 : 60))
        var left = width(.home) + gap + width(.sidebar)
        if inputs.hasCrop { left += MacMetric.pt(8) + width(level >= 3 ? .cropCompact : .cropFull) }
        if title > 0 { left += gap + title }

        var right = width(.actions) + gap + width(.edition)
        if inputs.hasClipboard {
            right += width(level >= 2 ? .copyCompact : .copyFull)
                + width(level >= 2 ? .pasteCompact : .pasteFull) + 2 * gap
        }
        if inputs.hasExport { right += gap + width(.export) }
        if inputs.hasStrip { right += gap + width(.strip) }

        // Three outer gaps: left → mode → spacer → right. The title/crop/clipboard and right-hand groups'
        // internal gaps are counted above. The edges are the actual, unscaled `.padding(.horizontal, 12)`.
        let required = 24 + left + width(.mode) + right + 3 * gap + MacMetric.pt(8)
        // The mode's half-width must clear BOTH flanks, not just fit the sum of the row's widths.
        let clearance = (inputs.width - 24 - width(.mode)) / 2 - max(left, right) - gap
        return (required, clearance)
    }
}

/// The window's top bar: `controls` at the leading edge, `actions` at the trailing one, then the
/// browser's toggle.
struct WindowToolbar<Controls: View, Mode: View, Actions: View>: View {
    let browser: MacLibraryBrowser
    /// FilmLab 暗房 (design A): 导出 at the bar's end, going to the 导出 mode; nil where it has nowhere to go (in 导出).
    var export: (() -> Void)? = nil
    /// The strip's toggle: 冲洗, 二级调色 and 导出 have the strip; 图库's grid is its own browser.
    var stripToggle = true
    var hasCrop = false
    var hasClipboard = true
    @ViewBuilder var controls: (Int, WindowBarMeter) -> Controls
    /// 图库 · 冲洗 · 编辑 (`MacModeSwitch`, the owner, 2026-10-27): centred in the window where the window
    /// clears `centreFrom` and both measured flanks, else right after the shared controls.
    @ViewBuilder var mode: Mode
    @ViewBuilder var actions: (Int, WindowBarMeter) -> Actions

    @AppStorage(InterfaceScale.key) private var scaleChoice = InterfaceScale.standard.rawValue
    /// The page's factor round the bar (`interfaceScaled(.macPoints)`): window points per bar point.
    @Environment(\.interfaceFactor) private var factor
    /// Whether the mode row stands in the window's centre (`centred(width:)`), kept as the answer and not as the
    /// width (2026-11-22): the bar read the window's size, so every step of a window resize re-made the bar and
    /// what it holds. Now a resize changes it only where it crosses the centre/measured-fit boundaries.
    @State private var centred = false
    /// Start with the narrow row until its intrinsic widths arrive. Levels: natural title; 60 pt title;
    /// icon-only clipboard; icon-only crop; no title. Level 4 also retains the narrow row's 4 pt gaps.
    @State private var compact = 4
    @State private var widths = WindowBarWidths()

    /// The bar's height, one in every mode.
    static var height: CGFloat { MacMetric.pt(35) }   // 44 until 2026-11-16: the owner asked for ~20 % less
    /// The window width (Mac points, at 100 %) from which the mode row stands in the window's centre
    /// (decided 2026-10-27). At a larger interface scale everything is larger, so the threshold is too.
    static var centreFrom: CGFloat { 1200 }

    private func reportWidth(_ part: WindowBarPiece, _ width: CGFloat) {
        guard widths.pieces[part] != width else { return }
        widths.pieces[part] = width
        updateLayout()
    }

    private func updateLayout() {
        guard let inputs = widths.inputs, inputs.width > 0,
              let current = widths.budget(level: compact) else { return }
        let slack = MacMetric.pt(16)
        var next = compact
        if current.required > inputs.width {
            // Tighten as soon as the current row would overflow. A roomier row must earn the slack back,
            // so rounding or a one-point resize cannot bounce between two neighbouring levels.
            next = (0...4).first { (widths.budget(level: $0)?.required ?? .infinity) <= inputs.width } ?? 4
        } else {
            for level in 0..<compact {
                if let budget = widths.budget(level: level), budget.required + slack <= inputs.width {
                    next = level
                    break
                }
            }
        }
        if next != compact { compact = next }
        if let budget = widths.budget(level: next) {
            let now = inputs.centreAllowed && budget.centreClearance >= 0
            if now != centred { centred = now }
        }
    }

    /// The bar is the window's width: `width` bar points are `width × factor` window points, which are the
    /// scene points `WindowShape` measures the window in over the page's own factor (`followsWindow`).
    private func centred(width: CGFloat) -> Bool {
        guard width > 0 else { return true }
        let scale = InterfaceScale(rawValue: scaleChoice) ?? .standard
        let choice = CGFloat(scale.rawValue) / 100
        let windowWidth = width * factor / scale.factor(.padPoints)
        return windowWidth * MacMetric.scale >= Self.centreFrom * choice
    }

    var body: some View {
        // Passing a reporter does not read the reference box's contents in body.
        let meter = WindowBarMeter(report: reportWidth)
        let gap = MacMetric.pt(compact == 4 ? 4 : 10)
        ZStack {
            // A project opening: the bar's groups arrive from the left, 35 ms apart (`FilmLabLibraryEntrance`); at any
            // other time they are simply there.
            HStack(spacing: gap) {
                HStack(spacing: gap) {
                    FilmLabHomeButton().fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { meter.report(.home, $0) }
                        .filmLabArrive(0)
                    HStack(spacing: gap) { controls(compact, meter) }.fixedSize().filmLabArrive(1)
                }
                // MacModeSwitch keeps its labels' intrinsic widths at every compact level.
                if !centred { measuredMode(meter).filmLabArrive(3) }
                Spacer(minLength: MacMetric.pt(8))
                HStack(spacing: gap) {
                    HStack(spacing: gap) { actions(compact, meter) }.fixedSize().filmLabArrive(5)
                    ProModeSwitch().fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { meter.report(.edition, $0) }
                        .filmLabArrive(6)
                    if let export {
                        FilmLabExportButton(action: export).fixedSize()
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { meter.report(.export, $0) }
                            .filmLabArrive(7)
                    }
                    if stripToggle {
                        browserToggle.fixedSize()
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { meter.report(.strip, $0) }
                            .filmLabArrive(8)
                    }
                }.fixedSize()
            }
            if centred { measuredMode(meter).filmLabArrive(3) }
        }
        // Measure the room offered by the window, not an over-wide row's ideal size. Compaction must not feed
        // its own contents' width back into the next threshold decision; this frame does not clip the row.
        .frame(minWidth: 0, maxWidth: .infinity)
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background(Theme.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.wall).frame(height: 1) }
        .onGeometryChange(for: WindowBarInputs.self) { room in
            WindowBarInputs(width: room.size.width, hasCrop: hasCrop, hasClipboard: hasClipboard,
                            hasExport: export != nil, hasStrip: stripToggle, centreAllowed: centred(width: room.size.width))
        } action: { inputs in
            widths.inputs = inputs
            updateLayout()
        }
    }

    private func measuredMode(_ meter: WindowBarMeter) -> some View {
        mode.fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { meter.report(.mode, $0) }
    }

    /// The browser, there or not: its icon mirrors the column's (`sidebar.right`, as the old column
    /// toggle had it). ⌘B, with ⌥⌘B retained as an alias; ⌘T folds the column.
    private var browserToggle: some View {
        Button { withAnimation(.smooth(duration: 0.2)) { browser.viewerShown.toggle() } } label: {
            // FilmLab: the browser is the strip along the bottom (`FilmStripBar`).
            Image(systemName: browser.viewerShown ? "rectangle.bottomthird.inset.filled" : "rectangle")
                .font(MacMetric.font(14))
                .foregroundStyle(browser.viewerShown ? Theme.text : Theme.secondaryText)
                .frame(width: MacMetric.pt(26), height: MacMetric.pt(22))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(browser.viewerShown ? L("Hide the filmstrip (⌘B)") : L("Show the filmstrip (⌘B)"))
        .accessibilityLabel(L("Browser"))
        .accessibilityIdentifier("mac.bar.browser")
        // The shell registers Browser once, alongside its menu command (MacShortcuts).
        .padding(.leading, MacMetric.pt(4))
    }
}

/// The browser as the window draws it: a floating card at the trailing edge, under the top bar.
struct FloatingBrowser<Content: View>: View {
    let browser: MacLibraryBrowser
    /// The most the panel may take, in this page's points: the window less the column and the least the
    /// picture keeps (`FloatingBrowser.limit`). A kept width wider than this is drawn at this, unchanged
    /// in the defaults — a narrower window never pushes the page off its edges (2026-10-27: at 900 Mac
    /// points the row overflowed the window both ways).
    var limit: CGFloat = .infinity
    /// The grid has the window (`MacLibraryBrowser.fullGrid`): the card fills what it is given, no grip.
    var full = false
    @ViewBuilder var content: Content

    @State private var drag: CGFloat?

    /// The panel's room in a window `width` wide beside a column `column` wide (both this page's points).
    static func limit(width: CGFloat, column: CGFloat) -> CGFloat {
        max(width - column - MacMetric.pt(320) - 8, MacMetric.pt(MacMetric.browserRange.lowerBound))
    }

    var body: some View {
        content
            .frame(width: full ? nil : min(MacMetric.pt(browser.browserWidth), limit))
            .frame(maxWidth: full ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.panel))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.wall, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
            .overlay(alignment: .leading) { if !full { grip } }
            .padding(.trailing, 8)
            .padding(.bottom, 8)
    }

    /// The panel's leading edge, dragged for its width (a drag to the left makes it wider), 240 to 900
    /// Mac points, the same as the wall it replaces.
    private var grip: some View {
        Color.clear
            .frame(width: MacMetric.pt(9))
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            // Measured in the window: the grip rides the edge it drags, so its own space moves under the
            // pointer and the width shook back and forth (the owner, 2026-10-27).
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    if drag == nil { drag = min(browser.browserWidth, limit * MacMetric.scale) }
                    let start = drag ?? browser.browserWidth
                    let w = start - v.translation.width * MacMetric.scale
                    let most = min(MacMetric.browserRange.upperBound, limit * MacMetric.scale)
                    browser.browserWidth = min(max(w, MacMetric.browserRange.lowerBound), max(most, MacMetric.browserRange.lowerBound))
                }
                .onEnded { _ in
                    drag = nil
                    browser.saveWidths()
                })
            .accessibilityLabel(L("Browser width"))
    }
}
