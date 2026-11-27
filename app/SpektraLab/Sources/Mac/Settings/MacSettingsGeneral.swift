// Everyday preferences. The mode switch uses the bar's action, including its return from grading.
import SwiftUI

struct MacSettingsGeneral: View {
    private var imports: FilmLabImport { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(MacSettingsMetric.gap)) {
            MacSettingsGroup(title: nil) {
                MacSettingsRow(label: L("Edition"), caption: L("Pro adds grading and local edits.")) {
                    MacSettingsSegments(label: L("Edition"), options: [(false, L("Simple")), (true, L("Pro"))],
                                        selection: Binding(get: { ProMode.shared.on }, set: { FilmLabHome.shared.setPro($0) }))
                }
                .macSettingsItem("Edition")
                MacSettingsRow(label: L("Language"), last: true) {
                    MacSettingsPopUp(label: L("Language"), options: AppLanguage.allCases.map { ($0, $0.ownName) },
                                     selection: Binding(get: { Language.shared.current }, set: { Language.shared.choose($0) }))
                }
                .macSettingsItem("Language")
            }
            MacSettingsGroup(title: L("Photos", as: "settings")) {
                MacSettingsRow(label: L("Photo location"), detail: imports.folderShown) {
                    Button(L("Change…")) { Task { await imports.chooseFolder() } }
                        .buttonStyle(MacSettingsButtonStyle())
                }
                .macSettingsItem("Photo location")
                MacSettingsRow(label: L("On import"), last: true) {
                    MacSettingsSegments(label: L("On import"),
                                        options: [(FilmLabImport.Mode.copy, L("Copy to photo location")), (.inPlace, L("Leave in place"))],
                                        selection: Binding(get: { imports.mode }, set: { imports.mode = $0 }))
                }
                .macSettingsItem("On import")
            }
        }
    }
}
