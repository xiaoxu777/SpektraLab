//  FilmLabWelcome.swift — the tour FilmLab gives the first time it opens.
//
//  The owner, 2026-11-22: "第一次安装的时候要有动画来欢迎以及教怎么弄。类似于 cleanmymac". Five pages over the window, each
//  with a small moving drawing: a welcome, then 图库, 冲洗 and 导出 as the three steps of a roll, then 普通版 or
//  专业版 and the first folder. Skip ends it at any page; the home page's Show the Welcome Tour and Help › Welcome
//  Tour run it again. Seen once, it is not shown at launch again (`FilmLabHome.welcomedKey`).

import SwiftUI

/// A check's launch: `--filmlab-welcome PAGE` (0–5) opens the tour on that page, whether or not it was seen, and the
/// tour then saves nothing: not that it was seen, nor 普通 | 专业, nor where photos go or the photo folder (each is shown
/// chosen, not kept). `--filmlab-welcome-storage copy|inPlace` starts the last page on that choice.
@MainActor
enum WelcomeCheck {
    static let page: Int? = FilmLabCheckArgs.value("--filmlab-welcome").flatMap { Int($0) }
    static var on: Bool { page != nil }
    static var storage: FilmLabImport.Mode? { FilmLabCheckArgs.value("--filmlab-welcome-storage").flatMap(FilmLabImport.Mode.init(rawValue:)) }
}

