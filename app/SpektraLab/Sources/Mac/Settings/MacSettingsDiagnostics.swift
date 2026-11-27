// Log controls and build facts. The complete privacy inventory stays behind a closed disclosure.
import SwiftUI

struct MacSettingsDiagnostics: View {
    @Environment(AppServices.self) private var model
    @Environment(Diagnostics.self) private var diagnostics
    @Environment(\.isSnapshot) private var isSnapshot
    /// The log's zip, made and waiting for Finder's panel.
    @State private var logZip: URL?
    @State private var saved: String?
    @State private var showingLogDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(MacSettingsMetric.gap)) {
            log
            MacSettingsGroup(title: nil) {
                DisclosureGroup(isExpanded: $showingLogDetails) { holds } label: {
                    Text(L("What the log holds")).font(MacMetric.font(14, .medium)).foregroundStyle(Theme.text)
                }
                .tint(Theme.accent).padding(MacMetric.pt(MacSettingsMetric.inset))
                .macSettingsItem("What the log holds")
            }
            thisBuild
        }
        .fileMover(isPresented: Binding(get: { logZip != nil }, set: { if !$0 { logZip = nil } }), file: logZip) { result in
            if case .success(let url) = result { saved = L("Saved to \(url.deletingLastPathComponent().lastPathComponent).") }
            logZip = nil
        }
    }

    // MARK: the log

    private var log: some View {
        MacSettingsGroup(title: L("Log")) {
            #if SPK_LOG_UPLOAD
            if diagnostics.canSend {
                MacSettingsRow(label: L("Share the log with SpektraLab")) {
                    MacSettingsCheckbox(label: L("Share the log with SpektraLab"),
                                        on: Binding(get: { diagnostics.consent == .shared }, set: { diagnostics.answer(share: $0) }))
                }
                .macSettingsItem("Share the log with SpektraLab")
            }
            #endif
            MacSettingsRow(label: L("Where"), detail: (ImportService.logs.path as NSString).abbreviatingWithTildeInPath,
                           caption: saved ?? note) {
                HStack(spacing: MacMetric.pt(6)) {
                    Button(L("Show in Finder")) { UIApplication.shared.open(ImportService.logs) }
                        .buttonStyle(MacSettingsButtonStyle())
                    Button(diagnostics.isPacking ? L("Making the Zip") : L("Export Log Zip")) { exportLog() }
                        .buttonStyle(MacSettingsButtonStyle())
                        .disabled(!diagnostics.keepsLog || diagnostics.isPacking)
                        .accessibilityIdentifier("mac.settings.log.zip")
                }
            }
            .macSettingsItem("Diagnostics", "Export Log Zip", "Making the Zip")
            MacSettingsRow(label: L("Privacy Policy"), last: true) {
                Button(L("Open")) { openPolicy() }
                    .buttonStyle(MacSettingsButtonStyle())
            }
            .macSettingsItem("Privacy Policy")
        }
    }

    /// The group's footer: what happens to the log, as things stand.
    private var note: String? {
        guard diagnostics.keepsLog else { return L("No log available.") }
        #if SPK_LOG_UPLOAD
        if diagnostics.canSend, diagnostics.consent == .shared {
            if let trouble = diagnostics.trouble {
                return L("SpektraLab's server could not be reached from here (\(Fmt.stamp(trouble.at))). Export Log Zip, and send it by hand.")
            }
            return diagnostics.lastSent.map { L(" Last sent \(Fmt.stamp($0)).") }
        }
        #endif
        return nil
    }

    private func exportLog() {
        guard !isSnapshot else { return }
        saved = nil
        Task { logZip = await diagnostics.makeZip() }
    }

    private func openPolicy() {
        guard !isSnapshot else { return }
        UIApplication.shared.open(Diagnostics.policyURL)
    }

    // MARK: what the log holds

    /// `DiagnosticsPage.holds`, each line said of this Mac.
    static var holdsLines: [String] {
        [
            L("This Mac: its model, its macOS, its language and region setting, its memory, Low Power Mode and heat, "
              + "and this build of SpektraLab with its settings."),
            L("Each develop and export: its size, how long it took, the memory it used and what the Mac had free, and whether it finished."),
            L("The app's memory as it runs: how much it held and how much the Mac had left, at each page, and whenever it rose or fell."),
            L("Your library in numbers: how many frames, from where, their sizes and the cameras they came from, and the storage they take."),
            L("What you used: the films and papers on your frames, which settings a visit to the develop page changed, "
              + "and the formats you exported."),
            L("What went wrong: errors, whether the app was ended while in use, and the system's own performance and crash reports for this app."),
            L("Every line carries the time it was written, with this Mac's offset from UTC."),
        ]
    }

    /// `DiagnosticsPage.whereItGoes`, said of this Mac.
    private var whereItGoes: [String] {
        #if SPK_LOG_UPLOAD
        if let host = diagnostics.serverHost, diagnostics.canSend {
            var lines: [String] = []
            lines.append(L("With sharing on, the log goes to \(host) over an encrypted connection, when the app is opened and when you "
                           + "leave it, under a random number made for this installation. The server notes the country a log arrived "
                           + "from, keeps no address, and deletes a log 90 days after it last arrived."))
            lines.append(L("Turning sharing on sends what this Mac has kept, up to 7 days of it. Turn it off and nothing more is "
                           + "sent; what was already sent is not deleted by that. Turning it on again starts a new number."))
            if diagnostics.installText != nil || diagnostics.numberBefore != nil {
                lines.append(L("To have what was sent deleted sooner, write to the address in the privacy policy (Settings) with the "
                               + "number below. It stays here after sharing is turned off."))
            }
            lines.append(L("The log stays on this Mac for 7 days whether or not it is shared. Export Log Zip, in Settings, hands you "
                           + "the same files to send yourself."))
            if let number = diagnostics.installText { lines.append(L("This installation's number: \(number)")) }
            if let before = diagnostics.numberBefore, before != diagnostics.installText {
                lines.append(diagnostics.installText == nil ? L("Sharing is off. What was sent went under the number: \(before)")
                                                            : L("The number before it: \(before)"))
            }
            return lines
        }
        #endif
        return [L("The log stays on this Mac for 7 days and leaves it only when you export it: Export Log Zip hands you the files to send yourself.")]
    }

    private var holds: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(12)) {
            paragraphs(Self.holdsLines)
                .overlay(alignment: .bottom) { MacSettingsHairline() }
                .macSettingsItem("What the log holds")
            heading(L("Never in it"))
            paragraphs([DiagnosticsPage.never])
                .overlay(alignment: .bottom) { MacSettingsHairline() }
                .macSettingsItem("Never in it")
            heading(L("Where it goes"))
            paragraphs(whereItGoes)
                .macSettingsItem("Where it goes")
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(MacMetric.font(12, .semibold)).foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MacMetric.pt(MacSettingsMetric.inset))
            .padding(.top, MacMetric.pt(9))
    }

    private func paragraphs(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(5)) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: MacMetric.pt(6)) {
                    Text("•").font(MacMetric.font(11)).foregroundStyle(Theme.dim)
                    MacSettingsCaption(line, color: Theme.secondaryText)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, MacMetric.pt(MacSettingsMetric.inset))
        .padding(.vertical, MacMetric.pt(9))
    }

    // MARK: this build

    private var thisBuild: some View {
        MacSettingsGroup(title: L("This build")) {
            MacSettingsValueRow(label: L("Version"), value: buildLine)
            MacSettingsValueRow(label: L("Engine"), value: model.engineText)
                .macSettingsItem("This build", "Engine")
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                MacSettingsValueRow(label: L("Memory budget"), value: budgetText, last: true)
            }
            .macSettingsItem("Memory budget")
        }
    }

    /// "2.0 (1) · Debug · unpublished-revision" (`DiagnosticsPage.buildLine`).
    private var buildLine: String {
        let b = diagnostics.build
        return Brand.name + " \(b.text)" + Fmt.dot + L(shown: b.configuration) + (b.commit.isEmpty ? "" : Fmt.dot + b.commit)
    }

    /// "1,445 MB · Mac headroom": the budget a job would be given now (`RenderQueue.budgetNow`), and
    /// which side holds it down.
    private var budgetText: String {
        let now = model.scheduler.budgetNow().budget
        return Fmt.thousands(Int(now.bytes.megabytes.rounded())) + " MB" + Fmt.dot
            + (now.binding == .allowance ? L("app allowance") : L("Mac headroom"))
    }
}
