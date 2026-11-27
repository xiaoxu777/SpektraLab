// FilmLabExportAnimation.swift — exposure, a paper print, and the stack it lands on.
// The animation is a consumer of export events, never an export scheduler. Only landing (or a deliberately skipped
// flight) changes the count. The cursor visits each terminal line once; a progress update does not scan the batch.

import SwiftUI

@MainActor
final class FilmLabExportStage {
    static let shared = FilmLabExportStage()
    nonisolated static let space = "filmlab.export.page"
    var viewer: CGRect = .zero
    var tray: CGRect = .zero
}

enum FilmLabExportMotion {
    static let slow: Double = CommandLine.arguments.contains("--filmlab-motion-slow") || CommandLine.arguments.contains("--filmlab-export-slow") ? 4 : 1
    static let lift = 0.12
    static let travel = 0.55
    static let settle = 0.32
    static func seconds(_ n: Double) -> Double { n * slow }
    static func fade(_ n: Double) -> Animation { .linear(duration: seconds(n)) }
    static func angle(_ id: Int) -> Double { [-4, 3, -1.5, 5, -2.5, 2][id % 6] }
}

@MainActor
@Observable
final class FilmLabExportShow {
    static let shared = FilmLabExportShow()

    /// Frozen at exposure: the same frame/crop and decode request survive the whole flight and the stack handoff.
    struct Source {
        let frame: LibraryFrame
        let rect: CGRect
        let viewer: CGRect
        let tray: CGRect
        let exposure: Bool
        var size: CGSize { rect.size }
        var edge: CGFloat { max(size.width, size.height) }
    }
    struct Card: Identifiable {
        enum Phase { case developing, lifting, travelling, settling, failed, stopped }
        let id: Int
        var source: Source
        var phase: Phase = .developing
        var fraction = 0.0
        var target = 0.0
        var saved = false
        let began = ContinuousClock.now
    }
    struct Print: Identifiable {
        let id: Int
        let source: Source
    }

    private(set) var cards: [Card] = []       // <= 2 flights + 1 developing/fading print
    private(set) var prints: [Print] = []     // newest five only
    private(set) var landed = 0
    private(set) var total = 0
    private(set) var fraction = 0.0
    private(set) var running = false
    private(set) var ready = false
    private(set) var stopped = false
    private(set) var problems: [MacExportRun.Line] = []
    private(set) var folder: URL?
    private(set) var demo = false
    var calm = false
    var hasRun: Bool { total > 0 }
    var identity: UUID { generation }

    @ObservationIgnored private var cursor = 0
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var completion: Task<Void, Never>?
    @ObservationIgnored private var ending = false
    @ObservationIgnored private var stopSeen = false

    func begin(total: Int, folder: URL?, demo: Bool = false) {
        reset()
        self.total = total; self.folder = folder; self.demo = demo
        running = true
    }

    func reset() {
        completion?.cancel(); completion = nil
        generation = UUID(); cursor = 0; ending = false; stopSeen = false
        cards = []; prints = []; landed = 0; total = 0; fraction = 0
        running = false; ready = false; stopped = false; problems = []; folder = nil; demo = false
    }

    /// MacExportRun is sequential. Process the changed head and any terminal lines passed between observations;
    /// already-consumed lines never participate in another progress tick. Demo feeds this same accept() boundary.
    func follow(_ run: MacExportRun, source: (LibraryFrame.ID) -> Source?) {
        guard !demo else { return }
        guard !run.lines.isEmpty else { if hasRun { reset() }; return }
        if !hasRun || (!running && run.isRunning) { begin(total: run.lines.count, folder: run.folder) }
        if run.stopping && !stopSeen { requestStop() }
        while cursor < run.lines.count {
            let line = run.lines[cursor]
            accept(line, source: line.frameID.flatMap(source))
            guard line.isEnded else { break }
            cursor += 1
        }
        if !run.isRunning { finish() }
    }