struct FilmLabWelcome: View {
    @Environment(AppServices.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var page = WelcomeCheck.page.map { min(max($0, 0), FilmLabWelcome.pages - 1) } ?? 0
    @State private var forward = true
    @State private var refused: String?

    static let pages = 6
    private var home: FilmLabHome { .shared }

    var body: some View {
        ZStack {
            HomeBackdrop()
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < Self.pages - 1 {
                        Button(L("Skip")) { home.finishWelcome() }
                            .buttonStyle(.plain)
                            .font(MacMetric.font(12.5, .medium)).foregroundStyle(Theme.dim)
                            .keyboardShortcut(.escape, modifiers: [])
                            .accessibilityIdentifier("filmlab.welcome.skip")
                    }
                }
                .frame(height: MacMetric.pt(24))
                .padding(.horizontal, MacMetric.pt(28)).padding(.top, MacMetric.pt(18))
                Spacer(minLength: MacMetric.pt(10))
                ZStack {
                    content(page)
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: MacMetric.pt(720))
                // The pages slide in and out of this column, so its sides are masked, and only its sides: the mark's
                // light and a chosen card's glow run past its top and bottom and fade out on their own (the owner,
                // 2026-11-25: "被卡掉了一块", when this was `.clipped()`).
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                           .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                        .padding(.vertical, -MacMetric.pt(400))
                }
                Spacer(minLength: MacMetric.pt(10))
                controls
                    .padding(.horizontal, MacMetric.pt(28)).padding(.bottom, MacMetric.pt(26))
            }
        }
        .accessibilityIdentifier("filmlab.welcome")
    }

    // MARK: pages

    @ViewBuilder private func content(_ i: Int) -> some View {
        switch i {
        case 0:
            WelcomePage(art: AnyView(WelcomeArt()),
                        eyebrow: nil,
                        title: L("Welcome to FilmLab"),
                        text: L("Turn your Hasselblad photos into real film. Three steps."))
        case 1:
            WelcomePage(art: AnyView(LibraryArt()),
                        eyebrow: L("Step 1 · Library"),
                        title: L("Bring in your photos"),
                        text: L("Insert the card and press Import Photos. Click a photo to start."))
        case 2:
            WelcomePage(art: AnyView(DevelopArt()),
                        eyebrow: L("Step 2 · Develop"),
                        title: L("Pick a film look"),
                        text: L("Click a thumbnail to change the film. Sliders set brightness and warmth."))
        case 3:
            WelcomePage(art: AnyView(ExportArt()),
                        eyebrow: L("Step 3 · Export"),
                        title: L("Save the finished photos"),
                        text: L("Choose a folder and press Export to save JPEGs. Originals are never changed."))
        case 4:
            ChooseModePage(refused: nil)
        default:
            WelcomeStoragePage(refused: refused)
        }
    }

    private var controls: some View {
        HStack(spacing: MacMetric.pt(14)) {
            if page > 0 {
                Button { go(page - 1) } label: {
                    Text(L("Back")).font(MacMetric.font(13, .semibold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, MacMetric.pt(18)).frame(height: MacMetric.pt(36))
                        .background(RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous).fill(Theme.card)).contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
            } else {
                Color.clear.frame(width: MacMetric.pt(80), height: MacMetric.pt(36))
            }
            Spacer()
            HStack(spacing: MacMetric.pt(7)) {
                ForEach(0..<Self.pages, id: \.self) { i in
                    Capsule().fill(i == page ? Theme.accent : Theme.rule)
                        .frame(width: MacMetric.pt(i == page ? 20 : 7), height: MacMetric.pt(7))
                        .onTapGesture { go(i) }
                }
            }
            .animation(.spring(duration: 0.35), value: page)
            Spacer()
            if page < Self.pages - 1 {
                Button { go(page + 1) } label: {
                    Text(page == 0 ? L("Get Started") : L("Next")).font(MacMetric.font(13, .semibold))
                        .foregroundStyle(Theme.onSelection)
                        .padding(.horizontal, MacMetric.pt(22)).frame(height: MacMetric.pt(36))
                        .background(RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous).fill(Theme.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityIdentifier("filmlab.welcome.next")
            } else {
                HStack(spacing: MacMetric.pt(10)) {
                    Button { home.finishWelcome() } label: {
                        Text(L("Later")).font(MacMetric.font(13, .semibold)).foregroundStyle(Theme.text)
                            .padding(.horizontal, MacMetric.pt(18)).frame(height: MacMetric.pt(36))
                            .background(RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous).fill(Theme.card)).contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    Button { openFolder() } label: {
                        Text(L("Import Photos…")).font(MacMetric.font(13, .semibold))
                            .foregroundStyle(Theme.onSelection)
                            .padding(.horizontal, MacMetric.pt(22)).frame(height: MacMetric.pt(36))
                            .background(RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous).fill(Theme.accent))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityIdentifier("filmlab.welcome.open")
                }
            }
        }
    }

    private func go(_ next: Int) {
        guard next != page, (0..<Self.pages).contains(next) else { return }
        forward = next > page
        withAnimation(.spring(duration: 0.5, bounce: 0.15)) { page = next }
    }

    /// The first import, as the home page's Import Photos… does it (`FilmLabImport`); the tour ends as it begins.
    private func openFolder() {
        refused = nil
        home.finishWelcome()
        FilmLabImport.shared.importPhotos(store: MacLibraryUI.store(model), router: router)
    }
}

/// A page: its drawing, the step's small name, a title and a paragraph, each coming in a moment after the last.
private struct WelcomePage: View {
    let art: AnyView
    let eyebrow: String?
    let title: String
    let text: String
    @State private var shown = false

    var body: some View {
        VStack(spacing: MacMetric.pt(14)) {
            art
                .frame(height: MacMetric.pt(250))
                .frame(maxWidth: .infinity)
                .scaleEffect(shown ? 1 : 0.92)
                .opacity(shown ? 1 : 0)
            if let eyebrow {
                Text(eyebrow.uppercased()).font(MacMetric.font(11, .bold)).tracking(1.2).foregroundStyle(Theme.accent)
                    .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 8)
                    .padding(.top, MacMetric.pt(10))
            }
            Text(title).font(MacMetric.font(28, .bold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 10)
                .padding(.top, eyebrow == nil ? MacMetric.pt(14) : 0)
            Text(text).font(MacMetric.font(14)).foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center).lineSpacing(3)
                .frame(maxWidth: MacMetric.pt(520))
                .fixedSize(horizontal: false, vertical: true)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 12)
        }
        .padding(.horizontal, MacMetric.pt(24))
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.2).delay(0.08)) { shown = true }
        }
    }
}

