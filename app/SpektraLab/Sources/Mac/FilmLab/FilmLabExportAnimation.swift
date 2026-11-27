// FilmLabExportAnimation.swift — enlarger → flash → folder.
// Export owns the work; this consumer owns only timestamped presentation. One clock draws the stage;
// the deadline task commits landings even when the page is away. No interpolated SwiftUI stage state.

import SwiftUI
import UIKit

@MainActor
@Observable
final class FilmLabExportStage {
    static let shared = FilmLabExportStage()
    nonisolated static let space = "filmlab.export.page"
    var viewer: CGRect = .zero
    var tray: CGRect = .zero
}

enum FilmLabExportMotion {
    static let slow: Double = CommandLine.arguments.contains("--filmlab-motion-slow") || CommandLine.arguments.contains("--filmlab-export-slow") ? 4 : 1
    static func seconds(_ n: Double) -> Double { n * slow }
    static func fade(_ n: Double) -> Animation { .linear(duration: seconds(n)) }
    @MainActor static let freeze: Double? = FilmLabCheckArgs.value("--filmlab-export-freeze").flatMap(Double.init)
        .flatMap { $0.isFinite && $0 >= 0 ? $0 / 1000 / slow : nil }
}

/// One fixed-size raster for all appearances of a photo (positive, negative, easel, flight).
/// FrameView remains the crop/decorated-picture authority. Decode once off the main thread, rasterise once
/// on it; moving/resizing the stage never changes this request or starts another thumbnail task.
@MainActor
@Observable
final class FilmLabExportThumbnail {
    private(set) var image: UIImage?
    init(frame: LibraryFrame, size: CGSize) {
        let picture = Layer2Copies.shared.served(frame) ?? frame.shownDevelop?.picture ?? frame.picture
        let edge = max(size.width, size.height, 1)
        let scale = UIScreen.main.scale
        func raster() -> UIImage? {
            let renderer = ImageRenderer(content: FrameView(frame: frame, pointSize: edge, contentMode: .fit)
                .frame(width: max(size.width, 1), height: max(size.height, 1)))
            renderer.scale = scale
            return renderer.uiImage
        }
        if ThumbnailStore.shared.cachedAny(picture) != nil { image = raster() }
        else {
            Task { @MainActor [weak self] in
                // Cover a cropped source as well. FrameView uses this same cached bitmap for the final crop.
                let crop = frame.pictureGeometry.crop
                let zoom = min(4, 1 / max(min(crop.width, crop.height), 0.1))
                guard let px = PictureLoading.maxPixel(points: edge, scale: scale, zoom: zoom),
                      await PictureLoading.picture(picture, maxPixel: px) != nil else { return }
                self?.image = raster()
            }
        }
    }
}

@MainActor
@Observable
final class FilmLabExportShow {
    static let shared = FilmLabExportShow()

    struct Source {
        let frame: LibraryFrame
        let rect: CGRect
        let viewer: CGRect
        let tray: CGRect
        let exposure: Bool
        var thumbnail: FilmLabExportThumbnail?
        var size: CGSize { rect.size }
        var edge: CGFloat { max(size.width, size.height, 1) }
    }
    struct Photo: Identifiable {
        let id: Int
        var source: Source?
        var progress = 0.0
        var received: Double
        var saved: Double?
        var failed: Double?
        var exposure: Double?
        var flash: Double?
        var off: Double?
        var flight: Double?
        var landed: Double?
        var silent = false
        var k: Double { id < 3 ? 1 : id < 9 ? 0.75 : 0.55 }
    }

    private(set) var photos: [Int: Photo] = [:]
    private(set) var opening: Source?
    private(set) var activeID: Int?
    private(set) var flightID: Int?
    private(set) var previousID: Int?
    private(set) var landed = 0
    private(set) var total = 0
    private(set) var fraction = 0.0
    private(set) var running = false
    private(set) var clockFrozen = false
    private(set) var ready = false
    private(set) var stopped = false
    private(set) var problems: [MacExportRun.Line] = []
    private(set) var folder: URL?
    private(set) var demo = false
    private(set) var began = Date.now
    private(set) var stopAt: Double?
    private(set) var exitAt: Double?
    private(set) var checkAt: Double?
    private(set) var abortAt: Double?
    private(set) var bumpAt: Double?
    private(set) var readyAt: Double?
    var calm = false
    var hasRun: Bool { total > 0 }
    var identity: UUID { generation }
    func photo(_ id: Int) -> Photo? { (frozenPhotos ?? photos)[id] }
    var active: Photo? { activeID.flatMap { photo($0) } }
    var flying: Photo? { flightID.flatMap { photo($0) } }
    var previous: Photo? { previousID.flatMap { photo($0) } }
    var idle: Bool { !hasRun || ready }

    @ObservationIgnored private var frozenPhotos: [Int: Photo]?
    @ObservationIgnored private var cursor = 0
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var deadlineAt: Double?
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var stopSeen = false
    @ObservationIgnored private var finishedAt: Double?
    @ObservationIgnored private var nextAt = 0.0
    @ObservationIgnored private var lastLanding: Double?
    @ObservationIgnored private var filed: Set<Int> = []
    @ObservationIgnored private var terminals: Set<Int> = []
    @ObservationIgnored private var resolve: ((LibraryFrame.ID) -> Source?)?

