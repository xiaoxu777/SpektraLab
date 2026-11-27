//  FilmLabModeTransition.swift — a mode pressed in the bar: the window shows where it is going.
//
//  The owner, 2026-11-25: "在修图的时候点击上方切换按钮的时候，我希望切换过程也可以有对应的动画". Until now 图库 · 冲洗 · 二级调色 ·
//  个性化 · 导出 swapped in the frame the press landed in. Now, in about 0.3 s on one curve:
//
//  - **The switch**: its white tab is one shape that slides to the mode pressed (`FilmLabModePill`, in `MacModeSwitch`).
//  - **The column**, between two editing modes: what the two modes do not share leaves and arrives with a short shift and
//    a fade, towards the side the switch moved — to a mode further right the new part comes from the right and the old
//    goes left (`FilmLabModeSlide`). What they share stays where it is (the histogram and 图层 between 冲洗 and 二级调色).
//  - **The picture** is not part of it: it is the same photograph, the same view, and nothing is developed for a switch.
//  - **图库 ↔ an editing mode**: the develop page comes up through a veil that fades off it (`FilmLabModeVeil`); back,
//    the library page fades in.
//
//  Nothing here keeps a timer or a queue: each piece follows the mode it is handed, so a second press in the middle of
//  the first retargets it. The animations are `.animation(_, value: mode)` on the parts themselves — `ShellContent`
//  clears the transaction's animation for the whole page (a window resize must never animate its layout), and a mode
//  does not change while the window is resized. Reduce Motion: one short fade, no movement.
//
//  A check's launch: `--filmlab-mode-slow N` (N times longer, for screenshots), `--filmlab-mode-still` (no transition:
//  the swap as it was, for a before/after), `--filmlab-mode-probe WAIT` (`FilmLabModeProbe`).

import SwiftUI
import UIKit

@MainActor
enum FilmLabModeMotion {
    static let slow: Double = max(FilmLabCheckArgs.value("--filmlab-mode-slow").flatMap(Double.init) ?? 1, 0.1)
    static let still = CommandLine.arguments.contains("--filmlab-mode-still")
    /// A check's launch draws it as under the system's Reduce Motion (`FilmLabExportStage.calmCheck`'s flag).
    static let calmCheck = CommandLine.arguments.contains("--filmlab-reduce-motion")

    /// +1 while the last switch went to a mode further right in the row, −1 to one further left. Read by the column's
    /// transition as it runs (`FilmLabModeSlide`), so the part leaving goes the way of this switch, not of the last.
    /// Main thread only (view bodies write and read it).
    static var direction: CGFloat = 1
    /// Reduce Motion as the column last saw it, for the transitions (which have no environment of their own).
    static var calm = false
    /// The mode 图库's row was asked for (`MacLibraryGo.choose`): what the switch wears for the frame between the develop
    /// page arriving and its first word to the bar, so the tab never visits 冲洗 on its way to 导出.
    static var wanted: WorkspaceMode?

    static func order(_ mode: WorkspaceMode) -> Int { WorkspaceMode.allCases.firstIndex(of: mode) ?? 0 }

    /// The one curve: quick off the mark, soft landing.
    static func animation(reduce: Bool) -> Animation? {
        if still { return nil }
        if reduce || calmCheck { return .easeOut(duration: 0.15 * slow) }
        // An ease-out that keeps moving to the end (seen slowed down: a steeper one was there in a third of the time
        // and crept for the rest).
        return .timingCurve(0.25, 0.6, 0.35, 1, duration: 0.3 * slow)
    }

    /// The switch's tab: it slides; under Reduce Motion it is simply there.
    static func pill(reduce: Bool) -> Animation? {
        reduce || calmCheck ? nil : animation(reduce: false)
    }
}

// MARK: - the switch

