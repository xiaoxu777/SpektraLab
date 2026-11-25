//  FilmLabHome.swift — FilmLab's home page, its 普通版 / 专业版 switch, and the bar's way back to it.
//
//  The owner, 2026-11-22: "交付也好，冲洗也好，目前很多功能都很专业 … 我希望可以有一个按钮来切换专业版和普通版。然后要有一个
//  类似项目的主界面". So:
//
//  - **The home page** (`FilmLabHomeView`) is over the window when FilmLab opens: every folder, catalog or session
//    the library has opened is a project card — its first picture, its name, how many pictures, when it was last
//    opened — and a card opens that project in 图库. A large Open Folder… makes a new one. The bar's house
//    (`FilmLabHomeButton`) brings it back from any mode.
//  - **普通版 / 专业版** (`ProModeSwitch`): one switch, in the bar and on the home page. 普通版 keeps each mode to its
//    everyday controls (图库 · 冲洗 · 导出; in 冲洗 the film, the paper, Exposure, White Balance and a Film Edge
//    switch; in 导出 Format, Quality, Size and Save to). 专业版 is everything SpektraLab has. What an edit holds is
//    never changed by the switch: it only decides what is shown.
//
//  The welcome tour that runs the first time is FilmLabWelcome.swift.

import ImageIO
import SwiftUI
import UIKit

/// What is over the window: the home page, the welcome tour.
@MainActor
@Observable
final class FilmLabHome {
    static let shared = FilmLabHome()

    private init() { FilmLabCheckArgs.applyMode() }
    static let welcomedKey = "filmlab.welcomed"

    /// The home page is over the window. On at every launch.
    /// On at every launch; `--no-home` leaves it off, for a check that captures the window itself (`--capture-window`).
    var shown = !CommandLine.arguments.contains("--no-home")
    /// The welcome tour is over the window: the first launch, or asked for again (Help, the home page), or a check's
    /// launch (`--filmlab-welcome PAGE`, `WelcomeCheck`).
    var welcome = WelcomeCheck.on || !UserDefaults.standard.bool(forKey: FilmLabHome.welcomedKey)

    func finishWelcome() {
        // A check's tour leaves the settings as it found them.
        if !WelcomeCheck.on { UserDefaults.standard.set(true, forKey: Self.welcomedKey) }
        withAnimation(.easeInOut(duration: 0.45)) { welcome = false }
    }

    func showHome() { withAnimation(.easeInOut(duration: 0.3)) { shown = true } }
    /// The home page goes, and 新建项目's sheet with it: a project opened leaves nothing of the page behind.
    func hideHome() {
        if FilmLabNewProject.shared.shown { FilmLabNewProject.shared.close() }
        withAnimation(.easeInOut(duration: 0.3)) { shown = false }
    }

    /// 普通版 or 专业版. Turning 专业版 off while 编辑 is in front goes to 冲洗 (编辑 is 专业版's).
    func setPro(_ on: Bool) {
        guard on != ProMode.shared.on else { return }
        withAnimation(.smooth(duration: 0.25)) { ProMode.shared.on = on }
        if !on, let dev = MacShellBar.shared.develop, dev.surface == .edit { dev.chooseSurface(.develop) }
    }
}

// MARK: - the switch

/// 普通 | 专业, a capsule with a sliding thumb. `large` is the home page's and the welcome's.
struct ProModeSwitch: View {
    var large = false
    @Namespace private var thumb

