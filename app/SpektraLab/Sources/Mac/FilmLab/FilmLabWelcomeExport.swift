//  FilmLabWelcomeExport.swift — the welcome tour's 导出 drawing, and the small motion helpers the tour's drawings share.
//
//  The owner, 2026-11-25, of 第三步 · 导出: "我倾向于让照片飞到文件夹". So `ExportArt` plays a loop of about three
//  seconds: the photos leave their stack one by one, fly over in an arc and drop into an amber folder (the folder gives a
//  little each time one lands, the bar under it moves on a quarter); when the last is in, a tick and "4 saved"; then the
//  photos sink away, the stack fills again and it starts over. Reduce Motion shows the end still: the photos in the
//  folder, the bar full, the tick. Drawn like the storage page's card-to-Mac drawing (FilmLabWelcomeStorage.swift): in a
//  field of design points, scaled to the window, from these helpers.

import SwiftUI

// MARK: - motion

enum WelcomeEase { case `in`, out, inOut }

enum WelcomeMotion {
    /// How far `s` is from `a` to `b`, held to 0…1.
    static func phase(_ s: Double, _ a: Double, _ b: Double) -> Double { min(max((s - a) / (b - a), 0), 1) }

    static func ease(_ kind: WelcomeEase, _ t: Double) -> Double {
        switch kind {
        case .in: t * t
        case .out: 1 - pow(1 - t, 3)
        case .inOut: t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        }
    }

    /// A spring's wobble after a landing, `u` seconds on: 0 before it, a few fast swings dying away.
    static func pop(_ u: Double) -> Double { u <= 0 ? 0 : exp(-8 * u) * sin(18 * u) }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
}

// MARK: - the drawing