    func accept(_ line: MacExportRun.Line, source: Source?) {
        let index = cards.firstIndex { $0.id == line.id }
        if line.isEnded { fraction = min(1, Double(line.id + 1) / Double(max(total, 1))) }
        switch line.state {
        case .waiting: break
        case .running(let p):
            fraction = min(1, (Double(line.id) + p.fraction) / Double(max(total, 1)))
            guard !stopSeen, !calm, let source else { return }
            if let index { cards[index].target = min(1, max(0, p.fraction)) }
            else {
                guard !cards.contains(where: { $0.saved && $0.phase == .developing }) else { return }
                // A disappearing failure is expendable when the next exposure needs its one slot.
                cards.removeAll { $0.phase == .failed || $0.phase == .stopped }
                expose(line.id, source: source, target: p.fraction)
            }
        case .saved:
            fraction = min(1, Double(line.id + 1) / Double(max(total, 1)))
            let paper: Source?
            if let index {
                let frozen = cards[index].source
                let updated = Source(frame: frozen.frame, rect: frozen.rect, viewer: frozen.viewer,
                                     tray: source?.tray ?? frozen.tray, exposure: frozen.exposure)
                cards[index].source = updated
                paper = updated
            } else { paper = source }
            // The first exposure can precede the foot's first layout. Capture its landing endpoint at save,
            // while keeping the exposure's pixels, size and decode request intact.
            // Saved prints waiting for their exposure beat reserve a flight slot too. A fast batch cannot leave
            // a queue of white cards on screen while the two visible prints finish their minimum exposure.
            let flights = cards.filter { $0.saved }.count
            let developing = cards.contains { $0.id != line.id && $0.saved && $0.phase == .developing }
            guard !calm, !stopSeen, !developing, flights < 2, let source = paper, source.tray.width > 1 else {
                cards.removeAll { $0.id == line.id }
                land(line.id, source: paper)
                return
            }
            if index == nil { expose(line.id, source: source, target: 1) }
            if let i = cards.firstIndex(where: { $0.id == line.id }) { cards[i].saved = true; cards[i].target = 1 }
        case .failed, .leftOut:
            problems.append(line)
            if index != nil { change(line.id, to: .failed); removeLater(line.id, after: 0.35) }
        case .stopped:
            stopped = true
            if index != nil { change(line.id, to: .stopped); removeLater(line.id, after: 0.2) }
        }
    }

    func requestStop() {
        stopSeen = true; stopped = true
        for card in cards {
            change(card.id, to: .stopped)
            removeLater(card.id, after: 0.2)
        }
    }

    func finish() {
        running = false; ending = true
        completeWhenQuiet()
    }

    private func expose(_ id: Int, source: Source, target: Double) {
        cards.append(Card(id: id, source: source, target: min(1, max(0, target))))
        let token = generation
        Task { @MainActor in
            while self.generation == token, let i = self.cards.firstIndex(where: { $0.id == id }),
                  self.cards[i].phase == .developing {
                let card = self.cards[i]
                // Leave the bottom of the completed sweep visible for one display tick before lifting.
                if card.saved && card.fraction >= 1 { self.lift(id); return }
                let elapsed = card.began.duration(to: .now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                let minimum = FilmLabExportMotion.seconds(card.source.exposure ? 0.7 : 0.5)
                let shown = min(card.target, max(0, seconds / minimum))
                if shown != card.fraction { self.cards[i].fraction = shown }
                try? await Task.sleep(for: .seconds(1.0 / 60))
            }
        }
    }

    private func lift(_ id: Int) {
        guard let card = cards.first(where: { $0.id == id }), card.phase == .developing, card.saved else { return }
        let source = card.source
        change(id, to: .lifting)
        later(FilmLabExportMotion.lift) { self.change(id, to: .travelling) }
        later(FilmLabExportMotion.lift + FilmLabExportMotion.travel) { self.change(id, to: .settling) }
        later(FilmLabExportMotion.lift + FilmLabExportMotion.travel + FilmLabExportMotion.settle) {
            guard self.cards.contains(where: { $0.id == id && $0.phase == .settling }) else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                self.cards.removeAll { $0.id == id }
                self.land(id, source: source)
            }
            self.completeWhenQuiet()
        }
    }