    /// Design seconds; slowing the drawing never delays the exporter. Freeze affects this consumer only.
    func clock(_ date: Date = .now) -> Double {
        let t = max(0, date.timeIntervalSince(began) / FilmLabExportMotion.slow)
        return FilmLabExportMotion.freeze.map { min(t, $0) } ?? t
    }
    func begin(total: Int, folder: URL?, demo: Bool = false, at date: Date = .now) {
        reset()
        self.total = total; self.folder = folder; self.demo = demo; began = date
        running = true
    }
    func reset() {
        cancelDeadline(); watcher?.cancel(); watcher = nil
        generation = UUID(); cursor = 0; stopSeen = false; finishedAt = nil; nextAt = 0
        photos = [:]; frozenPhotos = nil; opening = nil; activeID = nil; flightID = nil; previousID = nil
        landed = 0; total = 0; fraction = 0; running = false; clockFrozen = false; ready = false; stopped = false
        problems = []; folder = nil; demo = false; stopAt = nil; exitAt = nil; checkAt = nil
        abortAt = nil; bumpAt = nil; readyAt = nil; lastLanding = nil; filed = []; terminals = []
    }

    /// The cursor sees each terminal once. Keep following while away: returning draws today's timestamps,
    /// rather than reconstructing a new fly-in from a stale view's onAppear.
    func follow(_ run: MacExportRun, source: @escaping (LibraryFrame.ID) -> Source?) {
        guard !demo else { return }
        resolve = source
        guard !run.lines.isEmpty else { if hasRun && !running { reset() }; return }
        if !hasRun {
            let date = run.lines.compactMap(\.began).min() ?? .now
            begin(total: run.lines.count, folder: run.folder, at: date)
            resolve = source
        }
        if run.stopping && !stopSeen { requestStop() }
        while cursor < run.lines.count {
            let line = run.lines[cursor]
            // Freeze source and decode dimensions once, including the currently displayed develop.
            accept(line, source: photos[line.id]?.source ?? line.frameID.flatMap(source))
            guard line.isEnded else { break }
            cursor += 1
        }
        // Only the neighbour is prepared, never the entire batch's pictures.
        if cursor + 1 < run.lines.count {
            let line = run.lines[cursor + 1]
            if photos[line.id] == nil, let s = line.frameID.flatMap(source) {
                photos[line.id] = Photo(id: line.id, source: prepared(s), received: .infinity)
            }
        }
        if !run.isRunning { finish() }
        if run.isRunning && watcher == nil {
            let token = generation
            watcher = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(25))
                    guard let self, self.generation == token, let resolver = self.resolve else { return }
                    self.follow(run, source: resolver)
                    if !run.isRunning { self.watcher = nil; return }
                }
            }
        }
    }

    func accept(_ line: MacExportRun.Line, source: Source?) {
        let event = max(0, Date.now.timeIntervalSince(began) / FilmLabExportMotion.slow)
        let t = FilmLabExportMotion.freeze.map { min(event, $0) } ?? event
        if case .waiting = line.state {
            if line.id == 0, photos[0] == nil, let source {
                photos[0] = Photo(id: 0, source: prepared(source), received: 0)
                advance(t)
            }
            return
        }
        if terminals.contains(line.id) { return }
        var photo = photos[line.id] ?? Photo(id: line.id, source: source, received: event)
        if photo.source == nil { photo.source = source }
        if let s = photo.source, s.thumbnail == nil { photo.source = prepared(s) }
        if photo.received == .infinity { photo.received = event }
        switch line.state {
        case .waiting: return
        case .running(let p):
            if FilmLabExportMotion.freeze.map({ event <= $0 }) ?? true { photo.progress = min(1, max(0, p.fraction)) }
            fraction = min(1, (Double(line.id) + p.fraction) / Double(max(total, 1)))
        case .saved:
            // Real event time is retained even while the visual clock is frozen.
            photo.saved = event
            terminals.insert(line.id)
        case .failed, .leftOut:
            photo.failed = event
            problems.append(line); terminals.insert(line.id)
        case .stopped:
            terminals.insert(line.id)
            if !stopSeen { requestStop() }
        }
        photos[line.id] = photo
        advance(t)
    }

    private func prepared(_ source: Source) -> Source {
        var s = source
        if s.thumbnail == nil { s.thumbnail = FilmLabExportThumbnail(frame: s.frame, size: s.size) }
        return s
    }

    func requestStop() {
        guard !stopSeen else { return }
        stopSeen = true; stopped = true; stopAt = max(0, Date.now.timeIntervalSince(began) / FilmLabExportMotion.slow)
        if let id = activeID, var p = photos[id] { p.off = stopAt; photos[id] = p }
        advance(clock())
    }
    func finish() {
        guard finishedAt == nil else { return }
        running = false; finishedAt = max(clock(), Date.now.timeIntervalSince(began) / FilmLabExportMotion.slow)
        if !calm, (finishedAt ?? .infinity) <= clock(), landed == 0, photos.values.allSatisfy({ $0.saved == nil }),
           photos.values.filter({ $0.received.isFinite }).allSatisfy({ ($0.failed ?? .infinity) < ($0.flash ?? .infinity) }) {
            activeID = nil; abortAt = finishedAt; exitAt = finishedAt; readyAt = (finishedAt ?? clock()) + 0.2
        }
        advance(clock())
    }

    private func file(_ id: Int, at t: Double, silent: Bool) {
        guard !filed.contains(id), var p = photos[id] else { return }
        filed.insert(id); landed += 1; p.landed = t; p.silent = silent; photos[id] = p
        lastLanding = t
        // Silent catch-up cannot turn a fast producer into a vibrating folder.
        if bumpAt.map({ t - $0 >= 0.15 }) ?? true { bumpAt = t }
    }

    /// Only event/deadline work lives here. Positions, fades and lighting are pure clock functions below.
    /// A maximum of two saved photos wait for presentation; all excess are filed without creating views.
    private func advance(_ t: Double) {
        guard hasRun, !ready, !clockFrozen else { cancelDeadline(); return }
        let freezesNow = FilmLabExportMotion.freeze.map { t >= $0 } ?? false
        if freezesNow { clockFrozen = true }
        defer { if freezesNow { frozenPhotos = photos } }
        if let id = flightID, let p = photos[id], let start = p.flight, t >= start + 0.34 * p.k {
            file(id, at: start + 0.34 * p.k, silent: false); flightID = nil
        }
        // A frame may have been removed from the library while the exporter still held its source.
        // Its saved file is real even when there is no thumbnail to fly.
        for p in photos.values where p.source == nil && (p.saved ?? .infinity) <= t && !filed.contains(p.id) {
            file(p.id, at: t, silent: true)
        }
        let saved = photos.values.filter { ($0.saved ?? .infinity) <= t && !filed.contains($0.id) }.sorted { $0.id < $1.id }
        if calm || stopSeen {
            for p in saved where p.id != flightID { file(p.id, at: t, silent: true) }
        } else if saved.count > 2 {
            // Preserve an existing flight and the exposed sheet; everything else goes straight into the folder.
            var keep = Set([activeID, flightID].compactMap { $0 })
            for p in saved.reversed() where keep.count < 2 { keep.insert(p.id) }
            for p in saved where !keep.contains(p.id) { file(p.id, at: t, silent: true) }
        }
        if stopSeen {
            if let at = stopAt, t >= at + 0.2 { activeID = nil }
        } else if calm {
            activeID = nil
        } else if abortAt == nil {
            if let id = activeID, var p = photos[id], let flash = p.flash {
                if let fail = p.failed, fail <= t {
                    p.off = fail
                    if t >= fail + 0.56 { previousID = id; activeID = nil; nextAt = fail + 0.56 }
                } else if let save = p.saved, save <= t {
                    let minimum = flash + 0.4 * p.k
                    let off = max(minimum, save > minimum ? save + 0.16 * p.k : minimum)
                    p.off = off
                    let launch = off + (total == 1 ? 0.02 : 0) * p.k
                    if t >= launch, flightID == nil {
                        p.flight = launch; flightID = id; previousID = id; activeID = nil; nextAt = off
                    }
                }
                photos[id] = p
            }
            if activeID == nil, exitAt == nil {
                let candidate = photos.values.filter {
                    $0.received <= t && $0.exposure == nil && !filed.contains($0.id)
                        && ($0.failed == nil || $0.source != nil)
                }.min { $0.id < $1.id }
                if var p = candidate, p.source != nil, t >= nextAt {
                    let first = !photos.values.contains { $0.exposure != nil }
                    let start = max(nextAt, p.received)
                    p.exposure = first ? 0 : start
                    p.flash = first ? 0.46 : start + 0.3 * p.k
                    if first { opening = p.source }
                    // A failed sheet before its flash must never light the lamp.
                    photos[p.id] = p; activeID = p.id
                }
            }
        }
        let pending = photos.values.contains { ($0.saved ?? .infinity) <= t && !filed.contains($0.id) }
        if let finish = finishedAt, finish <= t, activeID == nil, flightID == nil, !pending, exitAt == nil {
            let wholeFailure = landed == 0 && !stopped
            if calm { exitAt = t; readyAt = t + 0.15 }
            else if wholeFailure { abortAt = t; exitAt = t; readyAt = t + 0.2 }
            else {
                let last = max(lastLanding ?? t, stopAt.map { $0 + 0.2 } ?? 0)
                if !stopped && landed > 0 { checkAt = last }
                exitAt = stopped ? max(t, last) : last + (total == 1 ? 0.18 : 0.53)
                readyAt = (exitAt ?? t) + 0.45
            }
        }
        // Retain only visible neighbours/prints, plus the opening copy until the scrim has gone.
        let retained = Set([activeID, flightID, previousID, activeID.map { $0 + 1 }].compactMap { $0 })
        for id in filed where !retained.contains(id) && photos[id]?.source != nil { photos[id]?.source = nil }
        if let end = readyAt, t >= end { ready = true; opening = nil; cancelDeadline(); return }
        schedule(after: t)
    }

    private func cancelDeadline() {
        deadline?.cancel(); deadline = nil; deadlineAt = nil
    }

    private func schedule(after t: Double) {
        var times: [Double] = []
        if let freeze = FilmLabExportMotion.freeze, t < freeze { times.append(freeze) }
        if let p = flying, let a = p.flight { times.append(a + 0.34 * p.k) }
        if let p = active {
            if let f = p.failed { times.append(f + 0.56) }
            else if flightID == nil, let save = p.saved, let flash = p.flash {
                let minimum = flash + 0.4 * p.k
                times.append(max(minimum, save > minimum ? save + 0.16 * p.k : minimum) + (total == 1 ? 0.02 * p.k : 0))
            }
        }
        if let s = stopAt, activeID != nil { times.append(s + 0.2) }
        if let end = readyAt { times.append(end) }
        guard !clockFrozen, let at = times.min(),
              FilmLabExportMotion.freeze.map({ at <= $0 }) ?? true else { cancelDeadline(); return }
        // Progress does not move a saved photo's deadline. Replacing its task on every tick could
        // cancel the only wake-up, then drop it in the old 10-us near-deadline exclusion window.
        // A newly selected queued photo can already be due (especially after a failed sheet); wake
        // once to consume it, rather than filtering its past deadline away and stranding the batch.
        guard deadlineAt != at else { return }
        cancelDeadline()
        deadlineAt = at
        let token = generation
        deadline = Task { @MainActor [weak self] in
            guard let self, self.generation == token else { return }
            // Measure when this task actually starts, including any wait for the main actor.
            let remaining = FilmLabExportMotion.seconds(max(0, at - self.clock()))
            do { try await Task.sleep(for: .seconds(max(0.001, remaining))) } catch { return }
            guard !Task.isCancelled, self.generation == token, self.deadlineAt == at else { return }
            self.deadline = nil; self.deadlineAt = nil
            self.advance(self.clock())
        }
    }
}

