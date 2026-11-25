//  FilmLabLibraryEntrance.swift — a project opening: the bar, the sidebar and the photos arrive one after another.
//
//  The owner, 2026-11-25: "进入项目后，我希望所有的图标是那种陆续出现的，要有动画，照片也是慢慢一张张浮现". When the home page
//  goes and 图库 is under it (or the project changes while 图库 is in front), the chrome — the bar's groups, the
//  sidebar's blocks and rows, the grid's header — fades in with a few points of rise, 35 ms apart, and the photos float
//  in one by one in reading order (fade, a rise, a touch of scale), all of it over in about a second.
//
//  It plays on entering a project and at no other time: not on a selection, a scroll, a filter or a window resize.
//  Each part reads one flag (`chrome`, `photos`), true except during an entrance, and animates only that flag's change
//  to true (`.animation(on ? … : nil, value: on)`): going false is instant, under the home page's cover. A cell made
//  later — scrolled in, or the page made again after a resize (`ShellContent`) — is born with the flag true and is
//  simply there. No cell keeps a timer: a cell's delay is its index less the first index on screen (the cells that drew
//  while the flag was false said which they were), the step shrunk so the last one on screen starts within 0.7 s.
//
//  The animations are `.animation(_, value:)` on the parts themselves: `ShellContent` clears the transaction's animation
//  for everything under it, so a `withAnimation` from outside would not reach them. Reduce Motion: one short fade, no
//  stagger, no movement.

import SwiftUI

@MainActor
@Observable
final class FilmLabLibraryEntrance {
    static let shared = FilmLabLibraryEntrance()

    /// The bar, the sidebar and the grid's header are there.
    private(set) var chrome = true
    /// The photos are there.
    private(set) var photos = true

    /// The first and last cell index drawn while `photos` was false: what was on screen as the project opened.
    @ObservationIgnored private var lo: Int?
    @ObservationIgnored private var hi: Int?
    @ObservationIgnored private var base = 0
    @ObservationIgnored private var visible = 1
    @ObservationIgnored private var run = 0

    /// A check's launch (`--filmlab-entrance-slow 4`): every delay and duration this many times longer, so screenshots
    /// taken one after another catch the stagger.
    static let slow: Double = max(FilmLabCheckArgs.value("--filmlab-entrance-slow").flatMap(Double.init) ?? 1, 0.1)

    // MARK: when it plays

    /// What is watched (`watch`): the store's project, the window's path, and what was last seen of them.
    @ObservationIgnored private weak var store: (any MacLibraryData)?
    @ObservationIgnored private var router: AppRouter?
    @ObservationIgnored private var seen: (covered: Bool, source: MacSource.ID?) = (true, nil)

    /// Watches for a project opening, once for the app's life (`MacLibraryPage`, as it first appears): the home page
    /// (or the welcome over it) going, or the project changing, while 图库 is in front and nothing covers it.
    ///
    /// Watched here and not by an `.onChange` on the library page (2026-11-25, measured with a trace): under the home
    /// page `ShellContent` takes the hidden library page out and puts it back about twice a second (its resize settle
    /// answers the empty stack's own size change), so the page was often not there at the moment the home page went,
    /// and an `.onChange` on it never saw the change. The page is back in the same update the cover goes in.
    func watch(store: any MacLibraryData, router: AppRouter) {
        guard self.store == nil else { return }
        self.store = store
        self.router = router
        seen = (Self.covered, store.selectedSourceID)
        track()
    }

    private static var covered: Bool { FilmLabHome.shared.shown || FilmLabHome.shared.welcome }

    private func track() {
        guard let store else { return }
        withObservationTracking {
            _ = FilmLabHome.shared.shown
            _ = FilmLabHome.shared.welcome
            _ = store.selectedSourceID
        } onChange: { [weak self] in
            // Told before the value is set: looked at a turn later, and watched again.
            Task { @MainActor in
                self?.changed()
                self?.track()
            }
        }
    }