    private func land(_ id: Int, source: Source?) {
        landed += 1
        if let source {
            prints.append(Print(id: id, source: source))
            if prints.count > 5 { prints.removeFirst(prints.count - 5) }
        }
    }
    private func change(_ id: Int, to phase: Card.Phase) {
        guard let i = cards.firstIndex(where: { $0.id == id }), cards[i].phase != .stopped else { return }
        cards[i].phase = phase
        if phase == .lifting { cards[i].fraction = 1 }
    }
    private func removeLater(_ id: Int, after delay: Double) {
        later(delay) { self.cards.removeAll { $0.id == id }; self.completeWhenQuiet() }
    }
    private func later(_ delay: Double, _ body: @escaping @MainActor () -> Void) {
        let token = generation
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(FilmLabExportMotion.seconds(delay)))
            guard self.generation == token, !Task.isCancelled else { return }
            body()
        }
    }
    private func completeWhenQuiet() {
        guard ending, cards.isEmpty, !ready, completion == nil else { return }
        let token = generation
        completion = Task { @MainActor in
            try? await Task.sleep(for: .seconds(FilmLabExportMotion.seconds(0.15)))
            guard !Task.isCancelled, self.generation == token else { return }
            self.ready = true
        }
    }
}

/// Uses the existing page overlay and named viewer/tray rectangles; never intercepts a click.
struct FilmLabExportFlight: View {
    let current: LibraryFrame.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(FrameCatalog.self) private var library
    @Environment(AppServices.self) private var model
    static let calmCheck = CommandLine.arguments.contains("--filmlab-reduce-motion")
    private var show: FilmLabExportShow { .shared }
    private var run: MacExportRun { .shared }
    private var calm: Bool { reduceMotion || Self.calmCheck }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .onChange(of: run.lines, initial: true) { _, _ in follow() }
                .onChange(of: run.isRunning) { _, _ in follow() }
                .onChange(of: run.stopping) { _, _ in follow() }
                .onChange(of: calm, initial: true) { _, value in show.calm = value }
                .onAppear { FilmLabExportCheck.source = source }
                .onChange(of: current) { _, _ in FilmLabExportCheck.source = source }
            ForEach(show.cards) { card in FilmLabExportPaper(card: card, calm: calm).id(show.identity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func follow() { show.calm = calm; show.follow(run, source: source) }

    private func source(_ id: LibraryFrame.ID) -> FilmLabExportShow.Source? {
        guard let kept = library.frame(id) else { return nil }
        let frame = MacShownFrame.of(kept, model: model)
        let stage = FilmLabExportStage.shared
        let viewer = stage.viewer
        let aspect = MacShownFrame.aspect(frame)
        // The shown frame is taken to be at fit (zooming in during an export is rare); another frame or a purpose
        // mock-up uses paper in the developer instead.
        let exposure = id == current && !FilmLabExportPurposeUI.shared.previewing
        let rect: CGRect
        if exposure {
            let inset = (12 * 10 / 9 / InterfaceScale.padTarget).rounded()
            let area = CGSize(width: max(viewer.width - 2 * inset, 1), height: max(viewer.height - 2 * inset, 1))
            let size = area.width / area.height > aspect
                ? CGSize(width: (area.height * aspect).rounded(), height: area.height)
                : CGSize(width: area.width, height: (area.width / aspect).rounded())
            rect = CGRect(x: viewer.midX - size.width / 2, y: viewer.midY - size.height / 2, width: size.width, height: size.height)
        } else {
            let edge = max(1, min(viewer.width, viewer.height) * 0.38)
            let size = aspect >= 1 ? CGSize(width: edge, height: edge / aspect) : CGSize(width: edge * aspect, height: edge)
            rect = CGRect(x: viewer.midX - size.width / 2, y: viewer.midY - size.height / 2, width: size.width, height: size.height)
        }
        return .init(frame: frame, rect: rect, viewer: viewer, tray: stage.tray, exposure: exposure)
    }
}

/// Fixed-size thumbnail request, including on the stack: movement cannot initiate another decode.
private struct FilmLabExportPrintFace: View {
    let source: FilmLabExportShow.Source
    var imageOpacity = 1.0
    var paperOpacity = 1.0
    private var paper: Color {
        source.exposure ? Color(red: 244 / 255, green: 241 / 255, blue: 234 / 255)
                        : Color(red: 236 / 255, green: 230 / 255, blue: 218 / 255)
    }
    var body: some View {
        FrameView(frame: source.frame, pointSize: source.edge, contentMode: .fit)
            .frame(width: source.size.width, height: source.size.height)
            .opacity(imageOpacity)
            // The outer sheet is always the viewer-photo rect. Only the fixed-size image transforms inward;
            // neither the border nor its decode request can grow past the starting rectangle.
            .scaleEffect(1 - 0.08 * paperOpacity)
            .background(paper.opacity(paperOpacity))
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

/// Quadratic Bezier translation, independent of the scale's timing curve. No layout along the path.
private struct FilmLabExportArc: GeometryEffect {
    var progress: CGFloat
    let start: CGPoint
    let end: CGPoint
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = progress, u = 1 - t
        let control = CGPoint(x: start.x + (end.x - start.x) * 0.5, y: min(start.y, end.y) - 70)
        let x = u * u * start.x + 2 * u * t * control.x + t * t * end.x
        let y = u * u * start.y + 2 * u * t * control.y + t * t * end.y
        return ProjectionTransform(CGAffineTransform(translationX: x - size.width / 2, y: y - size.height / 2))
    }
}

private struct FilmLabExportPaper: View {
    let card: FilmLabExportShow.Card
    let calm: Bool
    @State private var visible = false
    @State private var lifted = false
    @State private var travel: CGFloat = 0
    @State private var settled = false
    @State private var failed = false
    @State private var vanished = false
    private var s: FilmLabExportShow.Source { card.source }
    private var flying: Bool { card.phase != .developing }
    private var p: CGFloat { CGFloat(min(1, max(0, card.fraction))) }
    private var developedOpacity: Double { 0.15 + 0.85 * sqrt(Double(p)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !s.exposure {
                Color.black.opacity(visible && !flying && !vanished ? 0.18 : 0)
                    .frame(width: s.viewer.width, height: s.viewer.height)
                    .offset(x: s.viewer.minX, y: s.viewer.minY)
                    .animation(FilmLabExportMotion.fade(0.2), value: visible && !flying && !vanished)
            }
            if s.exposure && (!flying || card.phase == .stopped) && !calm {
                exposure.opacity(vanished ? 0 : 1)
            }
            FilmLabExportPrintFace(source: s, imageOpacity: s.exposure ? 1 : developedOpacity,
                                   paperOpacity: !s.exposure || lifted ? 1 : 0)
                .overlay { Color(red: 0.5, green: 0.15, blue: 0.12).opacity(failed ? 0.3 : 0) }
                .scaleEffect(travel > 0 ? 40 / max(s.edge, 1) : 1)
                .animation(calm ? nil : .timingCurve(0.4, 0, 0.6, 1, duration: FilmLabExportMotion.seconds(0.55)), value: travel)
                .rotationEffect(.degrees(travel > 0 ? FilmLabExportMotion.angle(card.id) : 0))
                .animation(calm ? nil : .timingCurve(0.3, 0, 0.2, 1, duration: FilmLabExportMotion.seconds(0.55)), value: travel)
                .shadow(color: .black.opacity(0.3), radius: settled || (s.exposure && !lifted) ? 4 : 18, y: settled ? 2 : 8)
                .offset(y: failed ? 12 : settled ? 0 : travel > 0 ? -3 : 0)
                .animation(calm ? nil : .spring(response: FilmLabExportMotion.seconds(0.32), dampingFraction: 0.7), value: settled)
                .animation(FilmLabExportMotion.fade(0.35), value: failed)
                .opacity(vanished || (s.exposure && (!flying || card.phase == .stopped)) ? 0 : visible ? 1 : 0)
                .animation(FilmLabExportMotion.fade(failed ? 0.35 : 0.2), value: vanished)
                .animation(FilmLabExportMotion.fade(0.2), value: visible)
                .modifier(FilmLabExportArc(progress: travel,
                                          start: CGPoint(x: s.rect.midX, y: s.rect.midY),
                                          end: CGPoint(x: s.tray.midX, y: s.tray.midY)))
                .animation(calm ? nil : .timingCurve(0.3, 0, 0.2, 1, duration: FilmLabExportMotion.seconds(0.55)), value: travel)
        }
        .onAppear { visible = true; phase() }
        .onChange(of: card.phase) { _, _ in phase() }
    }

    private var exposure: some View {
        ZStack(alignment: .top) {
            Color.white.opacity(0.06)
                .scaleEffect(x: 1, y: p, anchor: .top)
            LinearGradient(colors: [Color(red: 1, green: 244 / 255, blue: 224 / 255).opacity(0.28), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 64)
                .offset(y: (s.size.height - 1.5) * p)
            Rectangle().fill(Color(red: 1, green: 244 / 255, blue: 224 / 255).opacity(0.85))
                .frame(height: 1.5)
                .offset(y: (s.size.height - 1.5) * p)
        }
        .frame(width: s.size.width, height: s.size.height, alignment: .top)
        .clipped().blendMode(.plusLighter)
        .offset(x: s.rect.minX, y: s.rect.minY)
        .animation(.linear(duration: 1.0 / 60), value: p)
        .animation(FilmLabExportMotion.fade(0.2), value: vanished)
    }

    private func phase() {
        switch card.phase {
        case .developing: break
        case .lifting:
            // Yield once for a file that completed before the first progress observation.
            withAnimation(FilmLabExportMotion.fade(0.12)) { lifted = true }
        case .travelling: travel = 1
        case .settling: settled = true
        case .failed: failed = true; vanished = true
        case .stopped: vanished = true
        }
    }
}

// MARK: - pinned foot

private struct FilmLabExportStack: View {
    private var show: FilmLabExportShow { .shared }
    var body: some View {
        ZStack {
            ForEach(show.prints) { print in
                let age = show.prints.count - 1 - (show.prints.firstIndex { $0.id == print.id } ?? 0)
                FilmLabExportPrintFace(source: print.source)
                    .scaleEffect(40 / max(print.source.edge, 1))
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .rotationEffect(.degrees(show.ready || show.calm ? 0 : FilmLabExportMotion.angle(print.id)))
                    .offset(x: show.ready || show.calm ? 0 : CGFloat(age), y: show.ready || show.calm ? 0 : -CGFloat(age))
                    .animation(show.calm ? FilmLabExportMotion.fade(0.2) : .spring(response: FilmLabExportMotion.seconds(0.4), dampingFraction: 0.85), value: show.ready)
                    // Removed stack entries disappear immediately; fading every outgoing entry would retain an
                    // unbounded number of thumbnail views in a very fast batch.
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
        .id(show.identity)
        .frame(width: 56, height: 56)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if show.ready && !show.stopped && show.problems.isEmpty {
                FilmLabExportBadge(calm: show.calm).padding(1)
            }
        }
        .animation(FilmLabExportMotion.fade(0.15), value: show.prints.map(\.id))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FilmLabExportStage.space)) } action: {
            FilmLabExportStage.shared.tray = $0
        }
    }
}

private struct FilmLabExportBadge: View {
    let calm: Bool
    @State private var visible = false
    var body: some View {
        Image(systemName: "checkmark").font(Theme.Font.ui(10, .bold)).foregroundStyle(.white)
            .frame(width: 19, height: 19).background(Theme.labelGreen, in: Circle())
            .scaleEffect(calm || visible ? 1 : 0.6).opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(calm ? FilmLabExportMotion.fade(0.2) : .spring(response: FilmLabExportMotion.seconds(0.3), dampingFraction: 0.6)) { visible = true }
            }
    }
}

struct FilmLabExportTray: View {
    private var show: FilmLabExportShow { .shared }
    var body: some View {
        HStack(spacing: 12) {
            FilmLabExportStack().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .leading) {
                    Text(show.total == 1 && show.landed == 0 ? L("Exporting print…") : "\(show.landed) / \(show.total)")
                        .font(Theme.Font.ui(17, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                        .opacity(show.ready ? 0 : 1)
                        .accessibilityHidden(show.ready)
                    if show.ready { FilmLabExportDone().transition(.opacity) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 48, alignment: .leading)
                .animation(FilmLabExportMotion.fade(0.2), value: show.ready)
                Capsule().fill(Theme.card).frame(height: 1)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.accent)
                            .scaleEffect(x: max(0, min(1, show.fraction)), y: 1, anchor: .leading)
                            .animation(FilmLabExportMotion.fade(0.15), value: show.fraction)
                    }
                    .accessibilityHidden(true)
            }
            .frame(height: 56)
        }
        .frame(height: 72)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("filmlab.export.tray")
    }
}

