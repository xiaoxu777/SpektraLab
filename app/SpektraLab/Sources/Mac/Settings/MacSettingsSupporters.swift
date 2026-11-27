//  MacSettingsSupporters.swift — Settings › General › About › Supporters: the thanks, then each supporter.
//
//  Opened by the About group's *Supporters* row (`MacSettingsGeneral`), over the General section's place
//  on the page with a way back (`SettingsWindowRoot`). The list and its rules are `SupportersPage`
//  (Model/Supporters.swift): a name and a note are drawn as they were written, never looked up in the
//  catalogue, and a note wraps in full however long it is (the page's scroll view holds a long list).
//  With nobody listed the page is the thanks alone, with nothing drawn to say the list is empty.

import SwiftUI

struct MacSettingsSupporters: View {
    var page: SupportersPage = .shipped

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(MacSettingsMetric.gap)) {
            if !page.entries.isEmpty {
                MacSettingsGroup(title: nil) {
                    ForEach(page.entries) { entry in
                        row(entry, last: entry.id == page.entries.last?.id)
                    }
                }
            }
        }
    }

    private func row(_ entry: SupportersPage.Entry, last: Bool) -> some View {
        MacSettingsRow(label: entry.name, caption: entry.note, last: last)
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
    }
}