/// The last page: 普通版 or 专业版, as two cards; the first folder is the button under them.
private struct ChooseModePage: View {
    let refused: String?
    @State private var shown = false
    /// A check's tour shows the choice without saving it (`WelcomeCheck`).
    @State private var checkPro = ProMode.shared.on

    var body: some View {
        VStack(spacing: MacMetric.pt(14)) {
            Text(L("Simple or Pro?")).font(MacMetric.font(28, .bold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(L("Switch any time, top right of the window."))
                .font(MacMetric.font(14)).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
            HStack(spacing: MacMetric.pt(18)) {
                card(pro: false, symbol: "sparkles", title: L("Simple"), who: L("Quick results"),
                     lines: [L("Change film in one click"), L("Brightness and warmth"), L("Add a little film grain"),
                             L("Add a film border"), L("Save as JPEG in one step")])
                card(pro: true, symbol: "slider.horizontal.3", title: L("Pro"), who: L("Fine control"),
                     lines: [L("Everything in Simple, plus:"), L("Curves for the light and dark parts"), L("Glow around highlights"),
                             L("Local edits, like the sky or a face"), L("More formats, print colour settings")])
            }
            .padding(.top, MacMetric.pt(16))
            if let refused {
                Text(L(shown: refused)).font(MacMetric.font(12)).foregroundStyle(Theme.danger)
            }
        }
        .padding(.horizontal, MacMetric.pt(24))
        .opacity(shown ? 1 : 0).scaleEffect(shown ? 1 : 0.96)
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.2)) { shown = true } }
    }

    private func card(pro: Bool, symbol: String, title: String, who: String, lines: [String]) -> some View {
        let chosen = (WelcomeCheck.on ? checkPro : ProMode.shared.on) == pro
        return Button {
            if WelcomeCheck.on { withAnimation(.smooth(duration: 0.25)) { checkPro = pro } } else { FilmLabHome.shared.setPro(pro) }
        } label: {
            VStack(alignment: .leading, spacing: MacMetric.pt(10)) {
                HStack {
                    Image(systemName: symbol).font(MacMetric.font(20, .semibold))
                        .foregroundStyle(chosen ? Theme.accent : Theme.secondaryText)
                    Spacer()
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(MacMetric.font(18)).foregroundStyle(chosen ? Theme.accent : Theme.dim)
                        .contentTransition(.symbolEffect(.replace))
                }
                VStack(alignment: .leading, spacing: MacMetric.pt(2)) {
                    Text(title).font(MacMetric.font(18, .bold)).foregroundStyle(Theme.text)
                    Text(who).font(MacMetric.font(12, .medium)).foregroundStyle(chosen ? Theme.accent : Theme.dim)
                }
                VStack(alignment: .leading, spacing: MacMetric.pt(5)) {
                    ForEach(lines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: MacMetric.pt(6)) {
                            Text("·").foregroundStyle(Theme.dim)
                            Text(line).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(MacMetric.font(12.5))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(MacMetric.pt(18))
            .frame(width: MacMetric.pt(270), height: MacMetric.pt(250), alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(chosen ? Theme.accent : Theme.wall, lineWidth: chosen ? 2 : 1))
            .shadow(color: chosen ? Theme.accent.opacity(0.25) : .black.opacity(0.2), radius: chosen ? 18 : 8, y: 4)
            .scaleEffect(chosen ? 1.03 : 1)
            .animation(.spring(duration: 0.35, bounce: 0.3), value: chosen)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScale())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier(pro ? "filmlab.welcome.pro" : "filmlab.welcome.simple")
    }
}

// MARK: - the drawings

/// Five film looks the drawings cycle through: a name and the picture's two tints.
let welcomeLooks: [(name: String, top: UInt32, bottom: UInt32)] = [
    ("Portra 400", 0xF2C9A0, 0x6C8A9A), ("Gold 200", 0xF5C36A, 0x8A6A3A), ("Ektar 100", 0xF08A5A, 0x2E6A8A),
    ("Vision3 250D", 0xD8B8A0, 0x4A6A70), ("Velvia 50", 0xF0A040, 0x1E5A7A),
]

/// A picture drawn: sky, a sun, two hills, in a look's two tints.
struct SceneSketch: View {
    let top: UInt32, bottom: UInt32
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                LinearGradient(colors: [Color(hex: top), Color(hex: bottom)], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(hex: top).opacity(0.9)).frame(width: w * 0.22).blur(radius: 2)
                    .position(x: w * 0.7, y: h * 0.32)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.72))
                    p.addQuadCurve(to: CGPoint(x: w * 0.55, y: h * 0.66), control: CGPoint(x: w * 0.25, y: h * 0.5))
                    p.addQuadCurve(to: CGPoint(x: w, y: h * 0.7), control: CGPoint(x: w * 0.8, y: h * 0.58))
                    p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                }
                .fill(Color(hex: bottom).opacity(0.85))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.85))
                    p.addQuadCurve(to: CGPoint(x: w, y: h * 0.8), control: CGPoint(x: w * 0.45, y: h * 0.7))
                    p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                }
                .fill(Color.black.opacity(0.35))
            }
        }
    }
}

