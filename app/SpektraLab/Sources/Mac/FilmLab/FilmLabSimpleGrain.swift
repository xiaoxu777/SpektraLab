//  FilmLabSimpleGrain.swift — 颗粒, one slider in 普通版's 冲洗 column: a row of its own, pinned at the column's foot
//  (`PadDevelopPage.columnPanel`), on show whatever Decode's fold and the column's scroll (the owner, 2026-11-25).
//
//  The owner, 2026-11-25: "普通版也应该具备添加胶片颗粒的能力，这个功能很重要。" The slider is the very value 专业版's
//  颗粒·光晕 tab edits (`params.effects.grain`, `grain_amount`): 0 is off, 1× the film's own grain, 2× twice it, so
//  switching to 专业版 shows the same number and 导出 carries it. Grain's other settings are the film's own — its size
//  follows the film's format, its three sub-layers stay as set — so one number gives a grain that looks like the film's
//  across the whole range. The row is a `ValueSlider` with its ↺ beside it.

import SwiftUI

struct FilmLabSimpleGrain: View {
    let session: OpenFrameSession

    private var appliesFilm: Bool { session.edit.appliesFilm }
    private var moved: Bool { session.edit.params.effects.grain != EffectStrengths.default.grain }

    /// Reads and writes `effects.grain`; moving it from 0 also switches grain on, should it have been off.
    private var grain: Binding<Double> {
        Binding(get: { session.edit.params.effects.grain },
                set: { v in
                    session.change {
                        $0.params.effects.grain = v
                        if v > 0 { $0.params.grainActive = true }
                    }
                })
    }

        var body: some View {
        VStack(spacing: 0) {
            FoldRule()
            HStack(spacing: 6) {
                EditSlider(title: L("Grain"), value: grain, range: EffectStrengths.grainRange, rest: EffectStrengths.default.grain,
                           text: { $0 <= 0.001 ? L("Off") : Fmt.times($0) },
                           detentAtRest: true, editing: session.editing(.shoot))
                    .accessibilityIdentifier("filmlab.simple.grain")
                RoundButton(diameter: 22, label: L("Reset") + " " + L("Grain"), action: {
                    session.change { $0.params.effects.grain = EffectStrengths.default.grain }
                }) {
                    Icon(.reset, size: 13)
                }
                .rowEnabled(appliesFilm && moved)
                .accessibilityIdentifier("filmlab.simple.grain.reset")
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
        .rowEnabled(appliesFilm)
        .onAppear { Self.checkSetOnce(session) }
    }

    /// A check's launch only (`--filmlab-grain-check <amount>`): the grain set once when the row first shows, as the
    /// slider would, for a screenshot (a run in a scratch home — `CFFIXED_USER_HOME` — so no real photo is touched).
    private static var checked = false
    private static func checkSetOnce(_ session: OpenFrameSession) {
        guard !checked, let v = FilmLabCheckArgs.value("--filmlab-grain-check").flatMap(Double.init) else { return }
        checked = true
        session.change { $0.params.effects.grain = v; if v > 0 { $0.params.grainActive = true } }
    }
}
