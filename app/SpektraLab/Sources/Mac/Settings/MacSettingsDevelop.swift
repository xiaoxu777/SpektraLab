// New-photo defaults and the advanced engine page share the stock rules and existing setters.
import SwiftUI

struct MacSettingsDevelop: View {
    var engineOnly = false
    @Environment(AppServices.self) private var model
    @Environment(AppSettings.self) private var settings
    /// Whether a screen of this Mac shows HDR: the Enable HDR row's gate (D5).
    private var hdr: HDRDisplays { .shared }

    /// *Last used*, or a film's id.
    private static let lastUsed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(MacSettingsMetric.gap)) {
            if engineOnly {
                engineControls
                lensProfiles
                filmEdge
            } else {
                newFrames
                defaults
            }
        }
        .onAppear { if engineOnly { LensLibrary.shared.warm() } }
    }

    // MARK: new frames

    private var chosenFilm: String { settings.newFrameStocks.film }
    private var chosenPaper: String { settings.newFrameStocks.paper }

    private var newFrames: some View {
        let catalog = StockCatalog.shared
        let slide = catalog.isSlide(chosenFilm)
        let films: [(String, String)] = [(Self.lastUsed, L("Last used") + " · " + catalog.pairText(film: settings.lastFilm, paper: settings.lastPaper))]
            + catalog.films.map { ($0.id, $0.shortName + " · " + detail($0)) }
        let papers: [(String, String)] = catalog.papers.map { ($0.id, $0.shortName + " · " + L(shown: $0.kind)) }
        let note: String? = slide ? L("Slides do not use paper.")
            : catalog.stock(chosenFilm)?.isMonochrome == true ? L("Black-and-white film needs black-and-white paper.") : nil
        return MacSettingsGroup(title: L("New frames")) {
            MacSettingsRow(label: L("Film")) {
                MacSettingsPopUp(label: L("Film"), options: films,
                                 selection: Binding(get: { settings.newFrameFilm == nil ? Self.lastUsed : chosenFilm },
                                                    set: { chooseFilm($0) }),
                                 face: settings.newFrameFilm == nil ? L("Last used") : catalog.stock(chosenFilm)?.shortName)
            }
            .macSettingsItem("New frames", "Last used", "Film")
            MacSettingsRow(label: L("Paper"), caption: note, last: true) {
                MacSettingsPopUp(label: L("Paper"), options: papers,
                                 selection: Binding(get: { chosenPaper }, set: { choosePaper($0) }),
                                 allowed: { id in slide || catalog.whyNotPrinted(film: chosenFilm, on: id) == nil },
                                 face: catalog.stock(chosenPaper)?.shortName)
                    .disabled(slide)
            }
            .macSettingsItem("Paper")
        }
    }

    /// "colour negative · ISO 400".
    private func detail(_ stock: Stock) -> String {
        [L(shown: stock.kind), stock.isoText].compactMap { $0 }.joined(separator: " · ")
    }

    /// The window picker's choices (`StockPairPicker.chooseFilm`, `choosePaper`, `take`): *Last used* clears
    /// both; a film or a paper fixes the pair through `StockPair`, which refuses what a frame cannot have.
    private func chooseFilm(_ id: String) {
        guard id != Self.lastUsed else {
            settings.newFrameFilm = nil
            settings.newFramePaper = nil
            return
        }
        var pair = StockPair(film: chosenFilm, paper: chosenPaper)
        pair.load(film: id)
        settings.newFramePaper = pair.paper
        settings.newFrameFilm = pair.film
    }

    private func choosePaper(_ id: String) {
        var pair = StockPair(film: chosenFilm, paper: chosenPaper)
        guard pair.print(on: id) else { return }
        settings.newFramePaper = pair.paper
        settings.newFrameFilm = pair.film
    }

    // MARK: develop

    private var defaults: some View {
        MacSettingsGroup(title: nil) {
            MacSettingsRow(label: L("Default EDR"), last: !hdr.showsHDR) {
                MacSettingsCheckbox(label: L("Default EDR"), on: Binding(get: { settings.edrByDefault }, set: { settings.edrByDefault = $0 }))
            }
            .macSettingsItem("Enable EDR by Default")
            if hdr.showsHDR {
                MacSettingsRow(label: L("Default HDR"), last: true) {
                    MacSettingsCheckbox(label: L("Default HDR"), on: Binding(get: { settings.hdrByDefault }, set: { settings.hdrByDefault = $0 }))
                }
                .macSettingsItem("Enable HDR by Default")
            }
        }
    }

    private var engineControls: some View {
        MacSettingsGroup(title: nil) {
            MacSettingsRow(label: L("Preview size")) {
                MacSettingsPopUp(label: L("Preview size"), options: Self.previewEdges.map { ($0, Fmt.thousands($0) + " px") },
                                 selection: Binding(get: { settings.previewLongEdge }, set: { settings.previewLongEdge = $0 }),
                                 other: Fmt.thousands(settings.previewLongEdge) + " px")
            }
            .macSettingsItem("Preview size")
            MacSettingsRow(label: L("RAW decoder"), caption: LibRawDecode.isAvailable ? nil : L("LibRaw is not included in this build.")) {
                MacSettingsPopUp(label: L("RAW decoder"),
                                 options: [(RawDecoderChoice.system, L("Apple (macOS)")),
                                           (RawDecoderChoice.libraw, "LibRaw")],
                                 selection: Binding(get: { settings.rawDecoder }, set: { settings.rawDecoder = $0; model.rawDecoderChanged() }),
                                 allowed: { $0 == .system || LibRawDecode.isAvailable })
            }
            .macSettingsItem("RAW decoder")
            MacSettingsRow(label: L("Crop re-maps the frame"), last: true) {
                MacSettingsCheckbox(label: L("Crop re-maps the frame"), on: Binding(get: { settings.cropRemapsFrame },
                    set: { settings.cropRemapsFrame = $0; model.cropRemapsFrameChanged() }))
            }
            .macSettingsItem("Crop re-maps the frame")
        }
    }

    /// The window's six (`SettingsScreen`'s *Preview size*), the device policy's (`DevicePolicy.previewEdges`).
    static var previewEdges: [Int] { DevicePolicy.previewEdges }

    // MARK: lens profiles

    @State private var removing: LensDatabase.Source?

    private var lenses: LensLibrary { .shared }

    private var lensProfiles: some View {
        MacSettingsGroup(title: L("Lens Profiles")) {
            MacSettingsRow(label: L("Installed from Adobe"), detail: lensCount(.adobeInstalled)) {
                Button(L("Remove")) { removing = .adobeInstalled }
                    .buttonStyle(MacSettingsButtonStyle(kind: .destructive))
                    .disabled(lenses.lenses(of: .adobeInstalled) == 0 || lenses.isInstalling)
                    .accessibilityLabel(L("Remove the lenses installed from Adobe"))
            }
            .macSettingsItem("Lens Profiles", "Installed from Adobe", "Remove")
            MacSettingsRow(label: L("Added by hand"), detail: lensCount(.user)) {
                HStack(spacing: MacMetric.pt(8)) {
                    Button(L("Add .lcp…")) {
                        Task { @MainActor in
                            guard let file = await MacOpenPanel.chooseLensProfile() else { return }
                            await lenses.add(file: file)
                        }
                    }
                    .buttonStyle(MacSettingsButtonStyle())
                    .disabled(lenses.isInstalling || lenses.database == nil)
                    Button(L("Remove")) { removing = .user }
                        .buttonStyle(MacSettingsButtonStyle(kind: .destructive))
                        .disabled(lenses.lenses(of: .user) == 0 || lenses.isInstalling)
                        .accessibilityLabel(L("Remove the lenses added by hand"))
                }
            }
            .macSettingsItem("Added by hand", "Add .lcp…")
            adobeRow
        }
        .confirmationDialog(removing == .user ? L("Remove the lenses added by hand?") : L("Remove the lenses installed from Adobe?"),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(L("Remove"), role: .destructive) {
                guard let source = removing else { return }
                Task { @MainActor in await lenses.remove(source) }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("A photograph corrected with one of them is no longer corrected until its lens is added again."))
        }
    }

    /// "1,234 lenses", or what is happening to them.
    private func lensCount(_ source: LensDatabase.Source) -> String {
        guard lenses.read else { return L("Reading the lens library") }
        let n = lenses.lenses(of: source)
        return n == 1 ? L("1 lens") : L("\(Fmt.thousands(n)) lenses")
    }

    /// Adobe's profiles on this Mac, and Install to SpektraLab with its progress and its outcome.
    private var adobeRow: some View {
        let found = lenses.adobeFiles ?? 0
        let label = lenses.adobeFiles == nil ? L("Looking for Adobe's lens profiles on this Mac")
            : found == 0 ? L("No Adobe lens profiles were found on this Mac")
            : L("Found \(Fmt.thousands(found)) Adobe lens profiles on this Mac")
        return MacSettingsRow(label: L("Adobe lens profiles"), detail: label, caption: adobeCaption, last: true) {
            if lenses.isInstalling {
                Button(L("Cancel")) { lenses.cancelInstall() }
                    .buttonStyle(MacSettingsButtonStyle())
                    .accessibilityLabel(L("Cancel the install"))
            } else {
                Button(L("Install to SpektraLab")) { lenses.install() }
                    .buttonStyle(MacSettingsButtonStyle(kind: .primary))
                    .disabled(found == 0 || lenses.database == nil)
            }
        }
        .macSettingsItem("Found %@ Adobe lens profiles on this Mac", "Install to SpektraLab")
    }

    /// Under the Adobe row: the install's progress, or what the last write did, or where Adobe keeps them.
    private var adobeCaption: String? {
        if let p = lenses.progress {
            return p.total == 0 ? L("Starting the install")
                : L("Installing: \(Fmt.thousands(p.done)) of \(Fmt.thousands(p.total)) files read, \(Fmt.thousands(p.skipped)) skipped. You can keep working.")
        }
        switch lenses.lastResult {
        case .installed(let added, let replaced, let unchanged, let skipped, let cancelled)?:
            let done = L("Installed \(Fmt.thousands(added + replaced)) files, \(Fmt.thousands(unchanged)) already in the library, \(Fmt.thousands(skipped)) skipped.")
            let why = lenses.lastSkipped.prefix(3).map { $0.name }.joined(separator: ", ")
            return (cancelled ? L("Cancelled.") + " " : "") + done + (why.isEmpty ? "" : " " + L("Skipped: \(why).") )
        case .added(let name)?:
            return name.map { L("Added \($0).") } ?? L("Added.")
        case .addFailed(let reason)?:
            return L("Could not add the file: \(reason)")
        case .removed(let source)?:
            return source == .user ? L("The lenses added by hand were removed.") : L("The lenses installed from Adobe were removed.")
        case .failed(let reason)?:
            return L("The lens library could not be written: \(reason)")
        case nil: return nil
        }
    }

    // MARK: film edge

    private var filmEdge: some View {
        MacSettingsGroup(title: L("Film Edge")) {
            MacSettingsRow(label: L("Body"), last: true) {
                HStack(spacing: MacMetric.pt(8)) {
                    Text(L("No. \(settings.bodySeed)")).font(MacMetric.font(12, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                        .fixedSize()
                    Button(L("Another")) { settings.anotherBody() }
                        .buttonStyle(MacSettingsButtonStyle())
                        .accessibilityLabel(L("Another camera body"))
                }
            }
            .macSettingsItem("Body", "No. %@", "Another")
        }
    }
}