/// Page-space host: existing launch checks and event boundary, one display clock, no click interception.
@MainActor
struct FilmLabExportFlight: View {
    let current: LibraryFrame.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(FrameCatalog.self) private var library
    @Environment(AppServices.self) private var model
    @State private var entered: Double?
    static let calmCheck = CommandLine.arguments.contains("--filmlab-reduce-motion")
    private var show: FilmLabExportShow { .shared }
    private var run: MacExportRun { .shared }
    private var visible: Bool {
        guard let navigation = model.openSession(current)?.pageNavigation else { return false }
        return navigation.surface == .develop && navigation.step == .format && FilmLabFinish.shared.page == .export
    }
    private var calm: Bool {
        let r = FilmLabExportStage.shared.viewer
        return reduceMotion || Self.calmCheck || min(r.width * 0.86 / 460, r.height * 0.86 / 340, 1.35) < 0.55
    }
    private var stageClock: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: paused)) { clock in
            let t = show.clock(clock.date)
            FilmLabExportEnlargerStage(show: show, t: t).opacity(appearance(at: t))
        }
    }
    private var paused: Bool { show.idle || !visible || show.calm || show.clockFrozen }
    private func appearance(at t: Double) -> Double {
        guard visible, !show.calm else { return 0 }
        guard let entered else { return 1 }
        return WelcomeMotion.phase(t, entered, entered + 0.2)
    }
    var body: some View {
        stageClock
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: run.lines, initial: true) { _, _ in follow() }
        .onChange(of: run.isRunning) { _, _ in follow() }
        .onChange(of: run.stopping) { _, _ in follow() }
        .onChange(of: calm, initial: true) { _, value in show.calm = value; follow() }
        .onChange(of: visible) { _, value in if value && !show.idle { entered = show.clock() } }
        .onChange(of: show.identity) { _, _ in entered = nil }
        .onAppear {
            entered = show.hasRun && show.clock() > 0.06 ? show.clock() : nil
            FilmLabExportCheck.source = source
        }
        .onChange(of: current) { _, _ in FilmLabExportCheck.source = source }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transaction { $0.animation = nil }
    }
    private func follow() { show.calm = calm; show.follow(run, source: source) }
    private func source(_ id: LibraryFrame.ID) -> FilmLabExportShow.Source? {
        guard let kept = library.frame(id) else { return nil }
        let frame = MacShownFrame.of(kept, model: model)
        let stage = FilmLabExportStage.shared
        let viewer = stage.viewer, aspect = MacShownFrame.aspect(frame)
        let exposure = id == current && !FilmLabExportPurposeUI.shared.previewing
        // Same fit rectangle as round 3. No paper inset, shadow or rounding is applied to the flying copy.
        let inset = (12 * 10 / 9 / InterfaceScale.padTarget).rounded()
        let area = CGSize(width: max(viewer.width - 2 * inset, 1), height: max(viewer.height - 2 * inset, 1))
        let size = area.width / area.height > aspect
            ? CGSize(width: (area.height * aspect).rounded(), height: area.height)
            : CGSize(width: area.width, height: (area.width / aspect).rounded())
        let rect = CGRect(x: viewer.midX - size.width / 2, y: viewer.midY - size.height / 2, width: size.width, height: size.height)
        return .init(frame: frame, rect: rect, viewer: viewer, tray: stage.tray, exposure: exposure)
    }
}

