//  FilmLabWelcomeStorage.swift — the welcome tour's last page: where imported photos go, and a drawing of what each
//  choice does.
//
//  The owner, 2026-11-25: "我希望选择的时候能有动画直观的知道每个选择的影响。比方说第一个选项会有一个，照片从卡进入到电脑里的
//  动画。第二个则是照片尝试进入电脑，但是被弹飞了。" So the drawing over the two choices (`StorageArt`) plays the one chosen, a
//  loop of about three seconds, from its start again whenever the choice changes:
//
//  - **Copy**: three photos rise out of the card and fly into the Mac's screen, one after another; the card is pulled
//    out; the photos stay on the screen.
//  - **Leave them**: a photo rises out of the card, flies at the Mac, bounces off its screen and falls back into the card.
//
//  It says it without words. Reduce Motion shows each one still: the photos in the Mac and the card gone, or the photo
//  bouncing off. The choices are the home page's (`StorageChoice`, FilmLabImport.swift) said shorter, with the photo folder
//  inside the first so the page keeps its height when the choice changes.

import SwiftUI

struct WelcomeStoragePage: View {
    let refused: String?
    @State private var shown = false
    /// A check's tour shows the choice without saving it (`WelcomeCheck`).
    @State private var checkMode = WelcomeCheck.storage ?? FilmLabImport.shared.mode
    private var imports: FilmLabImport { .shared }
    private var mode: FilmLabImport.Mode { WelcomeCheck.on ? checkMode : imports.mode }

