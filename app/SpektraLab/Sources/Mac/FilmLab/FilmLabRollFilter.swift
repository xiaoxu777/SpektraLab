//  FilmLabRollFilter.swift — 图库's quick filters over the roll in front (design A, the owner chose it 2026-11-23):
//  全部 · 打过星的 · 精选 ★4+ · 还没冲洗 · 已导出, each with its count, at the top of the sidebar.
//
//  They narrow what is loaded (`MacLibraryData.images`), on this Mac, and both the 图库 grid and the strip under the
//  picture show the narrowed rows. The store's own filters (the Filters tab) still narrow what is loaded first.
//  还没冲洗 is a picture never opened in 冲洗 (no frame, or a frame never developed); 已导出 is one the export batch
//  saved (`FilmLabExportLog`).
//
//  留用 and 不要 (2026-11-25) are the flags (`FilmLabFlags`); "隐藏不要的" takes the photos not wanted out of every other
//  filter's rows (kept for this Mac in `filmlab.library.hideRejected`), offered once a photo of the roll is flagged so.

import SwiftUI

enum FilmLabRollFilter: String, CaseIterable, Identifiable {
    case all, rated, picks, flagged, rejected, undeveloped, exported
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L("All Pictures")
        case .rated: L("Rated")
        case .picks: L("Picks ★4+")
        case .flagged: L("Kept")
        case .rejected: L("Rejected")
        case .undeveloped: L("Not Developed Yet")
        case .exported: L("Exported")
        }
    }

    var symbol: String {
        switch self {
        case .all: "photo.on.rectangle"
        case .rated: "star"
        case .picks: "star.fill"
        case .flagged: "flag"
        case .rejected: "xmark"
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
        case .flagged: return FilmLabFlags.shared.flag(row) == .pick
        case .rejected: return FilmLabFlags.shared.flag(row) == .reject
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
    /// The colour label the sidebar's dots narrow to, on top of `current`; nil for any.
    var label: MacColorLabel?
    /// The dots, in the design's order (the five of the strip's menu and keys 6–9).
    static let labels: [MacColorLabel] = [.red, .yellow, .green, .blue, .purple]

    /// The photos flagged 不要 are left out of the rows (of every filter but 不要 itself). Kept for this Mac.
    static let hideRejectedKey = "filmlab.library.hideRejected"
    var hideRejected = UserDefaults.standard.bool(forKey: FilmLabRollFilterState.hideRejectedKey) {
        didSet { if hideRejected != oldValue { UserDefaults.standard.set(hideRejected, forKey: Self.hideRejectedKey) } }
    }

    /// `rows` as the filter in front leaves them.
    func apply(_ rows: [MacImage], library: FrameCatalog) -> [MacImage] {
        let hides = hideRejected && current != .rejected && FilmLabFlags.shared.count(.reject, in: rows) > 0
        guard current != .all || label != nil || hides else { return rows }
        let f = current, label = label
        _ = FilmLabExportLog.shared.exported   // read: an export landing narrows 已导出 again
        let flags = FilmLabFlags.shared
        return rows.filter {
            f.matches($0, library: library) && (label == nil || $0.colorLabel == label) && !(hides && flags.flag($0) == .reject)
        }
    }
}

/// The sidebar's 这一卷 block: one row per filter, its count at the trailing edge, the one in front on the card.
struct FilmLabRollFilters: View {
    let rows: [MacImage]
    @Environment(FrameCatalog.self) private var library

    var body: some View {
        let state = FilmLabRollFilterState.shared
        let _ = FilmLabExportLog.shared.exported
        VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: MacMetric.pt(1)) {
            Text(L("This Roll")).font(MacMetric.font(11, .semibold)).foregroundStyle(Theme.dim)
                .padding(.horizontal, MacMetric.pt(8)).padding(.bottom, MacMetric.pt(3))
                .filmLabArrive(2)
            ForEach(Array(FilmLabRollFilter.allCases.enumerated()), id: \.element) { n, f in
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
                .filmLabArrive(3 + n)
            }
            hideRejectedRow
        }
        .padding(.horizontal, MacMetric.pt(6))
        .padding(.top, MacMetric.pt(6))
        labelDots.filmLabArrive(11)
        }
    }

    /// "隐藏不要的": a tick under the filters, there once the roll has a photo flagged 不要 (or while it is on).
    @ViewBuilder private var hideRejectedRow: some View {
        let state = FilmLabRollFilterState.shared
        if state.hideRejected || FilmLabFlags.shared.count(.reject, in: rows) > 0 {
            Button { state.hideRejected.toggle() } label: {
                HStack(spacing: MacMetric.pt(7)) {
                    FilmLabCheckMark(on: state.hideRejected, size: 12).frame(width: MacMetric.pt(16))
                    Text(L("Hide Rejected")).font(MacMetric.font(12)).foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, MacMetric.pt(8))
                .frame(height: MacMetric.pt(26))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(state.hideRejected ? .isSelected : [])
            .accessibilityIdentifier("filmlab.roll-filter.hide-rejected")
        }
    }

    /// 色标: a dot per colour; one clicked narrows the grid and the strip to it, clicked again lets go.
    private var labelDots: some View {
        let state = FilmLabRollFilterState.shared
        return VStack(alignment: .leading, spacing: MacMetric.pt(6)) {
            Text(L("Colour Label")).font(MacMetric.font(11, .semibold)).foregroundStyle(Theme.dim)
            HStack(spacing: MacMetric.pt(10)) {
                ForEach(FilmLabRollFilterState.labels, id: \.self) { label in
                    let on = state.label == label
                    Button { state.label = on ? nil : label } label: {
                        Circle().fill(MacWords.color(label.rawValue) ?? Theme.dim)
                            .frame(width: MacMetric.pt(12), height: MacMetric.pt(12))
                            .padding(MacMetric.pt(3))
                            .overlay { if on { Circle().strokeBorder(Theme.text, lineWidth: 1.5) } }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(MacWords.colorName(label.rawValue))
                    .accessibilityLabel(MacWords.colorName(label.rawValue))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, MacMetric.pt(14))
        .padding(.top, MacMetric.pt(8)).padding(.bottom, MacMetric.pt(10))
    }
}