@MainActor
private struct FilmLabExportPrintFace: View {
    let source: FilmLabExportShow.Source
    var negative = 0.0
    var body: some View {
        ZStack {
            if let image = source.thumbnail?.image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                if negative > 0 {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                        .colorInvert().colorMultiply(Color(hex: 0xF2A766)).opacity(negative)
                }
            }
        }
        .frame(width: source.size.width, height: source.size.height)
    }
}

/// Copied from the help drawing under a new name; that file's private Shape stays private.
private struct FilmLabExportCone: Shape {
    let top: CGFloat, bottom: CGFloat
    func path(in r: CGRect) -> Path {
        let wide = max(top, bottom, 1), a = r.width * top / wide, b = r.width * bottom / wide
        var p = Path()
        p.move(to: CGPoint(x: r.midX - a / 2, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + a / 2, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + b / 2, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX - b / 2, y: r.maxY)); p.closeSubpath()
        return p
    }
}

/// The same two panels in the stage and the reserved foot slot. Split layers put a filing print behind
/// the front panel, never above it. Coordinates here are relative to (318, 226) of the 460 × 340 field.
@MainActor
private struct FilmLabExportFolder: View {
    enum Layer { case back, front, all }
    var count: Int
    var batch = false
    var check = 0.0
    var layer: Layer = .all
    var body: some View {
        ZStack(alignment: .topLeading) {
            if layer != .front {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xA87A42)).frame(width: 44, height: 12)
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xA87A42))
                    .frame(width: 120, height: 82).offset(y: 10)
                ForEach(0..<edges, id: \.self) { i in
                    Rectangle().fill(Color(hex: 0xF1EEE7)).frame(width: 106, height: 2)
                        .offset(x: 7, y: 24 - CGFloat(i) * 3)
                }
            }
            if layer != .back {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xD2A25F))
                    .frame(width: 120, height: 62).offset(y: 30)
                if batch && count > 0 {
                    Text("\(count)").font(MacMetric.font(20, .bold)).monospacedDigit()
                        .foregroundStyle(Color(hex: 0x5A3E1C)).position(x: 60, y: 66)
                }
                if check > 0 {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 18, height: 18).background(Theme.accent, in: Circle())
                        .scaleEffect(0.6 + 0.4 * check).opacity(check).position(x: 120, y: 0)
                }
            }
        }
        .frame(width: 120, height: 92, alignment: .topLeading)
    }
    private var edges: Int { count == 0 ? 0 : count == 1 ? 1 : count < 5 ? 2 : count < 20 ? 3 : count < 50 ? 4 : 5 }
}