/// The selected tab of `MacModeSwitch`, one shape for the whole row: laid behind the titles, as wide as one of them,
/// at the chosen one's place. The row's titles are equal shares of its width, so the place is the index's.
struct FilmLabModePill: View {
    let count: Int
    /// Nil where the mode in front is not in the row.
    let index: Int?
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        GeometryReader { room in
            // The row is padded 1 pt at each end, and each title 1 pt at each side (`MacModeSwitch`).
            let share = (room.size.width - 2) / CGFloat(max(count, 1))
            if let index {
                RoundedRectangle(cornerRadius: MacMetric.pt(6), style: .continuous).fill(Theme.selection)
                    .frame(width: max(share - 2, 0), height: MacMetric.pt(22))
                    .offset(x: 2 + share * CGFloat(index))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .animation(FilmLabModeMotion.pill(reduce: reduce), value: index)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - the column

/// A part of the develop column that belongs to one mode: it arrives from the side the switch moved towards and leaves
/// to the other, a short way, fading. The direction is read when the transition runs (`FilmLabModeMotion.direction`):
/// a transition is stored with its view, and a view that leaves would otherwise go the way the *last* switch went.
struct FilmLabModeSlide: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        let leaving = phase == .didDisappear
        let reach: CGFloat = FilmLabModeMotion.calm ? 0 : 28
        content.modifier(FilmLabModeSlideEffect(gone: phase.isIdentity ? 0 : 1, leaving: leaving,
                                               shift: (leaving ? -1 : 1) * FilmLabModeMotion.direction * reach,
                                               plain: FilmLabModeMotion.calm))
    }
}

/// The slide's drawing, by how far gone the part is (0 in place … 1 gone). The part leaving is clear a little past half
/// way and the part arriving starts a little in, so the two never sit over each other at full strength.
private struct FilmLabModeSlideEffect: ViewModifier, Animatable {
    var gone: CGFloat
    let leaving: Bool
    let shift: CGFloat
    let plain: Bool

    var animatableData: CGFloat {
        get { gone }
        set { gone = newValue }
    }

    func body(content: Content) -> some View {
        let shown: CGFloat = plain ? 1 - gone
            : leaving ? 1 - gone / 0.6
            : (1 - gone - 0.15) / 0.85
        // As one group: faded leaf by leaf, 冲洗's film grid (some hundred pictures and labels) cost the main thread
        // 25–40 ms a frame on the way out (measured 2026-11-26, `FilmLabModeProbe`); a group is one layer to move.
        content
            .compositingGroup()
            .opacity(min(max(shown, 0), 1))
            .offset(x: shift * gone)
    }
}

/// The develop column's own motion for a change of mode: says which way the switch went, animates what changes in the
/// column with that change and with nothing else, and keeps the parts on the move inside the column.
private struct FilmLabModeColumn: ViewModifier {
    let mode: WorkspaceMode
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// The mode last drawn, in a box nothing observes (written in the body).
    @State private var seen = Seen()
    private final class Seen { var mode: WorkspaceMode?; let born = Date() }

    func body(content: Content) -> some View {
        let _ = note()
        // A page opened from 图库 on 导出 or 个性化 is made on 冲洗 and told its mode a moment later (`applyOpening`): that
        // first change is the page arriving, not a switch, and is not animated (it is under the veil as it is).
        let arriving = seen.born.timeIntervalSinceNow > -0.5
        content
            .animation(arriving ? nil : FilmLabModeMotion.animation(reduce: reduce), value: mode)
            .clipped()
    }

