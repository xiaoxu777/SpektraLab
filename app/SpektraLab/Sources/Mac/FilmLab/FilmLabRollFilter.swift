//  FilmLabRollFilter.swift — 图库's quick filters over the roll in front (design A, the owner chose it 2026-11-23):
//  全部 · 打过星的 · 精选 ★4+ · 还没冲洗 · 已导出, each with its count, at the top of the sidebar.
//
//  They narrow what is loaded (`MacLibraryData.images`), on this Mac, and both the 图库 grid and the strip under the
//  picture show the narrowed rows. The store's own filters (the Filters tab) still narrow what is loaded first.
//  还没冲洗 is a picture never opened in 冲洗 (no frame, or a frame never developed); 已导出 is one the export batch
//  saved (`FilmLabExportLog`).

import SwiftUI

enum FilmLabRollFilter: String, CaseIterable, Identifiable {
    case all, rated, picks, undeveloped, exported
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L("All Pictures")
        case .rated: L("Rated")
        case .picks: L("Picks ★4+")
        case .undeveloped: L("Not Developed Yet")
        case .exported: L("Exported")
        }
    }

    var symbol: String {
        switch self {
        case .all: "photo.on.rectangle"
        case .rated: "star"
        case .picks: "star.fill"
        case .undeveloped: "circle.dashed"
        case .exported: "square.and.arrow.up"
        }
    }

    @MainActor
    func matches(_ row: MacImage, library: FrameCatalog) -> Bool {
        switch self {
        case .all: return true
        case .rated: return row.rating > 0
        case .picks: return row.rating >= 4
        case .undeveloped:
            guard let id = row.develop?.frameID, let frame = library.frame(id) else { return true }
            return frame.developed == nil
        case .exported:
            guard let id = row.develop?.frameID else { return false }
            return FilmLabExportLog.shared.wasExported(id)
        }
    }
}

/// The filter in front, for this run of the app.
@MainActor
@Observable
final class FilmLabRollFilterState {
    static let shared = FilmLabRollFilterState()
    var current: FilmLabRollFilter = .all

    /// `rows` as the filter in front leaves them.
    func apply(_ rows: [MacImage], library: FrameCatalog) -> [MacImage] {
        guard current != .all else { return rows }
        let f = current
        _ = FilmLabExportLog.shared.exported   // read: an export landing narrows 已导出 again
        return rows.filter { f.matches($0, library: library) }
    }
}

/// The sidebar's 这一卷 block: one row per filter, its count at the trailing edge, the one in front on the card.
struct FilmLabRollFilters: View {
    let rows: [MacImage]
    @Environment(FrameCatalog.self) private var library

    var body: some View {
        let state = FilmLabRollFilterState.shared
        let _ = FilmLabExportLog.shared.exported
        VStack(alignment: .leading, spacing: MacMetric.pt(1)) {
            Text(L("This Roll")).font(MacMetric.font(11, .semibold)).foregroundStyle(Theme.dim)
                .padding(.horizontal, MacMetric.pt(8)).padding(.bottom, MacMetric.pt(3))
            ForEach(FilmLabRollFilter.allCases) { f in
                let on = state.current == f
                Button { state.current = f } label: {
                    HStack(spacing: MacMetric.pt(7)) {
                        Image(systemName: f.symbol).font(MacMetric.font(11)).foregroundStyle(on ? Theme.text : Theme.dim)
                            .frame(width: MacMetric.pt(16))
                        Text(f.title).font(MacMetric.font(12.5)).foregroundStyle(on ? Theme.text : Theme.secondaryText)
                        Spacer(minLength: MacMetric.pt(6))
                        Text("\(rows.filter { f.matches($0, library: library) }.count)")
                            .font(MacMetric.font(11)).monospacedDigit().foregroundStyle(Theme.dim)
                    }
                    .padding(.horizontal, MacMetric.pt(8))
                    .frame(height: MacMetric.pt(26))
                    .background { if on { RoundedRectangle(cornerRadius: MacMetric.pt(6), style: .continuous).fill(Theme.card) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("filmlab.roll-filter.\(f.rawValue)")
            }
        }
        .padding(.horizontal, MacMetric.pt(6))
        .padding(.vertical, MacMetric.pt(6))
    }
}