/// All positions and lighting are functions of this clock and Show's stored event times.
/// Machinery is clipped to the viewer; only the final folder is allowed to cross into the foot.
@MainActor
private struct FilmLabExportEnlargerStage: View {
    let show: FilmLabExportShow
    let t: Double
    private var viewer: CGRect { FilmLabExportStage.shared.viewer }
    private var scale: CGFloat { min(viewer.width * 0.86 / 460, viewer.height * 0.86 / 340, 1.35) }
    private var origin: CGPoint { CGPoint(x: viewer.midX - 230 * scale, y: viewer.midY - 170 * scale) }
    private var entrance: Double { WelcomeMotion.ease(.out, phase(0, 0.26)) }
    private var rise: CGFloat { 10 * CGFloat(1 - entrance) }
    private var exit: Double { show.exitAt ?? .infinity }
    private var machineOpacity: Double { entrance * (1 - phase(exit, exit + 0.25)) * abortOpacity }
    private var abortOpacity: Double { show.abortAt.map { 1 - phase($0, $0 + 0.2) } ?? 1 }
    private var scrim: Double {
        0.88 * entrance * (1 - WelcomeMotion.ease(.inOut, phase(exit + 0.05, exit + 0.35))) * abortOpacity
    }
    private var p: FilmLabExportShow.Photo? { show.active }
    private var lampPhoto: FilmLabExportShow.Photo? {
        if let p, let flash = p.flash, t >= flash { return p }
        return show.previous
    }
    private var lamp: Double {
        guard let p = lampPhoto, let flash = p.flash, t >= flash,
              p.failed.map({ $0 > flash }) ?? true else { return 0 }
        let u = t - flash
        let strength = u < 0.06 ? u / 0.06 : 1 - 0.3 * WelcomeMotion.phase(u, 0.06, 0.24)
        let off = min(p.off ?? .infinity, show.stopAt ?? .infinity, p.failed ?? .infinity)
        return strength * (1 - phase(off, off + 0.08))
    }
    private var bulb: Double {
        guard let p = lampPhoto, let flash = p.flash, t >= flash,
              p.failed.map({ $0 > flash }) ?? true else { return 0 }
        let off = min(p.off ?? .infinity, show.stopAt ?? .infinity, p.failed ?? .infinity)
        return phase(flash, flash + 0.06) * (1 - phase(off, off + 0.08))
    }
    private var wash: Double {
        guard let p = lampPhoto, let flash = p.flash, t >= flash,
              p.failed.map({ $0 > flash }) ?? true, show.stopAt.map({ t < $0 }) ?? true else { return 0 }
        let u = t - flash
        return u < 0.06 ? 0.22 * u / 0.06 : 0.22 * (1 - WelcomeMotion.ease(.out, WelcomeMotion.phase(u, 0.06, 0.3)))
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            if show.hasRun && !show.ready && !show.calm && scale >= 0.55 {
                viewerDrawing
                    .frame(width: viewer.width, height: viewer.height, alignment: .topLeading)
                    .clipped().offset(x: viewer.minX, y: viewer.minY)
                if show.landed > 0 && show.abortAt == nil && t >= exit {
                    exitingFolder
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var viewerDrawing: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(scrim)
            // Completely cover the old photo under its moving copy. At t=0 the copy has exactly its fit
            // rectangle and no paper, corner radius or shadow; the original cannot show through behind it.
            if let source = firstSource, source.exposure {
                let rect = fit(source, in: viewer)
                Color.black.opacity((1 - WelcomeMotion.ease(.inOut, phase(exit + 0.05, exit + 0.35))) * abortOpacity)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX - viewer.minX, y: rect.midY - viewer.minY)
            }
            RadialGradient(colors: [Color(hex: 0xFFD9A0), .clear],
                           center: UnitPoint(x: (origin.x + 180 * scale - viewer.minX) / max(viewer.width, 1),
                                             y: (origin.y + 140 * scale - viewer.minY) / max(viewer.height, 1)),
                           startRadius: 0, endRadius: viewer.width * 0.6)
                .opacity(wash * machineOpacity)
            machine
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: origin.x - viewer.minX, y: origin.y - viewer.minY + rise * scale)
                .opacity(machineOpacity)
            if let source = firstSource, source.exposure, t < 0.4 {
                flyIn(source)
            }
        }
    }
    private var firstSource: FilmLabExportShow.Source? {
        show.opening
    }
    private var machine: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x3F4147)).frame(width: 10, height: 314).offset(x: 40, y: 14)
            Rectangle().fill(Color(hex: 0x3F4147)).frame(width: 90, height: 8).offset(x: 40, y: 22)
            RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x3F4147)).frame(width: 120, height: 40).offset(x: 120, y: 10)
            Capsule().fill(Color(hex: 0xFFE2A8)).opacity(0.25 + 0.75 * bulb)
                .frame(width: 44, height: 6)
                .shadow(color: Theme.accent.opacity(bulb), radius: 5 + 5 * WelcomeMotion.phase(t - (lampPhoto?.flash ?? t), 0, 0.06))
                .position(x: 180, y: 45)
            FilmLabExportCone(top: 36, bottom: 68).fill(beam(0.9, 0.5))
                .frame(width: 68, height: 20).position(x: 180, y: 60)
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x2B2C30))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: 0x4A4C52), lineWidth: 1))
                .frame(width: 132, height: 64).position(x: 180, y: 102)
            negatives
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x3F4147)).frame(width: 34, height: 12).offset(x: 163, y: 134)
            FilmLabExportCone(top: 34, bottom: 196).fill(beam(0.6, 0.18))
                .frame(width: 196, height: 50).position(x: 180, y: 171)
            easel
            if show.landed == 0 || t < exit {
                FilmLabExportFolder(count: show.landed, batch: show.total > 1, layer: .back)
                    .scaleEffect(folderBump).position(x: 378, y: 272)
                if let flying = show.flying { filing(flying) }
                FilmLabExportFolder(count: show.landed, batch: show.total > 1, check: check, layer: .front)
                    .scaleEffect(folderBump).position(x: 378, y: 272)
            }
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x2A2B2F)).frame(width: 430, height: 10).offset(x: 20, y: 318)
        }
        .frame(width: 460, height: 340, alignment: .topLeading)
    }
    private var check: Double {
        show.checkAt.map { WelcomeMotion.ease(.out, phase($0, $0 + 0.18)) } ?? 0
    }
    private var folderBump: Double { 1 + 0.05 * (show.bumpAt.map { WelcomeMotion.pop(t - $0) } ?? 0) }
    private func beam(_ top: Double, _ bottom: Double) -> LinearGradient {
        LinearGradient(colors: [Color(hex: 0xFFE2A8).opacity(top * lamp), Color(hex: 0xFFE2A8).opacity(bottom * lamp)],
                       startPoint: .top, endPoint: .bottom)
    }
    private var stripPhoto: FilmLabExportShow.Photo? { p ?? show.previous }
    private var negatives: some View {
        let photo = stripPhoto
        let start = photo?.exposure ?? 0
        let first = start == 0
        let advance = first ? 1 : WelcomeMotion.ease(.inOut, phase(start, start + 0.3 * (photo?.k ?? 1)))
        let stop = show.stopAt.map { phase($0, $0 + 0.2) } ?? 0
        let fade = show.total > 1 ? WelcomeMotion.phase(t, 0.2, 0.4) : 1.0
        return ZStack(alignment: .topLeading) {
            if show.total > 1 {
                Rectangle().fill(Color(hex: 0x4A2B14)).frame(width: 240, height: 64)
                ForEach(0..<20, id: \.self) { i in
                    let x = (CGFloat(i) * 12 + CGFloat(112 * advance)).truncatingRemainder(dividingBy: 240)
                    Rectangle().fill(Color(hex: 0x1C1D20)).frame(width: 3, height: 4).offset(x: x, y: 3)
                    Rectangle().fill(Color(hex: 0x1C1D20)).frame(width: 3, height: 4).offset(x: x, y: 57)
                }
            }
            if let photo {
                if let source = photo.source, !(first && source.exposure && t < 0.4) {
                    negative(source).position(x: 120 - CGFloat(112 * (1 - advance)), y: 32 + settle(first))
                }
                if show.total > 1 {
                    if !first, let source = show.previous?.source, show.previousID != photo.id {
                        negative(source).position(x: 120 + CGFloat(112 * advance), y: 32)
                    }
                    if let next = show.photo(photo.id + 1)?.source {
                        negative(next).position(x: 8 - CGFloat(112 * (1 - advance)), y: 32)
                    }
                }
            }
        }
        .frame(width: 240, height: 64, alignment: .topLeading)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.125),
                                    .init(color: .black, location: 0.875), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .opacity(fade * (1 - stop)).offset(x: 60 - 40 * stop, y: 70)
    }
    private func settle(_ first: Bool) -> CGFloat { first ? 2 * CGFloat(1 - WelcomeMotion.ease(.out, phase(0.4, 0.46))) : 0 }
    private func negative(_ source: FilmLabExportShow.Source) -> some View {
        let size = fitted(source.size, into: CGSize(width: 104, height: 56))
        return FilmLabExportPrintFace(source: source, negative: 1)
            .scaleEffect(size.width / max(source.size.width, 1))
            .frame(width: 104, height: 56).background(Color(hex: 0x4A2B14))
    }
    private var easel: some View {
        let start = p?.exposure ?? .infinity
        let first = start == 0
        let sheet = first ? 1 : phase(start + 0.14 * (p?.k ?? 1), start + 0.34 * (p?.k ?? 1))
        let stopFade = show.stopAt.map { 1 - phase($0, $0 + 0.2) } ?? 1
        let failureFade = p?.failed.map { 1 - phase($0 + 0.36, $0 + 0.56) } ?? 1
        return ZStack {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xF1EEE7))
            if let p, let source = p.source {
                let amount = developed(p)
                let size = fitted(source.size, into: CGSize(width: 184, height: 106))
                FilmLabExportPrintFace(source: source)
                    .brightness(0.35 * (1 - amount)).opacity(amount)
                    .scaleEffect(size.width / max(source.size.width, 1)).frame(width: 184, height: 106)
                if let fail = p.failed, t >= fail {
                    Color(hex: 0x77787C).opacity(0.6)
                    Image(systemName: "exclamationmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 14, height: 14).background(Theme.danger, in: Circle()).position(x: 204, y: 0)
                }
            }
        }
        .frame(width: 204, height: 122).opacity(sheet * stopFade * failureFade)
        .position(x: 180, y: 257)
    }
    private func developed(_ p: FilmLabExportShow.Photo) -> Double {
        guard let flash = p.flash, t >= flash + 0.02 * p.k else { return 0 }
        let start = flash + 0.02 * p.k
        if let save = p.saved, save <= flash + 0.4 * p.k, t >= save {
            let end = start + 0.38 * p.k
            if save <= start { return WelcomeMotion.ease(.out, phase(start, end)) }
            // A save received during development cannot retroactively change earlier frames. Meet the
            // fast beat from the value already on screen, rather than jumping to its nearly-finished curve.
            let atSave = min(0.85, max(min(p.progress, 0.85), 0.85 * (1 - exp(-max(0, save - start) / 1.2))))
            return atSave + (1 - atSave) * WelcomeMotion.ease(.out, phase(save, max(save + 0.001, end)))
        }
        let base = min(0.85, max(min(p.progress, 0.85), 0.85 * (1 - exp(-(t - start) / 1.2))))
        if let save = p.saved, t >= save {
            // Freeze the slow-develop value at save, then finish over exactly 160 ms.
            let atSave = min(0.85, max(0.85 * (1 - exp(-max(0, save - start) / 1.2)), min(p.progress, 0.85)))
            return atSave + (1 - atSave) * WelcomeMotion.ease(.out, phase(save, save + 0.16 * p.k))
        }
        return base
    }
    private func filing(_ p: FilmLabExportShow.Photo) -> some View {
        let e = WelcomeMotion.ease(.inOut, phase(p.flight ?? .infinity, (p.flight ?? .infinity) + 0.34 * p.k))
        let wave = sin(.pi * e)
        return Group {
            if let source = p.source {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xF1EEE7))
                    let size = fitted(source.size, into: CGSize(width: 184, height: 106))
                    FilmLabExportPrintFace(source: source).scaleEffect(size.width / max(source.size.width, 1))
                        .frame(width: 184, height: 106)
                }
                .frame(width: 204, height: 122).scaleEffect(WelcomeMotion.lerp(1, 96.0 / 204, e))
                .rotationEffect(.degrees(-6 * wave)).shadow(color: .black.opacity(0.4 * wave), radius: 6, y: 4 * wave)
                .position(x: WelcomeMotion.lerp(180, 378, e), y: WelcomeMotion.lerp(257, 302, e) - 30 * wave)
            }
        }
    }
    private func flyIn(_ source: FilmLabExportShow.Source) -> some View {
        let e = WelcomeMotion.ease(.inOut, phase(0, 0.4))
        let rect = fit(source, in: viewer)
        let target = fitted(source.size, into: CGSize(width: 104 * scale, height: 56 * scale))
        return FilmLabExportPrintFace(source: source, negative: phase(0.2, 0.4))
            .scaleEffect(x: WelcomeMotion.lerp(rect.width, target.width, e) / max(source.size.width, 1),
                         y: WelcomeMotion.lerp(rect.height, target.height, e) / max(source.size.height, 1))
            .position(x: WelcomeMotion.lerp(rect.midX, origin.x + 180 * scale, e) - viewer.minX,
                      y: WelcomeMotion.lerp(rect.midY, origin.y + (104 + rise) * scale, e) - viewer.minY - 24 * scale * sin(.pi * e))
    }
    private var exitingFolder: some View {
        let e = WelcomeMotion.ease(.inOut, phase(exit, exit + 0.45))
        let tray = FilmLabExportStage.shared.tray
        return FilmLabExportFolder(count: show.landed, batch: show.total > 1, check: check)
            .scaleEffect(WelcomeMotion.lerp(scale, 0.25, e) * folderBump)
            .position(x: WelcomeMotion.lerp(origin.x + 378 * scale, tray.midX, e),
                      y: WelcomeMotion.lerp(origin.y + 272 * scale, tray.midY, e) - 40 * sin(.pi * e))
    }
    private func phase(_ a: Double, _ b: Double) -> Double {
        guard a.isFinite, b.isFinite else { return 0 }
        return WelcomeMotion.phase(t, a, b)
    }
    private func fitted(_ size: CGSize, into box: CGSize) -> CGSize {
        let s = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
        return CGSize(width: size.width * s, height: size.height * s)
    }
    private func fit(_ source: FilmLabExportShow.Source, in viewer: CGRect) -> CGRect {
        if viewer == source.viewer { return source.rect }
        // The fixed decode is retained while the fit rectangle follows a resized viewer.
        let inset = (12 * 10 / 9 / InterfaceScale.padTarget).rounded()
        let size = fitted(source.size, into: CGSize(width: max(1, viewer.width - 2 * inset), height: max(1, viewer.height - 2 * inset)))
        return CGRect(x: viewer.midX - size.width / 2, y: viewer.midY - size.height / 2, width: size.width, height: size.height)
    }
}