    private func note() {
        FilmLabModeMotion.calm = reduce || FilmLabModeMotion.calmCheck
        if let last = seen.mode, last != mode {
            FilmLabModeMotion.direction = FilmLabModeMotion.order(mode) > FilmLabModeMotion.order(last) ? 1 : -1
        }
        seen.mode = mode
    }
}

extension View {
    /// On the develop column: its parts move for a change of `mode` (`FilmLabModeColumn`).
    func filmLabModeColumn(_ mode: WorkspaceMode) -> some View { modifier(FilmLabModeColumn(mode: mode)) }
    /// On a part of the column that only some modes have (`FilmLabModeSlide`).
    func filmLabModePart() -> some View { transition(FilmLabModeSlide()) }
    /// On 冲洗's panel, which takes no part: it is there, and gone, in the frame the mode changes in.
    ///
    /// The panel is the film grid and the paper grid, some hundred pictures (measured 2026-11-26, `FilmLabModeProbe`,
    /// the window walked through the modes with the transition off and on, interleaved). Kept for 0.3 s to slide out,
    /// its taking down came as a second stall after the switch had settled (冲洗 → 二级调色: late frames until ~560 ms
    /// after the press, against ~160 ms). Faded in, it halved the frames drawn in the half second after the press
    /// (二级调色 → 冲洗: 13 against 27). So the switch to and from 冲洗 costs what it did, and what shows the way is the
    /// tab, the histogram and 图层 where they come or go, and the other mode's panel.
    func filmLabModeHeavyPart() -> some View { transition(.identity) }
}

extension DevelopWorkspace {
    /// The page's mode as the window's switch names it (`publishShellBar` says the same to the bar).
    var filmLabMode: WorkspaceMode {
        navigation.surface == .edit ? .edit : personalizing ? .personalize : finishing ? .export : .develop
    }
}

// MARK: - 图库 ↔ an editing mode

/// The develop page arriving over the library page: a thin veil the colour of the window lies on it and fades away, so
/// the page comes up from dim to full. Going back, the develop page is gone at once and the library
/// fades in (`ShellContent`).
///
/// A veil and not the page's own opacity (measured 2026-11-26, `FilmLabModeProbe`): fading the page itself is a fade of
/// each of its hundreds of pieces at every frame, on top of the page being made (图库 → 导出: the main thread busy for
/// ~600 ms against ~370 ms); and a page kept for 0.3 s to fade *out* was taken down in a second stall after the switch
/// had settled (冲洗 → 图库: late frames until ~575 ms against ~140 ms). The veil is one layer, and it starts to fade
/// when the page is there to be seen, not when the press landed.
struct FilmLabModeVeil: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var lifted = false
    /// How dark the veil starts. Not opaque: the page is made in one long step and the main thread is often busy again
    /// straight after its first frame (the develop opening), and an opaque veil stood there as a black window for that
    /// time (seen 2026-11-26 in a run of fast switches). At this depth the page is there to be read at once, dimmed, and
    /// comes up to full.
    private static let depth = 0.45
    /// Faded and taken away: nothing is left over the picture.
    @State private var gone = false

