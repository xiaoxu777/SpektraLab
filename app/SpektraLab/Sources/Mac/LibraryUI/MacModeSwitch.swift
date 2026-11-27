//  MacModeSwitch.swift — 图库 · 冲洗 · 编辑, one row for the whole window (the owner, 2026-10-26).
//
//  Capture One's one window: the picture in the middle, the library at the right, and the tools at the
//  left under whichever tool the person is using. The mode is that row — the develop page's column
//  header wears it (冲洗/编辑 here, 图库 leading back to the library), and the library page's column
//  wears the same one, so the window's three faces are one control wherever the person stands.
//
//  Drawn as the develop page's `surfaceSwitch` has been since 2026-10-19: a card capsule, the mode in
//  front wearing the white selection. Mac only; the window and the reference device keep 冲洗 · 编辑.

import SwiftUI

enum WorkspaceMode: String, CaseIterable, Hashable {
    /// FilmLab's order (the owner, 2026-11-23): 二级调色 straight after 冲洗, 导出 last; 个性化 (the film edge, the date
    /// back, the watermark) before 导出 since 2026-11-25 ("把片边和日期后背加到导出前面吧，命名为个性化").
    case library, develop, edit, personalize, export

    var title: String {
        switch self {
        case .library: L("Library")
        case .develop: L("Develop")
        case .export: L("Export")
        case .personalize: L("Personalize")
        // FilmLab: 编辑 is 二级调色, the grading after the film (the owner, 2026-11-23).
        case .edit: L("Grading")
        }
    }

    /// The modes the row offers: FilmLab's simple window leaves 编辑 out (`FeatureFlags.simpleWindow`).
    static var shown: [WorkspaceMode] { FeatureFlags.simpleWindow ? [.library, .develop, .personalize, .export] : allCases }
}

/// `current` wears the white capsule; `choose` is what a press asks for (`.library` pops the window back
/// to the library, where that mode is not a page state but the page). `enabled` is the page's: the
/// library cannot open a picture it has none of (the owner, 2026-10-26).
struct MacModeSwitch: View {
    let current: WorkspaceMode
    var enabled: (WorkspaceMode) -> Bool = { _ in true }
    /// Why a mode stands down, in place (the owner, 2026-10-27: "say why in place, no silent no-op").
    var unavailable: (WorkspaceMode) -> String? = { _ in nil }
    let choose: (WorkspaceMode) -> Void
    /// Read so the row redraws when Settings turns the advanced tools on or off.
    private var showAdvanced: Bool { ProMode.shared.on }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The zero-spacing row's measured widths also locate each tab, without assuming equal label lengths.
    @State private var segmentWidths: [WorkspaceMode: CGFloat] = [:]

    var body: some View {
        let modes: [WorkspaceMode] = showAdvanced ? WorkspaceMode.allCases : [.library, .develop, .personalize, .export]
        HStack(spacing: 0) {
            ForEach(modes, id: \.self) { mode in
                let on = current == mode
                let allowed = enabled(mode)
                Button { choose(mode) } label: {
                    Text(mode.title)
                        .font(MacMetric.font(12, .medium))
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(on ? Theme.onSelection : allowed ? Theme.secondaryText : Theme.faint)
                        .frame(height: MacMetric.pt(22))
                        // Equal air round every title: 二级调色 and Personalize keep their natural font size.
                        .padding(.horizontal, MacMetric.pt(12))
                        .frame(minWidth: MacMetric.pt(48))
                        .frame(height: MacMetric.pt(30))
                        .contentShape(Rectangle())
                        // The title's colour turns as the tab slides under it (`FilmLabModePill`).
                        .animation(FilmLabModeMotion.animation(reduce: reduceMotion), value: on)
                }
                .disabled(!allowed)
                .help(allowed ? "" : (unavailable(mode) ?? ""))
                .accessibilityHint(allowed ? "" : (unavailable(mode) ?? ""))
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("mac.mode.\(mode.rawValue)")
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    segmentWidths[mode] = width
                }
            }
        }
        .padding(.horizontal, 1)
        // Design A: a rounded tab inside a rounded tray, not a capsule (2026-11-24). The tab is one shape for the row,
        // so it slides from the mode left to the mode pressed (2026-11-25, `FilmLabModeTransition.swift`).
        .background {
            if let index = modes.firstIndex(of: current), let width = segmentWidths[current],
               modes.allSatisfy({ segmentWidths[$0] != nil }) {
                let leading = modes.prefix(index).reduce(CGFloat.zero) { $0 + (segmentWidths[$1] ?? 0) }
                // Give the existing pill one measured segment's room, plus its two tray insets. Its own 1 pt
                // tab insets, shape and Reduce Motion stay intact; the outer frame and padding slide together.
                FilmLabModePill(count: 1, index: 0)
                    .frame(width: width + 2)
                    .padding(.leading, leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(FilmLabModeMotion.pill(reduce: reduceMotion), value: current)
            }
        }
        .background { RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous).fill(Theme.card).frame(height: MacMetric.pt(26)) }
        // The project name gives way first in the narrow bar; the mode labels never compress.
        .fixedSize()
    }
}

/// The surface the mode row asked for when it opened a picture from the library: read once by the develop
/// page it opens, which otherwise opens on Develop (`DevelopWorkspace`'s `onAppear`). The row says 编辑, so
/// the page it opens is the Edit surface — not the one the page happens to keep (the owner, 2026-10-26).
@MainActor
enum MacDevelopWanted {
    static var surface: DevelopSurface?
    /// FilmLab: the step the opened page stands on (`.format` for 个性化 and 导出, told apart by `FilmLabFinish`), read
    /// once with `surface`.
    static var step: DevelopStep?
}