    var body: some View {
        let pro = ProMode.shared.on
        HStack(spacing: 0) {
            segment(L("Simple"), symbol: "sparkles", selected: !pro) { FilmLabHome.shared.setPro(false) }
            segment(L("Pro"), symbol: "slider.horizontal.3", selected: pro) { FilmLabHome.shared.setPro(true) }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: MacMetric.pt(large ? 9 : 8), style: .continuous).fill(Theme.card))
        .fixedSize()
        .help(L("Simple shows the everyday controls; Pro shows every tool."))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Simple or Pro"))
        .accessibilityIdentifier("filmlab.promode")
    }

    private func segment(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: MacMetric.pt(large ? 6 : 4)) {
                if large { Image(systemName: symbol).font(MacMetric.font(12, .semibold)) }
                Text(title).font(MacMetric.font(large ? 13 : 11.5, .semibold)).fixedSize()
            }
            .foregroundStyle(selected ? Theme.onSelection : Theme.secondaryText)
            .padding(.horizontal, MacMetric.pt(large ? 16 : 10))
            .frame(height: MacMetric.pt(large ? 30 : 20))
            .background {
                if selected {   // design A: selection is white, a rounded tab in a rounded tray
                    RoundedRectangle(cornerRadius: MacMetric.pt(large ? 7 : 6), style: .continuous).fill(Theme.selection)
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The bar's house: the home page, from any mode.
struct FilmLabHomeButton: View {
    var body: some View {
        Button { FilmLabHome.shared.showHome() } label: {
            Image(systemName: "house").font(MacMetric.font(14)).foregroundStyle(Theme.secondaryText)
                .frame(width: MacMetric.pt(26), height: MacMetric.pt(22)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Home"))
        .accessibilityLabel(L("Home"))
        .accessibilityIdentifier("filmlab.bar.home")
    }
}

// MARK: - the home page

struct FilmLabHomeView: View {
    @Environment(AppServices.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var refused: String?
    @State private var appeared = false

    private var home: FilmLabHome { .shared }

    var body: some View {
        let store = MacLibraryUI.store(model)
        let projects = store.sources.filter { $0.kind != .appLibrary }
            .sorted { ($0.openedAt ?? $0.addedAt) > ($1.openedAt ?? $1.addedAt) }
        ZStack {
            // Design A: the plain graphite ground, no moving glow (2026-11-24).
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header(store, hasProjects: !projects.isEmpty)
                    .padding(.horizontal, MacMetric.pt(40))
                    .padding(.top, MacMetric.pt(26))
                if projects.isEmpty {
                    emptyState(store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: MacMetric.pt(24)) {
                            // 继续冲洗 (the last project) beside 新建项目 / 导入.
                            HStack(alignment: .top, spacing: MacMetric.pt(16)) {
                                if let last = projects.first {
                                    HomeContinueCard(source: last, open: { open(last, store) })
                                        .layoutPriority(1)
                                }
                                newRollCard(store)
                                    .frame(minWidth: MacMetric.pt(260), maxWidth: MacMetric.pt(380))
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(appeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.35), value: appeared)
                            HStack(alignment: .firstTextBaseline, spacing: MacMetric.pt(8)) {
                                Text(L("All projects")).font(MacMetric.font(15, .bold)).foregroundStyle(Theme.text)
                                Text("\(projects.count)").font(MacMetric.font(12)).monospacedDigit().foregroundStyle(Theme.dim)
                                Spacer(minLength: 0)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: MacMetric.pt(200), maximum: MacMetric.pt(300)),
                                                         spacing: MacMetric.pt(16))],
                                      alignment: .leading, spacing: MacMetric.pt(20)) {
                                ForEach(Array(projects.enumerated()), id: \.element.id) { i, source in
                                    ProjectCard(source: source, selected: source.id == store.selectedSourceID,
                                                dropping: FilmLabDrop.shared.hover == source.id,
                                                open: { open(source, store) },
                                                remove: { store.remove(source: source.id) })
                                        // Its frame, in the window's points: a drag over it is told by where it is (`FilmLabDrop`).
                                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { FilmLabDrop.shared.cards[source.id] = $0 }
                                        .onDisappear { FilmLabDrop.shared.cards[source.id] = nil }
                                        .opacity(appeared ? 1 : 0)
                                        .offset(y: appeared ? 0 : 14)
                                        .animation(.spring(duration: 0.5, bounce: 0.2).delay(0.03 * Double(min(i, 12))),
                                                   value: appeared)
                                }
                            }
                        }
                        .padding(.horizontal, MacMetric.pt(40))
                        .padding(.vertical, MacMetric.pt(22))
                    }
                    .scrollIndicators(.automatic)
                }
                footer(store)
                    .padding(.horizontal, MacMetric.pt(40))
                    .padding(.bottom, MacMetric.pt(22))
            }
            // Under 新建项目's sheet the page is neither pressed nor read: a press meant for the sheet (its ×, by
            // VoiceOver or Accessibility Keyboard) never lands on a card under it.
            .accessibilityHidden(FilmLabNewProject.shared.shown)
            .allowsHitTesting(!FilmLabNewProject.shared.shown)
        }
        // 新建项目's sheet, over the page (not Finder's panel first: the photos are dropped onto it).
        .overlay {
            if FilmLabNewProject.shared.shown {
                FilmLabNewProjectSheet(store: store, router: router)
            }
        }
        .onAppear {
            appeared = true
            // A check's launch, for `--capture-window`: the sheet with a folder in it, or the first card lit as a drag lights it.
            if let path = FilmLabCheckArgs.value("--filmlab-newproject") {
                FilmLabNewProject.shared.open(with: [URL(fileURLWithPath: path, isDirectory: true)])
            }
            if FilmLabCheckArgs.value("--filmlab-drop-hover") != nil {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    FilmLabDrop.shared.hover = store.sources.filter { $0.kind != .appLibrary }
                        .sorted { ($0.openedAt ?? $0.addedAt) > ($1.openedAt ?? $1.addedAt) }.dropFirst().first?.id
                }
            }
        }
        .accessibilityIdentifier("filmlab.home")
    }

    private func header(_ store: any MacLibraryData, hasProjects: Bool) -> some View {
        HStack(alignment: .center, spacing: MacMetric.pt(12)) {
            NegativeMark(size: MacMetric.pt(30))
            VStack(alignment: .leading, spacing: MacMetric.pt(1)) {
                Text(Brand.name).font(MacMetric.font(19, .bold)).foregroundStyle(Theme.text)
                Text(hasProjects ? L("Welcome back.")
                                 : L("Hasselblad files in, film out."))
                    .font(MacMetric.font(12)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: MacMetric.pt(16))
            if store.selectedSource != nil {
                Button { home.hideHome() } label: {
                    HStack(spacing: MacMetric.pt(6)) {
                        Text(L("Back to Library")).font(MacMetric.font(12.5, .medium))
                        Text("esc").font(MacMetric.font(10.5)).foregroundStyle(Theme.dim)
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, MacMetric.pt(12)).frame(height: MacMetric.pt(30))
                    .background(RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous).fill(Theme.card))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("filmlab.home.back")
            }
        }
    }

    /// 新建项目 / 导入: a dashed card beside 继续冲洗 — what goes where, and the two ways in (design A).
    private func newRollCard(_ store: any MacLibraryData) -> some View {
        VStack(spacing: MacMetric.pt(10)) {
            Image(systemName: "sdcard").font(.system(size: MacMetric.pt(28), weight: .light)).foregroundStyle(Theme.accent)
            Text(L("Start a new roll")).font(MacMetric.font(15, .semibold)).foregroundStyle(Theme.text)
            Text(L("Drop a card or folder here. 3FR, DNG, JPEG."))
                .font(MacMetric.font(12)).foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MacMetric.pt(8)) {
                    FilmLabNewProjectButton()
                    openButton(store)
                }
                VStack(spacing: MacMetric.pt(6)) {
                    FilmLabNewProjectButton()
                    openButton(store)
                }
            }
            storageLine
        }
        .padding(MacMetric.pt(18))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Theme.field, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { FilmLabNewProject.shared.open() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmlab.home.newcard")
    }

    /// 修改本地图片目录: one control, Finder's panel for the photo folder imports are copied into (the owner, 2026-11-25:
    /// "内容直接改为修改本地图片目录", for a sentence and a separate Change…). The folder is its tooltip, and its small grey
    /// text where that fits on the line; copy or leave them where they are is its right-click menu.
    private var storageLine: some View {
        let imports = FilmLabImport.shared
        let label = HStack(spacing: MacMetric.pt(5)) {
            Image(systemName: "folder").font(MacMetric.font(11.5, .semibold))
            Text(L("Change Local Photo Folder")).font(MacMetric.font(12, .semibold)).fixedSize()
        }
        .foregroundStyle(Theme.accent)
        return Button { Task { await imports.chooseFolder() } } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MacMetric.pt(8)) {
                    label
                    Text(imports.mode == .copy ? imports.folderShown : L("Imports stay where they are"))
                        .font(MacMetric.font(11.5)).foregroundStyle(Theme.dim).lineLimit(1).fixedSize()
                }
                label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(imports.folder.path)
        .contextMenu {
            Picker(L("Where should imported photos go?"), selection: Binding(get: { imports.mode }, set: { imports.mode = $0 })) {
                Text(L("Copy to my photo folder (recommended)")).tag(FilmLabImport.Mode.copy)
                Text(L("Leave them where they are")).tag(FilmLabImport.Mode.inPlace)
            }
            .pickerStyle(.inline)
        }
        .accessibilityLabel(L("Change Local Photo Folder"))
        .accessibilityValue(imports.folderShown)
        .accessibilityIdentifier("filmlab.home.storage")
    }

    private func openButton(_ store: any MacLibraryData, large: Bool = false) -> some View {
        Button { openFolder(store) } label: {
            HStack(spacing: MacMetric.pt(8)) {
                Image(systemName: "square.and.arrow.down").font(MacMetric.font(large ? 14 : 12, .bold))
                Text(L("Import Photos…")).font(MacMetric.font(large ? 14 : 12.5, .semibold)).fixedSize()
            }
            .foregroundStyle(Theme.onSelection)
            .padding(.horizontal, MacMetric.pt(large ? 20 : 14))
            .frame(height: MacMetric.pt(large ? 38 : 30))
            .background(RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous).fill(Theme.accent))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityIdentifier("filmlab.home.open")
    }

    private func emptyState(_ store: any MacLibraryData) -> some View {
        VStack(spacing: MacMetric.pt(18)) {
            FilmStripLoop(height: MacMetric.pt(86))
                .frame(maxWidth: MacMetric.pt(520))
                .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
            Text(L("Your first roll")).font(MacMetric.font(20, .bold)).foregroundStyle(Theme.text)
            Text(L("Insert the card and import its photos. Each import is one roll."))
                .font(MacMetric.font(13)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center).frame(maxWidth: MacMetric.pt(440))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: MacMetric.pt(12)) {
                FilmLabNewProjectButton()
                openButton(store, large: true)
            }
            .padding(.top, MacMetric.pt(4))
            Text(L("Or drag them onto this page.")).font(MacMetric.font(12)).foregroundStyle(Theme.dim)
            storageLine
            if let refused {
                Text(L(shown: refused)).font(MacMetric.font(12)).foregroundStyle(Theme.danger)
            }
        }
        .padding(MacMetric.pt(30))
    }

    private func footer(_ store: any MacLibraryData) -> some View {
        HStack(spacing: MacMetric.pt(14)) {
            ProModeSwitch(large: true)
            Text(ProMode.shared.on ? L("Pro: adds curves, glow, local edits and more.")
                                   : L("Simple: film, brightness and warmth, grain, export."))
                .font(MacMetric.font(12)).foregroundStyle(Theme.dim)
                .lineLimit(2)
                .contentTransition(.opacity)
            Spacer(minLength: MacMetric.pt(12))
            if let refused, !store.sources.isEmpty {
                Text(L(shown: refused)).font(MacMetric.font(12)).foregroundStyle(Theme.danger).lineLimit(1)
            }
            Button { withAnimation(.easeInOut(duration: 0.4)) { home.welcome = true } } label: {
                Label(L("Show the Welcome Tour"), systemImage: "play.circle")
                    .font(MacMetric.font(12, .medium)).foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("filmlab.home.tour")
        }
        .padding(.top, MacMetric.pt(12))
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule.opacity(0.6)).frame(height: 0.5) }
    }

    private func open(_ source: MacSource, _ store: any MacLibraryData) {
        if MacShellPath.develop(router.path) != nil { router.toLibrary() }
        home.hideHome()
        guard source.id != store.selectedSourceID else { return }
        Task { await store.select(source: source.id) }
    }

    private func openFolder(_ store: any MacLibraryData) {
        refused = nil
        FilmLabImport.shared.importPhotos(store: store, router: router)
    }
}