    private func changed() {
        guard let store, let router else { return }
        let now = (covered: Self.covered, source: store.selectedSourceID)
        let was = seen
        seen = now
        FilmLabLibraryCheck.trace("entrance watch · covered \(was.covered) → \(now.covered) · source changed \(was.source != now.source)")
        // The cover just went, or the project changed with nothing over the window; and 图库 is what is under it.
        guard !now.covered, was.covered || was.source != now.source, MacShellPath.develop(router.path) == nil else { return }
        begin {
            guard let first = store.images.first else { return false }
            return first.id.source == store.selectedSourceID
        } loading: { store.images.isEmpty && store.activity.working != nil }
    }

    /// A project is opening. `ready`: its photos are listed (asked every 50 ms; the photos arrive then, or after 1.2 s
    /// with whatever is there, so nothing ever stays hidden). `loading`: none is listed yet and the project is still
    /// being read — a large roll's first open: waited for a little longer (5 s at most), with nothing on screen to hide.
    func begin(ready: @escaping @MainActor () -> Bool, loading: @escaping @MainActor () -> Bool = { false }) {
        run += 1
        let mine = run
        lo = nil
        hi = nil
        if chrome { chrome = false }
        if photos { photos = false }
        FilmLabLibraryCheck.trace("entrance begin")
        Task { @MainActor in
            var waited = 0
            while waited < 1200 || (waited < 5000 && loading()) {
                try? await Task.sleep(for: .milliseconds(50))
                waited += 50
                guard run == mine else { return }
                // The chrome a moment in, as the home page's cover starts to go.
                if waited >= 100, !chrome { chrome = true }
                if waited >= 150, lo != nil, ready() { break }
            }
            guard run == mine else { return }
            if !chrome { chrome = true }
            base = lo ?? 0
            visible = max((hi ?? base) - base + 1, 1)
            FilmLabLibraryCheck.trace("entrance photos · first \(base) · on screen \(visible) · after \(waited) ms")
            photos = true
        }
    }

    /// A cell drawn while the photos are hidden: it is one of those on screen.
    fileprivate func note(_ index: Int) {
        lo = min(lo ?? index, index)
        hi = max(hi ?? index, index)
    }

    fileprivate func delay(cell index: Int) -> Double {
        let k = Double(max(index - base, 0))
        let step = min(0.034, 0.7 / Double(visible))
        return min(k * step, 0.75) * Self.slow
    }

    fileprivate func delay(chrome order: Int) -> Double { Double(order) * 0.035 * Self.slow }
}

/// One part's arrival (`FilmLabLibraryEntrance`).
struct FilmLabArrive: ViewModifier {
    enum Part {
        /// A piece of the chrome, by its place in the order they arrive.
        case chrome(Int)
        /// A photo of the grid, by its index among the rows.
        case cell(Int)
    }
    let part: Part
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        let entrance = FilmLabLibraryEntrance.shared
        let on = shown(entrance)
        content
            .opacity(on ? 1 : 0)
            .scaleEffect(on || reduce ? 1 : scale, anchor: .center)
            .offset(y: on || reduce ? 0 : rise)
            .animation(on ? animation(entrance) : nil, value: on)
    }

    private func shown(_ e: FilmLabLibraryEntrance) -> Bool {
        switch part {
        case .chrome: return e.chrome
        case .cell(let i):
            if !e.photos { e.note(i) }
            return e.photos
        }
    }

    private var scale: CGFloat { if case .cell = part { 0.965 } else { 1 } }
    private var rise: CGFloat { if case .cell = part { MacMetric.pt(9) } else { MacMetric.pt(5) } }

    private func animation(_ e: FilmLabLibraryEntrance) -> Animation {
        let slow = FilmLabLibraryEntrance.slow
        if reduce { return .easeOut(duration: 0.15) }
        switch part {
        case .chrome(let order): return .easeOut(duration: 0.3 * slow).delay(e.delay(chrome: order))
        case .cell(let i): return .smooth(duration: 0.42 * slow).delay(e.delay(cell: i))
        }
    }
}

extension View {
    /// A piece of the chrome that arrives `order`-th as a project opens.
    func filmLabArrive(_ order: Int) -> some View { modifier(FilmLabArrive(part: .chrome(order))) }
    /// A photo of the grid that floats in as a project opens.
    func filmLabArrive(cell index: Int) -> some View { modifier(FilmLabArrive(part: .cell(index))) }
}