    var body: some View {
        VStack(spacing: MacMetric.pt(14)) {
            Text(L("Where should your photos go?")).font(MacMetric.font(28, .bold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            StorageArt(mode: mode)
            VStack(alignment: .leading, spacing: MacMetric.pt(10)) {
                option(.copy, symbol: "externaldrive.badge.checkmark", title: L("Copy to my photo folder (recommended)"),
                       text: L("Take the card out once it is copied."))
                option(.inPlace, symbol: "sdcard", title: L("Leave them where they are"),
                       text: L("Keep the card in while you edit."))
            }
            .frame(maxWidth: MacMetric.pt(520))
            Text(L("You can change this later on the home page."))
                .font(MacMetric.font(12)).foregroundStyle(Theme.dim)
            if let refused {
                Text(L(shown: refused)).font(MacMetric.font(12)).foregroundStyle(Theme.danger)
            }
        }
        .padding(.horizontal, MacMetric.pt(24))
        .opacity(shown ? 1 : 0).scaleEffect(shown ? 1 : 0.96)
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.2)) { shown = true } }
    }

    private func choose(_ m: FilmLabImport.Mode) {
        guard m != mode else { return }
        withAnimation(.spring(duration: 0.3)) {
            if WelcomeCheck.on { checkMode = m } else { imports.mode = m }
        }
    }

    private func option(_ m: FilmLabImport.Mode, symbol: String, title: String, text: String) -> some View {
        let chosen = mode == m
        return HStack(alignment: .top, spacing: MacMetric.pt(12)) {
            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                .font(MacMetric.font(17)).foregroundStyle(chosen ? Theme.accent : Theme.dim)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: MacMetric.pt(3)) {
                HStack(spacing: MacMetric.pt(6)) {
                    Image(systemName: symbol).font(MacMetric.font(13, .semibold)).foregroundStyle(Theme.secondaryText)
                    Text(title).font(MacMetric.font(14, .semibold)).foregroundStyle(Theme.text)
                }
                Text(text).font(MacMetric.font(12.5)).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if m == .copy { folderLine(off: !chosen) }
            }
            Spacer(minLength: 0)
        }
        .padding(MacMetric.pt(14))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(chosen ? Theme.accent : Theme.wall, lineWidth: chosen ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // A tap, not a Button: the photo folder's Change… is a button inside the first.
        .onTapGesture { choose(m) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { choose(m) }
        .accessibilityIdentifier(m == .copy ? "filmlab.welcome.storage.copy" : "filmlab.welcome.storage.inplace")
    }

    /// The photo folder, and Change…; faint while Leave them is chosen (a tap on it chooses Copy).
    private func folderLine(off: Bool) -> some View {
        HStack(spacing: MacMetric.pt(6)) {
            Image(systemName: "folder.fill").font(MacMetric.font(11)).foregroundStyle(Theme.accent)
            Text(imports.folderShown).font(MacMetric.font(12, .medium)).foregroundStyle(Theme.text)
                .lineLimit(1).truncationMode(.middle)
            Button {
                if !WelcomeCheck.on { Task { await imports.chooseFolder() } }
            } label: {
                Text(L("Change…")).font(MacMetric.font(12, .semibold)).foregroundStyle(Theme.accent).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(off)
            .accessibilityIdentifier("filmlab.storage.folder")
        }
        .padding(.top, MacMetric.pt(5))
        .opacity(off ? 0.4 : 1)
        .help(imports.folder.path)
    }
}

// MARK: - the drawing

/// What the choice does, played: a card, a Mac, and the photos between them. Drawn in a 440 × 150 field of design
/// points and scaled to the window's (`MacMetric`).
private struct StorageArt: View {
    let mode: FilmLabImport.Mode
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var start = Date.now

    private static let size = CGSize(width: 440, height: 150)
    private static let copyCycle = 3.4, keepCycle = 2.8

    // Where things are, in the field.
    private static let card = CGPoint(x: 96, y: 90)
    private static let cardSize = CGSize(width: 56, height: 74)
    private static let screen = CGPoint(x: 306, y: 64)
    private static let screenSize = CGSize(width: 156, height: 102)
    private static let tileSize = CGSize(width: 30, height: 20)
    /// The three photos as they stand in the card, their tops showing over its edge.
    private static let peeks: [(p: CGPoint, r: Double)] = [(CGPoint(x: 85, y: 50), -9), (CGPoint(x: 96, y: 46), 0), (CGPoint(x: 107, y: 50), 9)]
    /// Clear of the card's top: where a photo is once it has risen out.
    private static let riseY: CGFloat = 26
    /// Their places on the screen; a photo there is drawn this much larger.
    private static let slots: [CGPoint] = [CGPoint(x: 262, y: 68), CGPoint(x: 306, y: 68), CGPoint(x: 350, y: 68)]
    private static let slotScale: CGFloat = 38 / 30
    /// Where a photo meets the screen's edge and is turned back.
    private static let wallX: CGFloat = screen.x - screenSize.width / 2
    private static let looks = [0, 2, 4]

    var body: some View {
        // A quarter larger than its field: the page has the room at the smallest window (1059 × 768).
        let k = MacMetric.pt(125) / 100
        TimelineView(.animation(paused: still)) { tl in
            let cycle = mode == .copy ? Self.copyCycle : Self.keepCycle
            let s = still ? (mode == .copy ? 2.8 : 1.12) : tl.date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
            Group {
                if mode == .copy { copyScene(max(s, 0)) } else { keepScene(max(s, 0)) }
            }
            .frame(width: Self.size.width, height: Self.size.height)
        }
        .scaleEffect(k)
        .frame(width: Self.size.width * k, height: Self.size.height * k)
        .onAppear { start = .now }
        .onChange(of: mode) { start = .now }
        .accessibilityHidden(true)
    }

    // MARK: copy

    /// Three photos leave the card one by one and land on the screen; the card is pulled out; the photos stay.
    private func copyScene(_ s: Double) -> some View {
        let launch = (0..<3).map { 0.25 + 0.3 * Double($0) }
        let landed = (0..<3).map { s >= launch[$0] + 0.8 && s < 3.2 }
        let pull = ease(.inOut, phase(s, 1.95, 2.4)) * (1 - ease(.out, phase(s, 3.0, 3.4)))
        let back = phase(s, 3.0, 3.4) > 0
        let fade = 1 - phase(s, 3.0, 3.2)
        let glow = Double(landed.filter { $0 }.count) / 3 * fade
        return ZStack {
            // The card's place once it is out: a faint outline.
            CardShape().stroke(Theme.dim.opacity(0.5 * pull), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                .position(Self.card)
            mac(slotsFilled: landed, glow: glow, shake: 0, flash: 0)
            // The card, the photos still in it (or rising out of it) behind its face.
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let t = launch[i]
                    if s < t + 0.22 || back {
                        let r = back ? 0 : ease(.out, phase(s, t, t + 0.22))
                        tile(i)
                            .rotationEffect(.degrees(Self.peeks[i].r * (1 - r)))
                            .position(x: Self.peeks[i].p.x, y: lerp(Self.peeks[i].p.y, Self.riseY, r))
                    }
                }
                cardFace.position(Self.card)
            }
            // Out and down a little, gone before it leaves the drawing (it never reaches the choices under it).
            .offset(y: 24 * pull)
            .opacity(1 - min(pull * 1.4, 1))
            // The photos in flight, then on the screen.
            ForEach(0..<3, id: \.self) { i in
                let t = launch[i]
                if s >= t + 0.22 && fade > 0 {
                    let f = phase(s, t + 0.22, t + 0.8), e = ease(.inOut, f)
                    let from = CGPoint(x: Self.peeks[i].p.x, y: Self.riseY), to = Self.slots[i]
                    let land = 1 + 0.12 * pop(s - (t + 0.8))
                    tile(i)
                        .scaleEffect((1 + (Self.slotScale - 1) * e) * land)
                        .rotationEffect(.degrees(-7 * sin(.pi * e)))
                        .shadow(color: .black.opacity(0.45 * sin(.pi * e)), radius: 6, y: 4)
                        .position(x: lerp(from.x, to.x, e), y: lerp(from.y, to.y, e) - 30 * sin(.pi * e))
                        .opacity(fade)
                }
            }
            check(s - 1.8, fade: fade)
        }
    }

    /// The tick on the screen's corner once all three are in.
    private func check(_ u: Double, fade: Double) -> some View {
        let v = u <= 0 ? 0 : 1 - exp(-9 * u) * cos(13 * u)
        return ZStack {
            Circle().fill(Theme.accent)
            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.onSelection)
        }
        .frame(width: 20, height: 20)
        .shadow(color: Theme.accent.opacity(0.5), radius: 6)
        .scaleEffect(max(v, 0))
        .opacity(u <= 0 ? 0 : fade)
        .position(x: Self.screen.x + Self.screenSize.width / 2 - 6, y: Self.screen.y - Self.screenSize.height / 2 + 6)
    }

    // MARK: leave them

    /// A photo leaves the card, flies at the screen, is knocked back off it and falls back into the card.
    private func keepScene(_ s: Double) -> some View {
        let i = 1
        let t0 = 0.3, hit = 1.0, away = 1.14, home = 1.75, inCard = 1.95
        let u = s - hit
        let shake = u > 0 ? 3.5 * exp(-9 * u) * sin(42 * u) : 0
        let flash = u > 0 ? exp(-5 * u) : 0
        let bump = 1 + 0.07 * pop(s - inCard)
        let impact = CGPoint(x: Self.wallX - Self.tileSize.width / 2 - 1, y: Self.screen.y + 2)
        let rise = CGPoint(x: Self.peeks[i].p.x, y: Self.riseY)
        return ZStack {
            mac(slotsFilled: [false, false, false], glow: 0, shake: shake, flash: flash)
            // The knock: two rings out from where it struck.
            ForEach(0..<2, id: \.self) { n in
                let r = phase(s, hit + 0.06 * Double(n), hit + 0.5 + 0.06 * Double(n))
                Circle().trim(from: 0.36, to: 0.64)
                    .stroke(Theme.danger.opacity((1 - r) * (r > 0 ? 1 : 0)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 14 + 40 * r, height: 14 + 40 * r)
                    .position(x: Self.wallX + 2, y: impact.y)
            }
            ZStack {
                ForEach(0..<3, id: \.self) { j in
                    if j != i {
                        tile(j).rotationEffect(.degrees(Self.peeks[j].r)).position(Self.peeks[j].p)
                    } else if s < t0 + 0.22 {
                        let r = ease(.out, phase(s, t0, t0 + 0.22))
                        tile(j).position(x: Self.peeks[j].p.x, y: lerp(Self.peeks[j].p.y, Self.riseY, r))
                    } else if s >= home {
                        let d = ease(.inOut, phase(s, home, inCard))
                        tile(j).position(x: Self.peeks[j].p.x, y: lerp(Self.riseY, Self.peeks[j].p.y, d))
                    }
                }
                cardFace.position(Self.card)
            }
            .scaleEffect(bump, anchor: .bottom)
            if s >= t0 + 0.22 && s < home {
                if s < hit {
                    // Out, faster and faster, at the screen.
                    let e = ease(.in, phase(s, t0 + 0.22, hit))
                    tile(i)
                        .rotationEffect(.degrees(6 * e))
                        .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
                        .position(x: lerp(rise.x, impact.x, e), y: lerp(rise.y, impact.y, e) - 16 * sin(.pi * min(e * 1.2, 1)))
                } else if s < away {
                    // Struck: flattened against the screen for a moment.
                    let q = sin(.pi * phase(s, hit, away))
                    tile(i)
                        .scaleEffect(x: 1 - 0.38 * q, y: 1 + 0.18 * q, anchor: .trailing)
                        .rotationEffect(.degrees(6))
                        .position(impact)
                } else {
                    // Knocked back over to the card, tumbling.
                    let e = ease(.out, phase(s, away, home))
                    tile(i)
                        .rotationEffect(.degrees(6 - 366 * e))
                        .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
                        .position(x: lerp(impact.x, rise.x, e), y: lerp(impact.y, rise.y, e) - 26 * sin(.pi * e))
                }
            }
        }
    }

    // MARK: pieces

    /// The Mac: a screen on a stand, its three places for photos, a warm light as they fill.
    private func mac(slotsFilled: [Bool], glow: Double, shake: Double, flash: Double) -> some View {
        let w = Self.screenSize.width, h = Self.screenSize.height
        return ZStack {
            // The stand.
            Path { p in
                p.move(to: CGPoint(x: Self.screen.x - 9, y: Self.screen.y + h / 2))
                p.addLine(to: CGPoint(x: Self.screen.x + 9, y: Self.screen.y + h / 2))
                p.addLine(to: CGPoint(x: Self.screen.x + 13, y: Self.screen.y + h / 2 + 17))
                p.addLine(to: CGPoint(x: Self.screen.x - 13, y: Self.screen.y + h / 2 + 17))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color(hex: 0x24252A), Color(hex: 0x34363C)], startPoint: .top, endPoint: .bottom))
            Capsule().fill(Color(hex: 0x3A3C42))
                .frame(width: 66, height: 5)
                .position(x: Self.screen.x, y: Self.screen.y + h / 2 + 19)
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x34363C), Color(hex: 0x26272C)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: 0x111214))
                    .overlay(RadialGradient(colors: [Theme.accent.opacity(0.28 * glow), .clear], center: .center,
                                            startRadius: 0, endRadius: 90))
                    .padding(6)
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Theme.dim.opacity(slotsFilled[i] ? 0 : 0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                        .frame(width: Self.tileSize.width * Self.slotScale, height: Self.tileSize.height * Self.slotScale)
                        .position(x: Self.slots[i].x - Self.screen.x + w / 2, y: Self.slots[i].y - Self.screen.y + h / 2)
                }
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.danger.opacity(0.85 * flash), lineWidth: 2)
            }
            .frame(width: w, height: h)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
            .position(Self.screen)
        }
        .offset(x: shake)
    }

    /// The card's face: dark, a corner cut, an amber label.
    private var cardFace: some View {
        let w = Self.cardSize.width, h = Self.cardSize.height
        return ZStack {
            CardShape().fill(LinearGradient(colors: [Color(hex: 0x3A3C42), Color(hex: 0x27282D)], startPoint: .top, endPoint: .bottom))
            CardShape().stroke(Color.white.opacity(0.08), lineWidth: 1)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accent, Color(hex: 0xB8662E)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: w - 14, height: 30)
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Theme.rebate.opacity(0.55)).frame(width: 22, height: 3)
                        Capsule().fill(Theme.rebate.opacity(0.35)).frame(width: 14, height: 3)
                    }
                    .padding(.leading, 6)
                }
                .offset(y: h / 2 - 7 - 15)
            // The lock switch on its side.
            RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0x4A4C52))
                .frame(width: 3, height: 10)
                .offset(x: -w / 2 + 1.5, y: -h / 2 + 22)
        }
        .frame(width: w, height: h)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    private func tile(_ i: Int) -> some View {
        let look = welcomeLooks[Self.looks[i]]
        return SceneSketch(top: look.top, bottom: look.bottom)
            .frame(width: Self.tileSize.width, height: Self.tileSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 0.75))
    }
}

/// A memory card's outline: a rounded rectangle with its top right corner cut.
private struct CardShape: Shape {
    func path(in r: CGRect) -> Path {
        let c: CGFloat = r.width * 0.26, rad: CGFloat = 5
        var p = Path()
        p.move(to: CGPoint(x: r.minX + rad, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rad), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + rad, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - motion

// The tour's drawings share these (`WelcomeMotion`, FilmLabWelcomeExport.swift).
private typealias Ease = WelcomeEase
private func phase(_ s: Double, _ a: Double, _ b: Double) -> Double { WelcomeMotion.phase(s, a, b) }
private func ease(_ kind: Ease, _ t: Double) -> Double { WelcomeMotion.ease(kind, t) }
private func pop(_ u: Double) -> Double { WelcomeMotion.pop(u) }
private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { WelcomeMotion.lerp(a, b, t) }