/// The welcome: the mark coming up out of the strip, with a slow glow.
private struct WelcomeArt: View {
    @State private var up = false
    var body: some View {
        ZStack {
            FilmStripLoop(height: MacMetric.pt(96), speed: 30)
                .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
                .opacity(0.75)
            Circle().fill(Theme.accent.opacity(0.35)).frame(width: MacMetric.pt(170)).blur(radius: 40)
                .scaleEffect(up ? 1.1 : 0.7)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: up)
            NegativeMark(size: MacMetric.pt(128))
                .rotationEffect(.degrees(up ? 0 : -14))
                .scaleEffect(up ? 1 : 0.5)
                .offset(y: up ? 0 : 40)
                .animation(.spring(duration: 0.9, bounce: 0.4).delay(0.15), value: up)
        }
        .onAppear { up = true }
    }
}

/// 图库: a folder's pictures falling into the grid one by one, a pointer choosing one.
private struct LibraryArt: View {
    @State private var landed = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.1)) { t in
            let pick = Int(t.date.timeIntervalSinceReferenceDate / 1.1) % 12
            HStack(spacing: MacMetric.pt(26)) {
                ZStack {
                    Image(systemName: "folder.fill").font(.system(size: MacMetric.pt(84))).foregroundStyle(Theme.accent.opacity(0.9))
                    Text("3FR").font(MacMetric.font(13, .heavy)).foregroundStyle(Theme.onSelection).offset(y: MacMetric.pt(6))
                }
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                Image(systemName: "arrow.right").font(MacMetric.font(22, .semibold)).foregroundStyle(Theme.dim)
                Grid(horizontalSpacing: MacMetric.pt(8), verticalSpacing: MacMetric.pt(8)) {
                    ForEach(0..<3, id: \.self) { r in
                        GridRow {
                            ForEach(0..<4, id: \.self) { c in
                                let i = r * 4 + c
                                let look = welcomeLooks[i % welcomeLooks.count]
                                SceneSketch(top: look.top, bottom: look.bottom)
                                    .frame(width: MacMetric.pt(66), height: MacMetric.pt(46))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white, lineWidth: i == pick ? 2 : 0))
                                    .scaleEffect(i == pick ? 1.08 : 1)
                                    .opacity(landed ? 1 : 0)
                                    .offset(x: landed ? 0 : -60, y: landed ? 0 : -20)
                                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(0.05 * Double(i)), value: landed)
                                    .animation(.spring(duration: 0.3), value: pick)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { landed = true }
    }
}

/// 冲洗: the picture changing film as the cards under it are chosen in turn, the exposure slider moving.
private struct DevelopArt: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.4)) { t in
            let s = t.date.timeIntervalSinceReferenceDate
            let pick = Int(s / 1.4) % welcomeLooks.count
            let look = welcomeLooks[pick]
            VStack(spacing: MacMetric.pt(12)) {
                SceneSketch(top: look.top, bottom: look.bottom)
                    .frame(width: MacMetric.pt(250), height: MacMetric.pt(150))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .bottomLeading) {
                        Text(look.name).font(MacMetric.font(11, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, MacMetric.pt(8)).frame(height: MacMetric.pt(20))
                            .background(Capsule().fill(.black.opacity(0.5))).padding(MacMetric.pt(8))
                            .contentTransition(.opacity)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
                    .animation(.easeInOut(duration: 0.6), value: pick)
                HStack(spacing: MacMetric.pt(8)) {
                    ForEach(welcomeLooks.indices, id: \.self) { i in
                        SceneSketch(top: welcomeLooks[i].top, bottom: welcomeLooks[i].bottom)
                            .frame(width: MacMetric.pt(46), height: MacMetric.pt(32))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white, lineWidth: i == pick ? 2 : 0))
                            .scaleEffect(i == pick ? 1.12 : 1)
                            .animation(.spring(duration: 0.35, bounce: 0.4), value: pick)
                    }
                }
                SliderSketch(label: L("Brightness"), period: 3.2)
            }
        }
    }
}

