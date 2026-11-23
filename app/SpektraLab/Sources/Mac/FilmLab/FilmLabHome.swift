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
    static let welcomedKey = "filmlab.welcomed"

    /// The home page is over the window. On at every launch.
    var shown = true
    /// The welcome tour is over the window: the first launch, or asked for again (Help, the home page).
    var welcome = !UserDefaults.standard.bool(forKey: FilmLabHome.welcomedKey)

    func finishWelcome() {
        UserDefaults.standard.set(true, forKey: Self.welcomedKey)
        withAnimation(.easeInOut(duration: 0.45)) { welcome = false }
    }

    func showHome() { withAnimation(.easeInOut(duration: 0.3)) { shown = true } }
    func hideHome() { withAnimation(.easeInOut(duration: 0.3)) { shown = false } }

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
        .background(Capsule().fill(Theme.card))
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
                if selected { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "thumb", in: thumb) }
            }
            .contentShape(Capsule())
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
    @State private var storageShown = false

    private var home: FilmLabHome { .shared }

    var body: some View {
        let store = MacLibraryUI.store(model)
        let projects = store.sources.filter { $0.kind != .appLibrary }
            .sorted { ($0.openedAt ?? $0.addedAt) > ($1.openedAt ?? $1.addedAt) }
        ZStack {
            HomeBackdrop()
            VStack(alignment: .leading, spacing: 0) {
                header(store, hasProjects: !projects.isEmpty)
                    .padding(.horizontal, MacMetric.pt(40))
                    .padding(.top, MacMetric.pt(34))
                if projects.isEmpty {
                    emptyState(store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: MacMetric.pt(220), maximum: MacMetric.pt(320)),
                                                     spacing: MacMetric.pt(20))],
                                  alignment: .leading, spacing: MacMetric.pt(22)) {
                            ForEach(Array(projects.enumerated()), id: \.element.id) { i, source in
                                ProjectCard(source: source, selected: source.id == store.selectedSourceID,
                                            open: { open(source, store) },
                                            remove: { store.remove(source: source.id) })
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 18)
                                    .animation(.spring(duration: 0.55, bounce: 0.25).delay(0.04 * Double(min(i, 12))),
                                               value: appeared)
                            }
                        }
                        .padding(.horizontal, MacMetric.pt(40))
                        .padding(.vertical, MacMetric.pt(24))
                    }
                    .scrollIndicators(.automatic)
                }
                footer(store)
                    .padding(.horizontal, MacMetric.pt(40))
                    .padding(.bottom, MacMetric.pt(22))
            }
        }
        .onAppear { appeared = true }
        .accessibilityIdentifier("filmlab.home")
    }

    private func header(_ store: any MacLibraryData, hasProjects: Bool) -> some View {
        HStack(alignment: .center, spacing: MacMetric.pt(16)) {
            NegativeMark(size: MacMetric.pt(46))
            VStack(alignment: .leading, spacing: MacMetric.pt(3)) {
                Text(Brand.name).font(MacMetric.font(26, .bold)).foregroundStyle(Theme.text)
                Text(hasProjects ? L("Welcome back. Pick up a roll, or import new photos.")
                                 : L("Hasselblad files in, film out."))
                    .font(MacMetric.font(13)).foregroundStyle(Theme.dim)
                storageLine
            }
            Spacer(minLength: MacMetric.pt(16))
            if store.selectedSource != nil {
                Button { home.hideHome() } label: {
                    Text(L("Back to Library")).font(MacMetric.font(13, .semibold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, MacMetric.pt(16)).frame(height: MacMetric.pt(34))
                        .background(Capsule().fill(Theme.card))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("filmlab.home.back")
            }
            openButton(store)
        }
    }

    /// Where imported photos go, and the way to change it.
    private var storageLine: some View {
        let imports = FilmLabImport.shared
        return Button { storageShown = true } label: {
            HStack(spacing: MacMetric.pt(5)) {
                Image(systemName: imports.mode == .copy ? "folder" : "sdcard").font(MacMetric.font(11))
                Text(imports.mode == .copy ? L("Imports are copied to \(imports.folderShown)") : L("Imports stay where they are"))
                    .font(MacMetric.font(11.5)).lineLimit(1).truncationMode(.middle)
                Text(L("Change…")).font(MacMetric.font(11.5, .semibold)).foregroundStyle(Theme.accent)
            }
            .foregroundStyle(Theme.dim)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $storageShown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: MacMetric.pt(12)) {
                Text(L("Where should imported photos go?")).font(MacMetric.font(15, .bold)).foregroundStyle(Theme.text)
                StorageChoice(compact: true)
            }
            .padding(MacMetric.pt(18))
            .frame(width: MacMetric.pt(420))
            .background(Theme.background)
            .interfaceScaled(.macPoints)
        }
        .accessibilityIdentifier("filmlab.home.storage")
    }

    private func openButton(_ store: any MacLibraryData, large: Bool = false) -> some View {
        Button { openFolder(store) } label: {
            HStack(spacing: MacMetric.pt(8)) {
                Image(systemName: "square.and.arrow.down").font(MacMetric.font(large ? 15 : 13, .bold))
                Text(L("Import Photos…")).font(MacMetric.font(large ? 15 : 13, .semibold))
            }
            .foregroundStyle(Theme.onSelection)
            .padding(.horizontal, MacMetric.pt(large ? 26 : 18))
            .frame(height: MacMetric.pt(large ? 44 : 34))
            .background(Capsule().fill(Theme.accent))
            .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 4)
            .contentShape(Capsule())
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
            Text(L("Put the camera's card in this Mac and choose its folder of photos. Each import becomes a project here, like a roll of film."))
                .font(MacMetric.font(13)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center).frame(maxWidth: MacMetric.pt(440))
                .fixedSize(horizontal: false, vertical: true)
            openButton(store, large: true).padding(.top, MacMetric.pt(4))
            if let refused {
                Text(L(shown: refused)).font(MacMetric.font(12)).foregroundStyle(Theme.danger)
            }
        }
        .padding(MacMetric.pt(30))
    }

    private func footer(_ store: any MacLibraryData) -> some View {
        HStack(spacing: MacMetric.pt(14)) {
            ProModeSwitch(large: true)
            Text(ProMode.shared.on ? L("Pro: every tool, for fine control — curves, grain, glow, local edits and more.")
                                   : L("Simple: just the essentials — pick a film, adjust brightness and colour, export."))
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
    let open: () -> Void
    let remove: () -> Void
    @State private var info: ProjectCovers.Info?
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                cover
                VStack(alignment: .leading, spacing: MacMetric.pt(3)) {
                    HStack(spacing: MacMetric.pt(6)) {
                        Text(source.name).font(MacMetric.font(14, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        if source.status == .offline {
                            Image(systemName: "externaldrive.badge.xmark").font(MacMetric.font(11)).foregroundStyle(Theme.dim)
                        }
                    }
                    Text(subtitle).font(MacMetric.font(11.5)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                .padding(.horizontal, MacMetric.pt(12))
                .padding(.vertical, MacMetric.pt(10))
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Theme.accent : (hovering ? Theme.rule : Theme.wall), lineWidth: selected ? 1.5 : 1))
            .shadow(color: .black.opacity(hovering ? 0.35 : 0.18), radius: hovering ? 16 : 8, y: hovering ? 8 : 3)
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScale())
        .onHover { hovering = $0 }
        .contextMenu {
            Button(L("Open")) { open() }
            if let url = source.url { Button(L("Show in Finder")) { UIApplication.shared.open(url) } }
            Divider()
            Button(L("Remove from Home"), role: .destructive) { remove() }
        }
        .task(id: source.path) { info = await ProjectCovers.shared.info(for: source) }
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

    private var subtitle: String {
        var parts: [String] = []
        if let n = source.imageCount ?? info?.count { parts.append(L("\(n) pictures")) }
        // Opening a project marks it opened now: never "in 0 seconds", and under a minute is "now".
        let now = Date()
        let when = min(source.openedAt ?? source.addedAt, now)
        let f = RelativeDateTimeFormatter()
        f.locale = Language.shared.current.locale
        f.unitsStyle = .full
        f.dateTimeStyle = .named
        parts.append(now.timeIntervalSince(when) < 60 ? f.localizedString(fromTimeInterval: 0) : f.localizedString(for: when, relativeTo: now))
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
    var body: some View {
        ZStack {
            Theme.background
            TimelineView(.animation(minimumInterval: 1 / 20)) { t in
                let s = t.date.timeIntervalSinceReferenceDate
                GeometryReader { g in
                    let w = g.size.width, h = g.size.height
                    Circle().fill(Theme.accent.opacity(0.16))
                        .frame(width: w * 0.55).blur(radius: 90)
                        .position(x: w * (0.22 + 0.06 * sin(s / 7)), y: h * (0.2 + 0.05 * cos(s / 9)))
                    Circle().fill(Color(hex: 0x3D7C8C).opacity(0.14))
                        .frame(width: w * 0.5).blur(radius: 100)
                        .position(x: w * (0.8 + 0.05 * cos(s / 8)), y: h * (0.78 + 0.05 * sin(s / 6)))
                }
            }
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