/// A project: its cover, its name, how many pictures and when it was last opened.
private struct ProjectCard: View {
    let source: MacSource
    let selected: Bool
    /// Photos are being dragged over it: dropped, they go into this project.
    var dropping = false
    let open: () -> Void
    let remove: () -> Void
    @State private var info: ProjectCovers.Info?
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: MacMetric.pt(8)) {
                cover
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(dropping ? Theme.accent : selected ? Theme.selectionFrame : Theme.wall,
                                      lineWidth: dropping ? 3 : selected ? 1.5 : 1))
                    .overlay {
                        if dropping {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.18))
                                Label(L("Add to this project"), systemImage: "plus.circle.fill")
                                    .font(MacMetric.font(13, .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, MacMetric.pt(12)).frame(height: MacMetric.pt(30))
                                    .background(Capsule().fill(Color.black.opacity(0.65)))
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .shadow(color: .black.opacity(hovering || dropping ? 0.4 : 0.2), radius: hovering || dropping ? 14 : 6, y: hovering ? 6 : 2)
                    .scaleEffect(hovering || dropping ? 1.015 : 1)
                VStack(alignment: .leading, spacing: MacMetric.pt(2)) {
                    HStack(spacing: MacMetric.pt(6)) {
                        Text(source.name).font(MacMetric.font(13.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        if source.status == .offline {
                            Image(systemName: "externaldrive.badge.xmark").font(MacMetric.font(11)).foregroundStyle(Theme.dim)
                        }
                        Spacer(minLength: MacMetric.pt(6))
                        Text(whenText).font(MacMetric.font(11)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    Text(countText).font(MacMetric.font(11.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                .padding(.horizontal, MacMetric.pt(2))
            }
            .animation(.spring(duration: 0.3, bounce: 0.3), value: hovering)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: dropping)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .onHover { hovering = $0 }
        .contextMenu {
            Button(L("Open")) { open() }
            if let url = source.url { Button(L("Show in Finder")) { UIApplication.shared.open(url) } }
            Divider()
            Button(L("Remove from Home"), role: .destructive) { remove() }
        }
        // Looked at again when photos were added to it (its count or its last look changes).
        .task(id: "\(source.path ?? "")|\(source.imageCount ?? -1)|\(source.syncedAt?.timeIntervalSince1970 ?? 0)") {
            info = await ProjectCovers.shared.info(for: source)
        }
        .accessibilityLabel(source.name + ", " + subtitle)
        .accessibilityIdentifier("filmlab.home.project")
    }

    private var cover: some View {
        Rectangle().fill(Theme.card)
            .aspectRatio(3 / 2, contentMode: .fit)
            .overlay {
                if let image = info?.cover {
                    Image(uiImage: image).resizable().scaledToFill()
                        .transition(.opacity.animation(.easeOut(duration: 0.35)))
                } else if info != nil {
                    Image(systemName: icon).font(.system(size: MacMetric.pt(28), weight: .light)).foregroundStyle(Theme.dim)
                } else {
                    ProgressView().scaleEffect(0.6)
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                if source.kind != .folder {
                    Text(kindName).font(MacMetric.font(10, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, MacMetric.pt(7)).frame(height: MacMetric.pt(18))
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(MacMetric.pt(8))
                }
            }
    }

    private var icon: String {
        switch source.kind {
        case .folder: "folder"
        case .catalog, .appLibrary: "books.vertical"
        case .session: "camera"
        case .captureOneCatalog, .captureOneSession: "circle.circle"
        }
    }

    private var kindName: String {
        switch source.kind {
        case .folder: L("Folder")
        case .catalog, .appLibrary: L("Catalog")
        case .session: L("Session")
        case .captureOneCatalog, .captureOneSession: "Capture One"
        }
    }

    private var countText: String {
        if let n = source.imageCount ?? info?.count { return L("\(n) pictures") }
        return kindName
    }

    private var whenText: String { HomeWhen.text(source) }

    private var subtitle: String { countText + " · " + whenText }
}

/// When a project was last opened, said the home page's way: never "in 0 seconds", under a minute is "now".
@MainActor
enum HomeWhen {
    static func text(_ source: MacSource) -> String {
        let now = Date()
        let when = min(source.openedAt ?? source.addedAt, now)
        let f = RelativeDateTimeFormatter()
        f.locale = Language.shared.current.locale
        f.unitsStyle = .full
        f.dateTimeStyle = .named
        return now.timeIntervalSince(when) < 60 ? f.localizedString(fromTimeInterval: 0) : f.localizedString(for: when, relativeTo: now)
    }
}

/// 继续冲洗: the project last opened, large, with its cover and the way back in (design A).
private struct HomeContinueCard: View {
    let source: MacSource
    let open: () -> Void
    @State private var info: ProjectCovers.Info?

    var body: some View {
        HStack(alignment: .top, spacing: MacMetric.pt(18)) {
            Button(action: open) {
                Rectangle().fill(Theme.card)
                    .overlay {
                        if let image = info?.cover {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo.stack").font(.system(size: MacMetric.pt(26), weight: .light)).foregroundStyle(Theme.dim)
                        }
                    }
                    .frame(width: MacMetric.pt(250), height: MacMetric.pt(166))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            VStack(alignment: .leading, spacing: MacMetric.pt(6)) {
                Text(L("Continue developing")).font(MacMetric.font(11.5, .semibold)).tracking(0.6).foregroundStyle(Theme.accent)
                Text(source.name).font(MacMetric.font(24, .bold)).foregroundStyle(Theme.text).lineLimit(2)
                Text(line).font(MacMetric.font(12.5)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                Spacer(minLength: MacMetric.pt(10))
                HStack(spacing: MacMetric.pt(8)) {
                    Button(action: open) {
                        Text(L("Open")).font(MacMetric.font(12.5, .semibold)).foregroundStyle(Theme.onSelection)
                            .padding(.horizontal, MacMetric.pt(18)).frame(height: MacMetric.pt(30))
                            .background(RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous).fill(Theme.accent))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("filmlab.home.continue")
                    if let url = source.url {
                        Button { UIApplication.shared.open(url) } label: {
                            Text(L("Show in Finder")).font(MacMetric.font(12.5, .medium)).foregroundStyle(Theme.text)
                                .padding(.horizontal, MacMetric.pt(12)).frame(height: MacMetric.pt(30))
                                .background(RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous).fill(Theme.card))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, MacMetric.pt(4))
            Spacer(minLength: 0)
        }
        .padding(MacMetric.pt(16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
        .task(id: "\(source.path ?? "")|\(source.imageCount ?? -1)|\(source.syncedAt?.timeIntervalSince1970 ?? 0)") {
            info = await ProjectCovers.shared.info(for: source)
        }
        .accessibilityElement(children: .contain)
    }

    private var line: String {
        var parts: [String] = []
        if let n = source.imageCount ?? info?.count { parts.append(L("\(n) pictures")) }
        parts.append(L("Opened \(HomeWhen.text(source))"))
        return parts.joined(separator: " · ")
    }
}

/// A project's first picture and its count, found once a launch, off the main thread.
@MainActor
final class ProjectCovers {
    static let shared = ProjectCovers()
    struct Info { var cover: UIImage?; var count: Int? }
    private var known: [String: Info] = [:]

    nonisolated static var pictureExtensions: Set<String> { FilmLabCopier.pictureExtensions }

    /// Looked at again next time: photos were added to it.
    func forget(_ source: MacSource) { if let path = source.path { known[path] = nil } }

    func info(for source: MacSource) async -> Info {
        guard let path = source.path else { return Info() }
        if let i = known[path] { return i }
        let found = await Task.detached(priority: .utility) { Self.look(path) }.value
        let info = Info(cover: found.cover.map { UIImage(cgImage: $0) }, count: found.count)
        known[path] = info
        return info
    }

    private nonisolated static func look(_ path: String) -> (cover: CGImage?, count: Int?) {
        let root = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return (nil, nil) }
        var first: URL?
        var count = 0
        for case let url as URL in walk {
            guard pictureExtensions.contains(url.pathExtension.lowercased()) else { continue }
            count += 1
            if first == nil || url.path.localizedStandardCompare(first!.path) == .orderedAscending { first = url }
            if count > 20_000 { break }
        }
        guard let first, let src = CGImageSourceCreateWithURL(first as CFURL, nil) else { return (nil, count == 0 ? nil : count) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
        ]
        return (CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary), count)
    }
}

// MARK: - pieces

/// A button that sinks a little while pressed.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// The home page's ground: the window's, with two slow amber and teal glows.
struct HomeBackdrop: View {
    /// Design A (2026-11-24): the graphite ground with one still, faint warm light from the top, not two drifting glows
    /// (and no 20-a-second timeline redrawing the page under it).
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.accent.opacity(0.10), .clear], center: .top, startRadius: 0, endRadius: 620)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// FilmLab's mark drawn: a 6×6 frame of negative, amber base, a dark rebate and its edge print.
struct NegativeMark: View {
    let size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Theme.rebate)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xE9A25A), Color(hex: 0xB8662E)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 0.62, height: size * 0.62)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: size * 0.05) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1).fill(Theme.edgeInk.opacity(0.85)).frame(width: size * 0.09, height: size * 0.04)
                    }
                }
                .padding(.bottom, size * 0.07)
            }
            .shadow(color: .black.opacity(0.3), radius: size * 0.1, y: size * 0.04)
            .accessibilityHidden(true)
    }
}