    var body: some View {
        if !gone {
            Theme.background
                .opacity(lifted ? 0 : Self.depth)
                // Here, under `ShellContent`'s cleared transaction.
                .animation(FilmLabModeMotion.animation(reduce: reduce), value: lifted)
                .onAppear { lifted = true }
                .task {
                    try? await Task.sleep(for: .milliseconds(Int(600 * FilmLabModeMotion.slow)))
                    gone = true
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - a check's launch

/// `--filmlab-mode-probe WAIT [--filmlab-mode-walk a,b,c] [--filmlab-mode-gap S]`: after WAIT seconds the modes are
/// walked by the bar's own paths (the develop page's `chooseSurface`, `router.toLibrary`, `MacLibraryGo.choose`), one
/// every S seconds (1.2), and for each switch the gaps between display frames in the 0.6 s after it are written to
/// `~/Library/Logs/FilmLab-mode.txt`: the longest (the main thread busy with the switch), when the last late frame
/// ended ("busy until"), and how many frames came. The walk's names are the modes' (`library`, `develop`, `edit`,
/// `personalize`, `export`); the default goes through every neighbour and a few jumps. Nothing in the library or the
/// settings is changed: a mode is not kept.
@MainActor
final class FilmLabModeProbe: NSObject {
    private static var running: FilmLabModeProbe?

    static func startIfAsked(model: AppServices) {
        guard running == nil, let wait = FilmLabCheckArgs.value("--filmlab-mode-probe").flatMap(Double.init) else { return }
        let probe = FilmLabModeProbe(model: model)
        running = probe
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { probe.start() }
    }

    private let model: AppServices
    private var steps: [WorkspaceMode]
    private let gap: Double
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var began: CFTimeInterval = 0
    private var gaps: [(at: Double, gap: Double)] = []
    private var from = "?"
    private var lines: [String] = []

    private init(model: AppServices) {
        self.model = model
        let names = FilmLabCheckArgs.value("--filmlab-mode-walk")?.split(separator: ",").map(String.init)
            ?? ["develop", "edit", "personalize", "export", "personalize", "edit", "develop", "export", "develop",
                "library", "develop", "library", "export", "library"]
        steps = names.compactMap { WorkspaceMode(rawValue: $0) }.filter { WorkspaceMode.shown.contains($0) }
        gap = FilmLabCheckArgs.value("--filmlab-mode-gap").flatMap(Double.init) ?? 1.2
    }

    private var current: WorkspaceMode {
        MacShellPath.develop(model.router.path) == nil ? .library : (MacShellBar.shared.develop?.surface ?? .develop)
    }

    private func start() {
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        last = CACurrentMediaTime()
        next()
    }

    private func next() {
        guard !steps.isEmpty else { finish(); return }
        let mode = steps.removeFirst()
        from = current.rawValue + "→" + mode.rawValue
        gaps = []
        began = CACurrentMediaTime()
        Self.go(mode, model: model)
        NSLog("[filmlab-mode] %@", from)
        // A gap under 0.6 s is a hand pressing fast: the next switch lands inside this one's transition.
        DispatchQueue.main.asyncAfter(deadline: .now() + min(gap, 0.6)) { [self] in
            record()
            DispatchQueue.main.asyncAfter(deadline: .now() + max(gap - 0.6, 0)) { [self] in next() }
        }
    }

    /// A mode, as the bar's switch and ⌘1–⌘5 ask for it (`MainWindowLayout.modeSwitch`).
    static func go(_ mode: WorkspaceMode, model: AppServices) {
        let browser = MacLibraryBrowser.shared
        if MacShellPath.develop(model.router.path) != nil, let dev = MacShellBar.shared.develop {
            if mode == .library { model.router.toLibrary() } else { browser.fullGrid = false; dev.chooseSurface(mode) }
        } else if mode != .library {
            browser.fullGrid = false
            MacLibraryGo.choose(mode, rows: MacLibraryUI.store(model).images, model: model)
        }
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        gaps.append((at: (now - began) * 1000, gap: (now - last) * 1000))
        last = now
    }

    private func record() {
        // The first tick's gap began before the switch: it is counted from the switch.
        let seen = gaps.filter { $0.at > 0 }.map { (at: $0.at, gap: min($0.gap, $0.at)) }
        let longest = seen.map(\.gap).max() ?? 0
        let busyUntil = seen.last(where: { $0.gap > 25 })?.at ?? seen.first?.at ?? 0
        lines.append(String(format: "  %@  frames %d  first %.0f ms  longest gap %.0f ms  busy until %.0f ms  late(>25ms) %d",
                            from.padding(toLength: 22, withPad: " ", startingAt: 0), seen.count, seen.first?.at ?? 0, longest,
                            busyUntil, seen.filter { $0.gap > 25 }.count))
    }

    private func finish() {
        link?.invalidate(); link = nil
        let head = "\(ISO8601DateFormatter().string(from: Date()))  args \(CommandLine.arguments.dropFirst().joined(separator: " "))\n"
        let text = head + lines.joined(separator: "\n") + "\n"
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/FilmLab-mode.txt")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
        Self.running = nil
    }
}
