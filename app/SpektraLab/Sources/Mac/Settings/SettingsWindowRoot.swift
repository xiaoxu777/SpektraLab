// Settings is a cover over the existing window. Ordinary choices stay on the first seven pages;
// maintenance lives under one disclosure. Page requests open that disclosure without persisting it.
import SwiftUI

enum MacSettingsSection: String, CaseIterable, Hashable {
    case general, appearance, develop, export, watermarks, shortcuts, about
    case engine, sources, storage, diagnostics, agents, supporters

    var title: String {
        switch self {
        case .general: L("General")
        case .appearance: L("Appearance")
        case .develop: L("Develop")
        case .export: L("Export")
        case .watermarks: L("Watermarks")
        case .shortcuts: L("Shortcuts")
        case .about: L("About")
        case .engine: L("Develop engine")
        case .sources: L("Sources")
        case .storage: L("Storage")
        case .diagnostics: L("Diagnostics")
        case .agents: L("Agents")
        case .supporters: L("Supporters")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .develop: "camera.filters"
        case .export: "square.and.arrow.up"
        case .watermarks: "signature"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        case .engine: "slider.horizontal.3"
        case .sources: "books.vertical"
        case .storage: "internaldrive"
        case .diagnostics: "stethoscope"
        case .agents: "terminal"
        case .supporters: "heart"
        }
    }

    var advanced: Bool {
        switch self {
        case .engine, .sources, .storage, .diagnostics, .agents, .supporters: true
        default: false
        }
    }
    var available: Bool { self != .agents || ProMode.shared.on }
    static var visible: [Self] { allCases.filter(\.available) }

    init(_ page: SettingsPage?) {
        switch page {
        case .sources?: self = .sources
        case .storage?, .workingLimit?, .previewLimit?: self = .storage
        case .newFrames?: self = .develop
        case .previewSize?: self = .engine
        case .recipe?, .recipeEdit?: self = .export
        case .watermarks?: self = .watermarks
        case .diagnostics?: self = .diagnostics
        case .appearance?: self = .appearance
        case .credits?: self = .about
        case .shortcuts?: self = .shortcuts
        case .agents?: self = .agents
        case .language?, nil: self = .general
        }
    }
}

struct SettingsWindowRoot: View {
    @Environment(AppRouter.self) private var router
    @State private var section: MacSettingsSection
    @State private var advanced: Bool

    init() {
        let request = MacSettingsSection(SettingsRequest.take())
        let asked: MacSettingsSection = Self.supportersAsked ? .supporters : request
        Self.supportersAsked = false
        let shown: MacSettingsSection = asked.available ? asked : .general
        _section = State(initialValue: shown)
        _advanced = State(initialValue: shown.advanced)
    }

    #if DEBUG
    static let drive = Notification.Name("com.spektralab.mac.settings.drive")
    #endif
    /// Kept for the existing debug driver and the Release screenshot argument. Consumed once.
    static var supportersAsked = false

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            MacSettingsHairline()
            HStack(spacing: 0) {
                sidebar.frame(width: MacMetric.pt(MacSettingsMetric.sidebar))
                Rectangle().fill(Theme.wall).frame(width: 1)
                content
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .appColorScheme()
        .macPageActions(confirm: { router.dismissCover() }, cancel: { router.dismissCover() })
        .onAppear { attachCheck() }
        .onChange(of: section) { _, _ in attachCheck() }
        .onChange(of: ProMode.shared.on) { _, _ in
            if !section.available { choose(.general) }
        }
        .onDisappear {
            #if DEBUG
            MacSettingsCheck.detach()
            #endif
        }
        .macSettingsDriven { asked, supporters in choose(supporters ? .supporters : asked) }
    }

    private func choose(_ asked: MacSettingsSection) {
        section = asked.available ? asked : .general
        if section.advanced { advanced = true }
    }

    private func attachCheck() {
        #if DEBUG
        MacSettingsCheck.attach(section: section) { choose($0) }
        #endif
    }