// MARK: - pinned foot (fixed height, reserved folder slot, no progress bar)

@MainActor
struct FilmLabExportTray: View {
    private var show: FilmLabExportShow { .shared }
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if show.ready, show.landed > 0, let folder = show.folder, !show.demo {
                    Button { UIApplication.shared.open(folder) } label: { icon }
                        .buttonStyle(.plain).accessibilityLabel(L("Show in Finder"))
                } else { icon.accessibilityHidden(true) }
            }
            .frame(width: 30, height: 24)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FilmLabExportStage.space)) } action: {
                FilmLabExportStage.shared.tray = $0
            }
            ZStack(alignment: .topLeading) {
                Text(show.total == 1 ? L("Exporting print…") : "\(show.landed) / \(show.total)")
                    .font(Theme.Font.ui(15, .medium)).monospacedDigit().foregroundStyle(Theme.text)
                    .id(show.landed).transition(.opacity)
                    .opacity(show.ready ? 0 : 1).accessibilityHidden(show.ready)
                if show.ready { FilmLabExportDone().transition(.opacity) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 48, alignment: .topLeading)
            .offset(y: 14)
            // Foot cross-fades only. Stage trajectories are never SwiftUI animations.
            .animation(FilmLabExportMotion.fade(0.15), value: show.landed)
            .animation(FilmLabExportMotion.fade(0.15), value: show.ready)
        }
        .frame(height: 72)
        .accessibilityElement(children: .contain).accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("filmlab.export.tray")
    }
    private var icon: some View {
        FilmLabExportFolder(count: show.ready ? show.landed : 0, check: show.ready && !show.stopped && show.landed > 0 ? 1 : 0)
            .scaleEffect(0.25).frame(width: 30, height: 24)
            .opacity(show.ready && show.landed > 0 ? 1 : 0.35)
            .animation(FilmLabExportMotion.fade(0.15), value: show.ready)
    }
}