/// Shown only after landing + settle + 150 ms. The existing reveal action and failure summary stay here.
struct FilmLabExportDone: View {
    private var show: FilmLabExportShow { .shared }
    private var run: MacExportRun { .shared }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if show.problems.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { title.fixedSize(); reveal }
                    VStack(alignment: .leading, spacing: 4) { title; reveal }
                }
            } else {
                HStack(spacing: 4) { title; reveal }
                // The fixed result area has two lines: summary and reason. Keep all details available on hover
                // without expanding the foot or letting another reason displace the stack.
                Text(problemText).font(Theme.Font.ui(11.5)).foregroundStyle(Theme.danger)
                    .lineLimit(1).truncationMode(.middle).help(problemText)
            }
        }
        .font(Theme.Font.ui(15, .medium))
        .foregroundStyle(Theme.text)
        .task {
            guard !show.stopped, show.problems.isEmpty else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, !show.running, !run.isRunning else { return }
            withAnimation(FilmLabExportMotion.fade(0.25)) { run.reset(); show.reset() }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if show.stopped || !show.problems.isEmpty {
                withAnimation(FilmLabExportMotion.fade(0.2)) { run.reset(); show.reset() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmlab.export.done")
    }
    private var title: some View {
        Text(titleText).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
    }
    @ViewBuilder private var reveal: some View {
        if let folder = show.folder, show.landed > 0, !show.demo {
            HStack(spacing: 4) {
                Text("·").foregroundStyle(Theme.dim)
                Button { UIApplication.shared.open(folder) } label: { Text(L("Show in Finder")) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("filmlab.export.reveal")
            }
            .fixedSize()
        }
    }
    private var problemText: String {
        show.problems.map { $0.name + Fmt.dot + L(shown: $0.problem ?? "") }.joined(separator: Fmt.dot)
    }
    private var titleText: String {
        let n = show.landed, problems = show.problems.count
        let saved = n == 1 ? L("1 photo exported") : L("\(n) photos exported")
        if show.stopped { return L("Stopped") + Fmt.dot + saved }
        if problems == 0 { return saved }
        return n == 0 ? L("\(problems) not exported") : L("\(n) saved") + Fmt.dot + L("\(problems) not exported")
    }
}

// MARK: - launch checks (kept in this owned source so no project or page-host edit is needed)

@MainActor
enum FilmLabExportCheck {
    static var source: ((LibraryFrame.ID) -> FilmLabExportShow.Source?)?
    private static var started = false
    private static var launchTask: Task<Void, Never>?
    private static var task: Task<Void, Never>?

    /// Wait for the real store, make the strip's frames, then select them as command-clicks would. No export opens
    /// the viewer or changes the pipeline. The caller waits for this before resolving the footer's batch IDs.
    static func launch(model: AppServices, current: LibraryFrame.ID?, go: @escaping @MainActor ([LibraryFrame.ID]?) -> Void) {
        let args = CommandLine.arguments
        let choose = FilmLabCheckArgs.value("--filmlab-choose").flatMap(Int.init)
        let demoIndex = args.firstIndex(of: "--filmlab-export-demo")
        guard choose != nil || demoIndex != nil || FilmLabCheckArgs.value("--filmlab-export-go") != nil else { return }
        guard !started else { return }
        started = true
        // The selection can replace the footer's frame identity. Its .task must not cancel the launch halfway
        // through making frames or waiting to press Export.
        launchTask = Task { await prepare(model: model, current: current, choose: choose, demoIndex: demoIndex, go: go) }
    }

    private static func prepare(model: AppServices, current: LibraryFrame.ID?, choose: Int?, demoIndex: Int?,
                                go: @escaping @MainActor ([LibraryFrame.ID]?) -> Void) async {
        let args = CommandLine.arguments
        let store = MacLibraryUI.store(model)
        var chosenIDs: [LibraryFrame.ID]?
        while store.images.isEmpty && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
        guard !Task.isCancelled else { started = false; return }
        if let choose, choose > 0 {
            while store.hasMore && store.images.count < choose && !Task.isCancelled { await store.loadMore() }
            let rows = Array(FilmLabRollFilterState.shared.apply(store.images, library: model.library).prefix(choose))
            if let catalog = store as? CatalogSourcesStore {
                if let made = try? await catalog.frames(for: rows.map(\.id)) {
                    chosenIDs = rows.compactMap { made.frames[$0.id] }
                }
            } else {
                chosenIDs = rows.compactMap { $0.develop?.frameID }
            }
            let browser = MacLibraryBrowser.shared
            for (i, row) in rows.enumerated() { browser.click(row.id, command: i > 0, shift: false, in: rows) }
            browser.scrollTarget = rows.first?.id
        }
        // A separate turn lets the footer receive frameIDs after the selection / frame index refresh.
        await Task.yield()
        if let i = demoIndex, i + 2 < args.count, let count = Int(args[i + 1]), count > 0,
           let seconds = Double(args[i + 2]), seconds.isFinite, seconds >= 0 {
            let rows = FilmLabRollFilterState.shared.apply(store.images, library: model.library)
            var ids = rows.compactMap { $0.develop?.frameID }.filter { model.library.frame($0) != nil }
            // Demo uses existing project frames only: no adoption, preview render, sidecar or export write.
            if ids.isEmpty, let current, model.library.frame(current) != nil { ids = [current] }
            guard !ids.isEmpty else { return }
            task = Task { await demo(count: count, seconds: seconds, ids: ids, model: model) }
        } else if let wait = FilmLabCheckArgs.value("--filmlab-export-go").flatMap(Double.init),
                  wait.isFinite, wait >= 0, FilmLabCheckArgs.value("--filmlab-export-folder") != nil, !FilmLabCheckArgs.exportWent {
            FilmLabCheckArgs.exportWent = true
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            go(chosenIDs)
        }
    }

    static func stop() {
        let show = FilmLabExportShow.shared
        guard show.demo else { return }
        task?.cancel(); show.requestStop(); show.finish()
    }

    private static func demo(count: Int, seconds: Double, ids: [LibraryFrame.ID], model: AppServices) async {
        let show = FilmLabExportShow.shared
        let fail = FilmLabCheckArgs.value("--filmlab-export-demo-fail").flatMap(Int.init)
        let stopAt = FilmLabCheckArgs.value("--filmlab-export-demo-stop").flatMap(Int.init)
        while (source == nil || FilmLabExportStage.shared.viewer.width <= 40) && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard !Task.isCancelled else { return }
        show.begin(total: count, folder: nil, demo: true)
        // First layout of the stack is caused by begin(), not by the check's wall clock.
        while FilmLabExportStage.shared.tray.width <= 1 && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(25))
        }
        for index in 0..<count {
            guard !Task.isCancelled else { return }
            let id = ids[index % ids.count]
            let photo = source?(id)
            var line = MacExportRun.Line(id: index, frameID: id, name: model.library.frame(id)?.fileName ?? "", state: .waiting(""))
            let ticks = max(1, Int(ceil(seconds / 0.025)))
            for tick in 0...ticks {
                guard !Task.isCancelled else { return }
                line.state = .running(RenderProgress(stage: .save, fraction: Double(tick) / Double(ticks)))
                show.accept(line, source: photo)
                if stopAt == index + 1 && tick >= ticks / 2 { stop(); return }
                if tick < ticks { try? await Task.sleep(for: .seconds(seconds / Double(ticks))) }
            }
            line.state = fail == index + 1 ? .failed(L("Could not develop")) : .saved(URL(fileURLWithPath: "/filmlab-animation-demo/\(index).jpg"))
            show.accept(line, source: photo)
        }
        show.finish()
    }
}