    private var titleBar: some View {
        HStack {
            Text(L("Settings")).font(MacMetric.font(16, .semibold))
                .accessibilityAddTraits(.isHeader).macSettingsItem("Settings")
            Spacer()
            Button(L("Done")) { router.dismissCover() }
                .buttonStyle(MacSettingsButtonStyle(kind: .primary))
                .accessibilityIdentifier("mac.settings.done").macSettingsItem("Done")
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, MacMetric.pt(20))
        .frame(height: MacMetric.pt(54))
        .background(Theme.chrome)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacMetric.pt(2)) {
                ForEach(MacSettingsSection.visible.filter { !$0.advanced }, id: \.self) { sidebarRow($0) }
                Rectangle().fill(Theme.wall).frame(height: 1).padding(.vertical, MacMetric.pt(6))
                Button {
                    advanced.toggle()
                    if !advanced && section.advanced { choose(.general) }
                } label: {
                    HStack(spacing: MacMetric.pt(10)) {
                        Image(systemName: "slider.horizontal.3").frame(width: MacMetric.pt(18))
                        Text(L("Advanced", as: "settings"))
                        Spacer(minLength: 0)
                        Image(systemName: advanced ? "chevron.down" : "chevron.right").font(MacMetric.font(10, .semibold))
                    }
                    .font(MacMetric.font(14, .medium)).foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, MacMetric.pt(12)).frame(minHeight: MacMetric.pt(36))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(advanced ? L("On") : L("Off"))
                .accessibilityIdentifier("mac.settings.advanced")
                if advanced {
                    ForEach(MacSettingsSection.visible.filter(\.advanced), id: \.self) { sidebarRow($0) }
                }
            }
            .padding(.horizontal, MacMetric.pt(10))
            .padding(.vertical, MacMetric.pt(8))
        }
        .scrollIndicators(.automatic)
        .background(Theme.chrome.opacity(0.45))
    }

    private func sidebarRow(_ s: MacSettingsSection) -> some View {
        Button { choose(s) } label: {
            HStack(spacing: MacMetric.pt(10)) {
                if !s.advanced {
                    Image(systemName: s.symbol).frame(width: MacMetric.pt(18))
                        .foregroundStyle(s == section ? Theme.accent : Theme.dim)
                }
                Text(s.title).foregroundStyle(s == section ? Theme.text : Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(MacMetric.font(s.advanced ? 13 : 14, s == section ? .semibold : .regular))
            .padding(.leading, MacMetric.pt(s.advanced ? 40 : 12))
            .padding(.trailing, MacMetric.pt(12))
            .frame(minHeight: MacMetric.pt(s.advanced ? 30 : 36))
            .background(s == section ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: MacMetric.pt(8)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(s == section ? .isSelected : [])
        .accessibilityIdentifier("mac.settings.section.\(s.rawValue)")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacMetric.pt(MacSettingsMetric.gap)) {
                Text(section.title).font(MacMetric.font(24, .semibold)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                switch section {
                case .general: MacSettingsGeneral()
                case .appearance: AppearanceSettings(style: .mac)
                case .develop: MacSettingsDevelop()
                case .export: MacSettingsRecipes()
                case .watermarks: MacSettingsWatermarks()
                case .shortcuts: FilmLabSettingsShortcuts()
                case .about: FilmLabSettingsAbout()
                case .engine: MacSettingsDevelop(engineOnly: true)
                case .sources: MacSettingsSources(close: { router.dismissCover() })
                case .storage: MacSettingsStorage()
                case .diagnostics: MacSettingsDiagnostics()
                case .agents: FilmLabSettingsAgents()
                case .supporters: MacSettingsSupporters()
                }
            }
            .frame(maxWidth: MacMetric.pt(MacSettingsMetric.readable), alignment: .leading)
            .padding(.horizontal, MacMetric.pt(28))
            .padding(.vertical, MacMetric.pt(28))
            .frame(maxWidth: .infinity, alignment: .top)
            .id(section)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Screenshot routing only: no preference or fixture is written, in Debug or Release.
@MainActor
enum FilmLabSettingsCheck {
    static func openIfAsked(router: AppRouter, arguments: [String] = CommandLine.arguments) {
        guard let i = arguments.firstIndex(of: "--filmlab-settings"), i + 1 < arguments.count else { return }
        let page: SettingsPage
        switch arguments[i + 1] {
        case "general": page = .language
        case "appearance": page = .appearance
        case "develop": page = .newFrames
        case "export": page = .recipe
        case "watermarks": page = .watermarks
        case "sources": page = .sources
        case "storage": page = .storage
        case "diagnostics": page = .diagnostics
        case "supporters", "about": page = .credits
        case "shortcuts": page = .shortcuts
        case "engine": page = .previewSize
        case "agents": page = .agents
        default: return
        }
        SettingsRequest.next = page
        SettingsWindowRoot.supportersAsked = arguments[i + 1] == "supporters"
        router.show(.settings)
    }
}

extension View {
    /// The window Settings items this view stands for (`MacSettingsCoverage`): a debug build notes them as
    /// they appear, for `--settings-check` to find each one on its section.
    func macSettingsItem(_ keys: String...) -> some View { macSettingsItem(keys) }

    func macSettingsItem(_ keys: [String]) -> some View {
        #if DEBUG
        onAppear { MacSettingsCheck.saw(keys) }
        #else
        self
        #endif
    }

    /// A debug build's: `MacDriver` moving the page that is up to a section, or to Supporters.
    func macSettingsDriven(_ perform: @escaping (MacSettingsSection, Bool) -> Void) -> some View {
        #if DEBUG
        onReceive(NotificationCenter.default.publisher(for: SettingsWindowRoot.drive)) { note in
            guard let raw = note.userInfo?["section"] as? String, let section = MacSettingsSection(rawValue: raw) else { return }
            SettingsRequest.next = nil
            SettingsWindowRoot.supportersAsked = false
            perform(section, note.userInfo?["supporters"] as? Bool ?? false)
        }
        #else
        self
        #endif
    }
}