@MainActor
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
                // without expanding the foot or letting another reason displace the folder.
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
        let fail = (FilmLabCheckArgs.value("--filmlab-export-demo-fail") ?? FilmLabCheckArgs.value("-demo-fail")).flatMap(Int.init)
        let stopAt = (FilmLabCheckArgs.value("--filmlab-export-demo-stop") ?? FilmLabCheckArgs.value("-demo-stop")).flatMap(Int.init)
        while (source == nil || FilmLabExportStage.shared.viewer.width <= 40) && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard !Task.isCancelled else { return }
        show.begin(total: count, folder: nil, demo: true)
        // First layout of the folder slot is caused by begin(), not by the check's wall clock.
        while FilmLabExportStage.shared.tray.width <= 1 && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(25))
        }
        // SECONDS is the whole batch's render budget, including repeated library pictures. Use
        // absolute monotonic deadlines: 25-ms sleeps plus a busy main actor must not stretch every
        // photo's render (formerly N * SECONDS, with all scheduling delays added to every tick).
        let clock = ContinuousClock()
        let began = clock.now
        let perPhoto = seconds / Double(count)
        for index in 0..<count {
            guard !Task.isCancelled else { return }
            let id = ids[index % ids.count]
            let photo = source?(id)
            // The batch index identifies the event; a repeated library ID only supplies the pixels.
            var line = MacExportRun.Line(id: index, frameID: id, name: model.library.frame(id)?.fileName ?? "", state: .waiting(""))
            let start = began.advanced(by: .seconds(Double(index) * perPhoto))
            let end = began.advanced(by: .seconds(Double(index + 1) * perPhoto))
            while true {
                guard !Task.isCancelled else { return }
                let elapsed = start.duration(to: clock.now).components
                let age = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                let fraction = perPhoto > 0 ? min(1, max(0, age / perPhoto)) : 1
                line.state = .running(RenderProgress(stage: .save, fraction: fraction))
                show.accept(line, source: photo)
                if stopAt == index + 1 && fraction >= 0.5 { stop(); return }
                if fraction >= 1 { break }
                let wake = min(end, clock.now.advanced(by: .milliseconds(25)))
                do { try await clock.sleep(until: wake) } catch { return }
            }
            line.state = fail == index + 1 ? .failed(L("Could not develop")) : .saved(URL(fileURLWithPath: "/filmlab-animation-demo/\(index).jpg"))
            show.accept(line, source: photo)
            await Task.yield()
        }
        show.finish()
    }
}