/// 导出: the stack of finished photos flying one by one into a folder, a bar filling, a tick.
struct ExportArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    /// Still under Reduce Motion, or in a check's launch with `--filmlab-reduce-motion` (`FilmLabExportFlight`).
    private var still: Bool { reduceMotion || FilmLabExportFlight.calmCheck }

    private static let size = CGSize(width: 440, height: 176)
    private static let cycle = 3.2
    private static let count = 4

    // Where things are, in the field.
    private static let photoSize = CGSize(width: 84, height: 58)
    /// The stack's top photo; each one under it sits up and to the right, turned a little more.
    private static let stack = CGPoint(x: 112, y: 92)
    private static let stackStep = CGSize(width: 12, height: -9)
    private static let stackTurn = 6.0
    private static let folder = CGPoint(x: 330, y: 76)
    private static let folderSize = CGSize(width: 124, height: 92)
    /// How far down the folder its front starts: what drops in goes behind it.
    private static let frontTop: CGFloat = 26
    /// A photo in the folder: this small, its top showing over the front, fanned.
    private static let inScale: CGFloat = 0.42
    private static let rests: [(x: CGFloat, r: Double)] = [(-24, -7), (-8, -2), (8, 3), (24, 8)]
    private static let restY: CGFloat = folder.y - folderSize.height / 2 + frontTop + 2
    private static let bar = CGPoint(x: 330, y: 142)
    private static let barWidth: CGFloat = 130
    private static let looks = [0, 2, 1, 4]

    // When things happen, in seconds of the loop.
    private static let launches = (0..<count).map { 0.15 + 0.4 * Double($0) }
    private static let flight = 0.72
    private static var lands: [Double] { launches.map { $0 + flight } }
    private static let doneAt = 2.25, clearAt = 2.72

    var body: some View {
        // A quarter larger than its field, as the storage page's drawing is.
        let k = MacMetric.pt(125) / 100
        TimelineView(.animation(paused: still)) { tl in
            let s = still ? Self.clearAt - 0.05 : tl.date.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.cycle)
            scene(max(s, 0))
                .frame(width: Self.size.width, height: Self.size.height)
                .scaleEffect(k)
                .frame(width: Self.size.width * k, height: Self.size.height * k)
                // The words outside the scaling, so they are drawn at their own size.
                .overlay { caption(max(s, 0)).position(x: Self.bar.x * k, y: (Self.bar.y + 24) * k) }
        }
        .onAppear { start = .now }
        .accessibilityHidden(true)
    }

    private func scene(_ s: Double) -> some View {
        let landed = Self.lands.map { s >= $0 && s < Self.clearAt + 0.4 }
        // The folder gives a little under each photo that lands.
        let settle = Self.lands.reduce(0) { $0 + WelcomeMotion.pop(s - $1) }
        let fill = Self.lands.reduce(0) { $0 + WelcomeMotion.ease(.out, WelcomeMotion.phase(s, $1, $1 + 0.35)) } / Double(Self.count)
        let drain = WelcomeMotion.ease(.inOut, WelcomeMotion.phase(s, Self.clearAt, Self.clearAt + 0.35))
        return ZStack {
            // Where the stack was: a faint outline as it empties.
            let gone = WelcomeMotion.phase(s, Self.lands[Self.count - 1] - 0.3, Self.lands[Self.count - 1]) * (1 - drain)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Theme.dim.opacity(0.45 * gone), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: Self.photoSize.width, height: Self.photoSize.height)
                .position(Self.stack)
            // The stack, the lower photos moving up as the top one leaves; drawn bottom first.
            ForEach((0..<Self.count).reversed(), id: \.self) { i in stacked(i, s) }
            ZStack {
                folderBack
                // Photos dropping in and lying there, behind the front.
                ForEach(0..<Self.count, id: \.self) { i in
                    if landed[i] { resting(i, s, drain: drain) }
                }
                // In the air: over the folder's back, behind its front, so the last of the drop goes into it.
                ForEach(0..<Self.count, id: \.self) { i in flying(i, s) }
                folderFront
                check(s)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .scaleEffect(x: 1 + 0.025 * settle, y: 1 - 0.05 * settle,
                         anchor: UnitPoint(x: Self.folder.x / Self.size.width,
                                           y: (Self.folder.y + Self.folderSize.height / 2) / Self.size.height))
            progress(fill * (1 - drain))
        }
    }

    // MARK: the photos

    /// A photo in the stack: there until it leaves, back once the folder is cleared.
    @ViewBuilder private func stacked(_ i: Int, _ s: Double) -> some View {
        let t = Self.launches[i]
        // How many above it have left, smoothly: its place in the stack.
        let above = (0..<i).reduce(0.0) { $0 + WelcomeMotion.ease(.inOut, WelcomeMotion.phase(s, Self.launches[$1] + 0.1, Self.launches[$1] + 0.45)) }
        let back = s >= Self.clearAt + 0.05 * Double(Self.count - 1 - i)
        if s < t || back {
            // Refilling: each drops back into its place, the bottom one first.
            let r = back ? WelcomeMotion.ease(.out, WelcomeMotion.phase(s, Self.clearAt + 0.06 * Double(Self.count - 1 - i),
                                                                    Self.clearAt + 0.06 * Double(Self.count - 1 - i) + 0.3)) : 1
            let rank = back ? Double(i) : Double(i) - above
            photo(i)
                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                .rotationEffect(.degrees(-2 + Self.stackTurn * rank))
                .scaleEffect(0.9 + 0.1 * r)
                .opacity(r)
                .position(x: Self.stack.x + Self.stackStep.width * rank,
                          y: Self.stack.y + Self.stackStep.height * rank - 14 * (1 - r))
        }
    }

    /// A photo on its way: lifted off the stack, over in an arc, smaller as it nears the folder, then down into it.
    @ViewBuilder private func flying(_ i: Int, _ s: Double) -> some View {
        let t = Self.launches[i]
        let f = WelcomeMotion.phase(s, t, t + Self.flight)
        if f > 0 && f < 1 {
            // Across quickly, down late: it comes to the folder from above.
            let fx = WelcomeMotion.ease(.inOut, min(f / 0.82, 1))
            let fy = WelcomeMotion.ease(.inOut, f)
            let to = CGPoint(x: Self.folder.x + Self.rests[i].x, y: Self.restY)
            let lift = 46 * sin(.pi * min(f / 0.82, 1)) + 26 * (1 - WelcomeMotion.ease(.in, WelcomeMotion.phase(f, 0.7, 1))) * WelcomeMotion.phase(f, 0.4, 0.7)
            let turn = -2 * (1 - fx) + Self.rests[i].r * fx - 10 * sin(.pi * fx)
            photo(i)
                .shadow(color: .black.opacity(0.45 * sin(.pi * fx)), radius: 8, y: 5)
                .rotationEffect(.degrees(turn))
                .scaleEffect(1 - (1 - Self.inScale) * WelcomeMotion.ease(.inOut, f))
                .position(x: WelcomeMotion.lerp(Self.stack.x, to.x, fx),
                          y: WelcomeMotion.lerp(Self.stack.y, to.y, fy) - lift)
        }
    }

    /// A photo in the folder, its top over the front; when the loop ends they sink away into it.
    private func resting(_ i: Int, _ s: Double, drain: Double) -> some View {
        let bob = 3 * WelcomeMotion.pop(s - Self.lands[i])
        return photo(i)
            .rotationEffect(.degrees(Self.rests[i].r))
            .scaleEffect(Self.inScale)
            .position(x: Self.folder.x + Self.rests[i].x, y: Self.restY + bob + 22 * drain)
    }

    private func photo(_ i: Int) -> some View {
        let look = welcomeLooks[Self.looks[i]]
        return SceneSketch(top: look.top, bottom: look.bottom)
            .frame(width: Self.photoSize.width, height: Self.photoSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
    }

    // MARK: the folder

    private var folderBack: some View {
        let w = Self.folderSize.width, h = Self.folderSize.height
        return FolderBackShape()
            .fill(LinearGradient(colors: [Color(hex: 0xC27A2A), Color(hex: 0x9C5A1E)], startPoint: .top, endPoint: .bottom))
            .frame(width: w, height: h)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
            .position(Self.folder)
    }

    private var folderFront: some View {
        let w = Self.folderSize.width, h = Self.folderSize.height - Self.frontTop
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xF0B14C), Theme.accent, Color(hex: 0xD48A2C)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 3, y: -1)
            .frame(width: w, height: h)
            .position(x: Self.folder.x, y: Self.folder.y + Self.folderSize.height / 2 - h / 2)
    }

    /// The tick on the folder's front once all four are in.
    private func check(_ s: Double) -> some View {
        let u = s - Self.doneAt
        let v = u <= 0 ? 0 : 1 - exp(-9 * u) * cos(13 * u)
        let out = 1 - WelcomeMotion.phase(s, Self.clearAt, Self.clearAt + 0.25)
        return Image(systemName: "checkmark")
            .font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.onSelection.opacity(0.85))
            .scaleEffect(max(v, 0) * (0.6 + 0.4 * out))
            .opacity(u <= 0 ? 0 : out)
            .position(x: Self.folder.x, y: Self.folder.y + Self.frontTop / 2 + 4)
    }

    private func progress(_ v: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.card).frame(width: Self.barWidth, height: 5)
            Capsule().fill(Theme.accent).frame(width: max(Self.barWidth * v, v > 0.01 ? 5 : 0), height: 5)
        }
        .frame(width: Self.barWidth, height: 5)
        .position(Self.bar)
    }

    /// JPEG · 24 MP while it works, 4 saved when it is done.
    private func caption(_ s: Double) -> some View {
        let done = WelcomeMotion.phase(s, Self.doneAt, Self.doneAt + 0.3) * (1 - WelcomeMotion.phase(s, Self.clearAt, Self.clearAt + 0.3))
        return ZStack {
            // One out, then the other in: never both at once.
            Text("JPEG · 24 MP").opacity(max(1 - 2 * done, 0))
            Text(L("\(Self.count) saved")).foregroundStyle(Theme.accent).opacity(max(2 * done - 1, 0))
        }
        .font(MacMetric.font(12, .medium)).foregroundStyle(Theme.dim)
        .fixedSize()
    }
}

/// A folder's back: a rounded body with a tab on its top left.
private struct FolderBackShape: Shape {
    func path(in r: CGRect) -> Path {
        let tabW = r.width * 0.38, tabH: CGFloat = 10, rad: CGFloat = 9
        var p = Path()
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.minY + tabH, width: r.width, height: r.height - tabH),
                         cornerSize: CGSize(width: rad, height: rad), style: .continuous)
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.minY, width: tabW, height: tabH * 2.2),
                         cornerSize: CGSize(width: 6, height: 6), style: .continuous)
        return p
    }
}
