//  FilmLabGradeTabs.swift — 二级调色's chip tabs (FilmLab 暗房, design A; the owner chose it 2026-11-23):
//  调整 · 曲线 · 颗粒·光晕 · 局部, a row of chips at the top of the grading column, each showing its part of the column.
//
//  调整 is Adjust's tools without the curve; 曲线 the curve alone, open; 颗粒·光晕 the film's effects (they moved here from
//  导出 › 格式, `DevelopWorkspace.gradingHasEffects`), with 底片画幅 above the sliders; 局部 points at the 图层 panel over
//  it, where a sky, a person, a subject, a brush or a gradient is added and picked — a picked mask layer's page takes
//  the column, as before.
//  The tab is kept across launches.

import SwiftUI

enum FilmLabGradeTab: String, CaseIterable, Identifiable {
    case adjust, curve, effects, local
    var id: String { rawValue }

    var title: String {
        switch self {
        case .adjust: L("Adjust")
        case .curve: L("Curve")
        case .effects: L("Grain · Halation")
        case .local: L("Local")
        }
    }

    /// The tabs this build shows: the effects only where the grading column carries them.
    static var shown: [FilmLabGradeTab] {
        DevelopWorkspace.gradingHasEffects ? allCases : allCases.filter { $0 != .effects }
    }

    /// Which of Adjust's tools the tab shows.
    func shows(_ tool: AdjustTool) -> Bool {
        switch self {
        case .adjust: tool != .curve
        case .curve: tool == .curve
        case .effects, .local: false
        }
    }
}

@MainActor
@Observable
final class FilmLabGradeState {
    static let shared = FilmLabGradeState()
    private static let key = "filmlab.grade.tab"

    var tab: FilmLabGradeTab {
        didSet {
            UserDefaults.standard.set(tab.rawValue, forKey: Self.key)
            if tab == .curve { AdjustLayout.shared.show(.curve) }
        }
    }

    private init() {
        tab = FilmLabPersonalizeCheck.gradeTab
            ?? UserDefaults.standard.string(forKey: Self.key).flatMap(FilmLabGradeTab.init(rawValue:)) ?? .adjust
    }
}

/// The chips, in a row under the 图层 panel, a hairline under them.
struct FilmLabGradeTabs: View {
    static let height: CGFloat = 44

    var body: some View {
        let state = FilmLabGradeState.shared
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(FilmLabGradeTab.shown) { t in
                    let on = state.tab == t
                    Button { state.tab = t } label: {
                        Text(t.title).font(Theme.Font.ui(12, on ? .semibold : .medium)).lineLimit(1)
                            .foregroundStyle(on ? Theme.onSelection : Theme.secondaryText)
                            .padding(.horizontal, 11).frame(height: 24)
                            .background(on ? Theme.selection : Theme.card, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("filmlab.grade.tab.\(t.rawValue)")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: Self.height - 0.5)
            Rectangle().fill(Theme.rule).frame(height: 0.5)
        }
    }
}

/// The film's physical format belongs with its grain and halation, not the decorations in 个性化.
/// The edge's camera owns the scale while on; keep that a reading, with no disabled cards to tap.
struct FilmLabFilmFormatSection: View {
    let session: OpenFrameSession
    let frame: LibraryFrame
    @Environment(AppSettings.self) private var settings
    @AppStorage("filmlab.grade.filmFormat.collapsed") private var folded = true

    private var isFolded: Bool { folded && !FilmLabPersonalizeCheck.gradeFormat }

    var body: some View {
        if !FeatureFlags.simpleWindow, frame.pair == nil, session.pair == nil {
            VStack(spacing: 0) {
                if session.edit.filmEdge.effective {
                    Text(L("Follows the film edge: \(session.edit.filmEdge.format.everydayName)"))
                        .font(Theme.Font.ui(12.5)).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ColumnSectionHeader(title: L("Film format"), folded: isFolded, id: "film-format",
                                        value: Self.cardName(FilmFrame.named(session.edit.params.filmFrame)),
                                        toggleFold: { folded.toggle() })
                    Text(L("Smaller film, coarser grain and wider halation."))
                        .font(Theme.Font.ui(11.5)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.bottom, 8)
                    if !isFolded {
                        FilmSizeSection(session: session, frame: frame, controlsOnly: true, cardName: Self.cardName)
                    }
                }
            }
            .accessibilityIdentifier("filmlab.grade.film-format")
            .task(id: frame.id) { await FilmLabPersonalizeCheck.applyEdge(session, frame: frame, body: settings.bodySeed) }
        }
    }

    private static func cardName(_ frame: FilmFrame) -> String {
        switch frame.id {
        case "8mm": L("8mm movie")
        case "110": L("110 pocket film")
        case "135": L("35mm full frame")
        case "120": L("120 medium format")
        case "4x5": L("4×5 large format")
        default: frame.title
        }
    }
}

/// 局部: where local adjustments are made — the 图层 panel over the column.
struct FilmLabLocalHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.3.layers.3d.top.filled").font(.system(size: 15)).foregroundStyle(Theme.accent)
                Text(L("Local adjustments are layers")).font(Theme.Font.ui(13, .semibold)).foregroundStyle(Theme.text)
            }
            Text(L("In Layers above, add Subject, Background or People, or paint one with the brush, a linear or a radial gradient. Pick the layer, and its own adjustments take this column."))
                .font(Theme.Font.ui(12)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