/// A slider whose knob swings slowly from side to side.
private struct SliderSketch: View {
    let label: String
    let period: Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { t in
            let v = 0.5 + 0.32 * sin(t.date.timeIntervalSinceReferenceDate * 2 * .pi / period)
            HStack(spacing: MacMetric.pt(10)) {
                Text(label).font(MacMetric.font(11, .medium)).foregroundStyle(Theme.dim).fixedSize()
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.card).frame(height: 4)
                        Capsule().fill(Theme.accent).frame(width: g.size.width * v, height: 4)
                        Circle().fill(Color.white).frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .offset(x: g.size.width * v - 7)
                    }
                    .frame(height: g.size.height)
                }
                .frame(width: MacMetric.pt(170), height: 16)
            }
        }
    }
}

/// 导出: the roll's pictures flying into a folder, a bar filling, a tick.
private struct ExportArt: View {
    private static let cycle = 3.6
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { t in
            let p = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle
            let done = p > 0.78
            HStack(spacing: MacMetric.pt(40)) {
                ZStack {
                    ForEach(0..<4, id: \.self) { i in
                        let start = 0.12 * Double(i), local = min(max((p - start) / 0.35, 0), 1)
                        let look = welcomeLooks[i]
                        SceneSketch(top: look.top, bottom: look.bottom)
                            .frame(width: MacMetric.pt(92), height: MacMetric.pt(64))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                            .rotationEffect(.degrees(Double(i - 2) * 6 * (1 - local)))
                            .offset(x: CGFloat(local) * MacMetric.pt(190) + CGFloat(i) * 4, y: -CGFloat(sin(local * .pi)) * 40 + CGFloat(i) * 4)
                            .scaleEffect(1 - 0.55 * local)
                            .opacity(local >= 1 ? 0 : 1)
                    }
                }
                .frame(width: MacMetric.pt(120))
                Spacer().frame(width: MacMetric.pt(30))
                VStack(spacing: MacMetric.pt(12)) {
                    ZStack {
                        Image(systemName: "folder.fill").font(.system(size: MacMetric.pt(80))).foregroundStyle(Theme.accent.opacity(0.9))
                        Image(systemName: "checkmark").font(MacMetric.font(26, .heavy)).foregroundStyle(Theme.onSelection)
                            .offset(y: MacMetric.pt(6))
                            .scaleEffect(done ? 1 : 0.2).opacity(done ? 1 : 0)
                            .animation(.spring(duration: 0.4, bounce: 0.5), value: done)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.card).frame(width: MacMetric.pt(130), height: 6)
                        Capsule().fill(Theme.accent).frame(width: MacMetric.pt(130) * min(p / 0.78, 1), height: 6)
                    }
                    Text(done ? L("\(4) saved") : "JPEG · 24 MP").font(MacMetric.font(11, .medium)).foregroundStyle(Theme.dim)
                        .contentTransition(.opacity)
                }
            }
        }
    }
}