/// A strip of 120 film running sideways for ever: frames in warm and cool negatives.
struct FilmStripLoop: View {
    let height: CGFloat
    var speed: Double = 24
    private static let tints: [(UInt32, UInt32)] = [(0xD98B4A, 0x8A4A26), (0x6E8FA0, 0x2E4A5A), (0xE0B070, 0xA0603A),
                                                    (0x8FA27A, 0x46603C), (0xC9785A, 0x6A3A2C), (0x7A86B0, 0x3A4270)]

    var body: some View {
        let frame = height * 0.78
        let pitch = frame + height * 0.12
        TimelineView(.animation) { t in
            let x = (t.date.timeIntervalSinceReferenceDate * speed).truncatingRemainder(dividingBy: Double(pitch) * Double(Self.tints.count))
            GeometryReader { g in
                let n = Int(g.size.width / pitch) + Self.tints.count + 2
                HStack(spacing: height * 0.12) {
                    ForEach(0..<n, id: \.self) { i in
                        let c = Self.tints[i % Self.tints.count]
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Color(hex: c.0), Color(hex: c.1)], startPoint: .top, endPoint: .bottom))
                            .frame(width: frame, height: frame)
                    }
                }
                .offset(x: -CGFloat(x))
                .frame(height: g.size.height)
            }
        }
        .frame(height: height)
        .background(Theme.rebate)
        .overlay(alignment: .top) { edgeText }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }

    private var edgeText: some View {
        Text("FILMLAB  ◂ 1  ◂ 2  ◂ 3  ◂ 4  ◂ 5  ◂ 6  ◂ 7  ◂ 8  ◂ 9  ◂ 10  ◂ 11  ◂ 12")
            .font(.system(size: height * 0.07, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.edgeInk.opacity(0.8))
            .lineLimit(1).fixedSize()
            .padding(.top, height * 0.005)
    }
}
