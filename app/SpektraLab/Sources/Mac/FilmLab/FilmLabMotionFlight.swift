//  FilmLabMotionFlight.swift — one photograph travelling between the kept library and the new develop page.
//
//  Geometry is in the page host's unscaled window points. The plate is one UIImageView; Core Animation moves its
//  bounds, position and sampling transform. No display tick writes observable state, asks for a decode, or keeps a
//  develop page alive. Cached pictures retain their crop recipe: stretching a cropped/edged thumbnail to `shown`
//  would match the outside rectangle and still move the photograph at the hand-off (trap 33).

import SwiftUI
import UIKit

private struct FilmLabFlightKey: EnvironmentKey { static let defaultValue: FilmLabMotionFlight? = nil }
private struct FilmLabFlightSourceKey: EnvironmentKey { static let defaultValue: FilmLabFlightSourceContext? = nil }
private struct FilmLabFlightPreviewKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var filmLabFlight: FilmLabMotionFlight? {
        get { self[FilmLabFlightKey.self] } set { self[FilmLabFlightKey.self] = newValue }
    }
    fileprivate var flightSource: FilmLabFlightSourceContext? {
        get { self[FilmLabFlightSourceKey.self] } set { self[FilmLabFlightSourceKey.self] = newValue }
    }
    fileprivate var flightPreview: Bool {
        get { self[FilmLabFlightPreviewKey.self] } set { self[FilmLabFlightPreviewKey.self] = newValue }
    }
}

enum FilmLabFlightSourceRole: Hashable { case cell, preview }
private struct FilmLabFlightSourceContext {
    let row: MacImage
    let role: FilmLabFlightSourceRole
}

/// Viewport (normalised) → this already-decoded bitmap (normalised). A second map removes a baked edge continuously
/// during the flight, without re-rendering the photo or changing its measured material/profile.
struct FilmLabFlightAsset {
    var image: UIImage
    var map = MaskMatrix.identity
    var landingMap: MaskMatrix?
    var imageToSource: MaskMatrix?
    var displaySize: CGSize?
    var identity: ObjectIdentifier { image.cgImage.map(ObjectIdentifier.init) ?? ObjectIdentifier(image) }

    @MainActor static func cached(frame: LibraryFrame, edit: FrameEdit, developed: DevelopedPicture? = nil,
                                  original: Bool = false, model: AppServices) -> FilmLabFlightAsset? {
        let made = original ? nil : (developed ?? frame.shownDevelop)
        let ref = original ? (frame.originalPicture ?? frame.picture) : (made?.picture ?? frame.picture)
        let served = !original && developed == nil && made != nil ? (Layer2Copies.shared.served(frame) ?? ref) : ref
        guard let image = ThumbnailStore.shared.cachedAny(served) else { return nil }
        let source = CGSize(width: frame.originalSize.width, height: frame.originalSize.height)
        let base = made.map { CGSize(width: $0.size.width, height: $0.size.height) } ?? source
        var asset = FilmLabFlightAsset(image: image)
        asset.imageToSource = made == nil ? .identity : model.finishedToSource(frame, edit: edit)
        if made != nil {
            if !frame.isPair, !edit.printCrop.isIdentity {
                asset.map = MaskFrame.view(finished: .identity, printCrop: edit.printCrop, finishedSize: base)
                asset.displaySize = edit.printCrop.onFinished(base).outputSize(for: base)
            }
        } else {
            let geometry = edit.pictureGeometry(source: frame.originalSize)
            // The bitmap is the whole source, while FrameView draws through its geometry.
            asset.map = MaskFrame.finished(picture: geometry, source: source)
            if !geometry.isIdentity { asset.displaySize = geometry.outputSize(for: source) }
        }
        guard asset.map.m.allSatisfy({ $0.isFinite }), asset.map.inverted.m.allSatisfy({ $0.isFinite }) else { return nil }
        return asset
    }

    /// Only for a selected, already-developed library picture. This uses the app's existing maps once, before
    /// motion starts. A missing map leaves the original bitmap intact; the normal cross-fade removes its edge.
    @MainActor mutating func withoutEdge(frame: LibraryFrame, model: AppServices) {
        guard frame.shownDevelop != nil, frame.edit.filmEdge.effective, !frame.isComposite,
              let from = model.finishedToSource(frame, edit: frame.edit) else { return }
        var bare = frame.edit
        bare.filmEdge.active = false; bare.dateBack.active = false; bare.watermarks = []
        guard let to = model.finishedToSource(frame, edit: bare) else { return }
        let size = frame.displaySizeUnder(bare.pictureGeometry(source: frame.originalSize))
        let mapped = MaskFrame.view(finished: to, printCrop: bare.printCrop,
                                   finishedSize: CGSize(width: size.width, height: size.height))
        let landing = from.inverted.after(mapped)
        if landing.m.allSatisfy({ $0.isFinite }) { landingMap = landing }
    }
}

@MainActor @Observable
final class FilmLabMotionFlight {
    enum Phase { case idle, flyingIn, landedWaitingForPicture, fading, flyingOut }
    static let space = "filmlab.motion-flight.window"
    /// MacLibraryGo has no view environment. The front host lends it a weak reference, never a retained window.
    static weak var current: FilmLabMotionFlight?
    private(set) var phase = Phase.idle
    private(set) var generation = 0
    private(set) var rowID: MacImage.ID?
    private(set) var frameID: LibraryFrame.ID?
    private(set) var libraryOpacity: Double = 1
    private(set) var inward = true
    private(set) var mounted = false
    private(set) var usesSnapshot = false
    var reduce = false
    @ObservationIgnored weak var surface: FilmLabFlightSurface?
    @ObservationIgnored private var sources: [FilmLabFlightSourceRole: Endpoint] = [:]
    @ObservationIgnored private var target: Target?
    @ObservationIgnored private var departure: Endpoint?
    @ObservationIgnored private var movingUntil: CFTimeInterval = 0
    @ObservationIgnored private var motion = 0
    @ObservationIgnored private var began: CFTimeInterval = 0
    @ObservationIgnored private var readyAt: CFTimeInterval?
    @ObservationIgnored private var lastRoute: Route?
    @ObservationIgnored private var reverseCanLand = false
    @ObservationIgnored private var returnDestination: Endpoint?
    @ObservationIgnored private var expectedInAspect: CGFloat?
    @ObservationIgnored private var inDestination: (rect: CGRect, clip: CGRect?)?

    struct Endpoint {
        var row: MacImage.ID
        var rect: CGRect
        var asset: FilmLabFlightAsset
        var epoch: Int
    }
    private struct Target {
        var id: LibraryFrame.ID
        var rect: CGRect
        var clip: CGRect?
        var asset: FilmLabFlightAsset?
        var ready: Bool
    }
    var active: Bool { phase != .idle }
    var calm: Bool { reduce || FilmLabFlightOptions.calm }
    var duration: Double { (calm ? 0.15 : 0.38) * FilmLabFlightOptions.slow }
    var fadeDuration: Double { (calm ? 0.15 : 0.12) * FilmLabFlightOptions.slow }
    var ownsTransition: Bool { active && !FilmLabFlightOptions.off }
    var hidesPicture: Bool { active && !calm && phase != .fading }

    func reportSource(_ row: MacImage, role: FilmLabFlightSourceRole, rect: CGRect, asset: FilmLabFlightAsset,
                      epoch: Int, inLibrary: Bool) {
        guard rect.flightValid, inLibrary else { return }
        let browser = MacLibraryBrowser.shared
        guard browser.selection.contains(row.id) else { return }
        if let focus = browser.focus, browser.selection.contains(focus), focus != row.id { return }
        if let surface, surface.bounds.flightValid, !surface.bounds.contains(rect) {
            if !inward, active, role == .cell, row.id == rowID { fade(reason: "cell-offscreen") }
            return
        }
        let endpoint = Endpoint(row: row.id, rect: rect, asset: asset, epoch: epoch)
        sources[role] = endpoint
        if !inward, (phase == .flyingOut || phase == .fading), role == .cell, row.id == rowID, epoch == generation {
            let previous = returnDestination
            returnDestination = endpoint
            guard reverseCanLand || previous?.rect != rect || previous?.asset.map != asset.map else { return }
            reverseCanLand = false
            phase = .flyingOut
            // The return bitmap is the canvas's, which can differ from the cell's edged/cropped preview.
            let sampling: MaskMatrix
            if let source = departure?.asset.imageToSource, let destination = asset.imageToSource {
                let mapped = source.inverted.after(destination).after(asset.map)
                sampling = mapped.m.allSatisfy({ $0.isFinite }) && mapped.inverted.m.allSatisfy({ $0.isFinite })
                    ? mapped : (departure?.asset.map ?? .identity)
            } else { sampling = departure?.asset.map ?? .identity }
            travel(to: rect, map: sampling, reverse: true, clip: rect)
        }
    }

    func forgetSource(_ row: MacImage.ID, role: FilmLabFlightSourceRole) {
        if sources[role]?.row == row { sources[role] = nil }
        if !inward, active, role == .cell, row == rowID { fade(reason: "cell-unmounted") }
    }

    /// Commit *moving* layers before any store/navigation work can build Develop. A plain async main-queue turn is
    /// enough after the explicit flush; waiting for a canvas or another layout pass here would recreate the stall.
    static func open(_ row: MacImage, model: AppServices, navigate: @escaping @MainActor () -> Void) {
        guard let flight = current, flight.prepare(row, model: model) else { navigate(); return }
        let ticket = flight.generation
        DispatchQueue.main.async { [weak flight] in
            guard let flight, flight.generation == ticket, flight.active else { return }
            FilmLabMotionFlightProbe.navigation()
            navigate()
        }
    }

    private func prepare(_ row: MacImage, model: AppServices) -> Bool {
        guard MacShellPath.develop(model.router.path) == nil else { return false }
        if MacDevelopWanted.surface == .edit || MacDevelopWanted.step == .format { if active { end() }; return false }
        if FilmLabFlightOptions.off {
            FilmLabMotionFlightProbe.baseline("in-off"); return false
        }
        guard let surface, let source = [sources[.preview], sources[.cell]].compactMap({ $0 }).first(where: { $0.row == row.id }) else {
            end(); FilmLabMotionFlightProbe.baseline("in-no-cached-source"); return false
        }
        let retarget = active && rowID == row.id
        let presentation = retarget ? surface.pictureRect : nil
        let carried = retarget ? surface.capturedAsset : nil
        let start = presentation ?? source.rect
        interrupt()
        began = CACurrentMediaTime(); readyAt = nil
        FilmLabMotionFlightProbe.begin("in", source: start, destination: nil)
        guard surface.capturePage(excluding: start) else {
            end(); FilmLabMotionFlightProbe.baseline("in-no-page-snapshot"); return false
        }
        let predicted = predictDestination(row, source: source, model: model, room: surface.bounds.size)
        expectedInAspect = predicted.picture.width / predicted.picture.height
        rowID = row.id; frameID = row.develop?.frameID
        departure = source; if let carried { departure?.asset = carried }
        inward = true; mounted = false; usesSnapshot = true
        libraryOpacity = 1; phase = .flyingIn
        CATransaction.begin()
        surface.show(carried ?? source.asset, at: start, preserveBackdrop: true)
        surface.fadeBackdrop(seconds: duration)
        travel(to: predicted.picture, map: departure?.asset.landingMap ?? departure?.asset.map ?? .identity,
               reverse: false, clip: predicted.canvas)
        CATransaction.commit()
        CATransaction.flush()
        FilmLabMotionFlightProbe.committed()
        // Making a catalog frame may await I/O. It never waits for this animation; an abandoned arm expires.
        later(1.5) { flight in if !flight.mounted { flight.end() } }
        return true
    }

    /// Seed the animation without constructing a DevelopPane. These are the existing layout owners' numbers:
    /// a fresh DevelopController shows its column; DevelopRegions reserves the info/film strip immediately. The
    /// canvas's measured rect remains authoritative and replaces this estimate with the original time remaining.
    private func predictDestination(_ row: MacImage, source: Endpoint, model: AppServices,
                                    room: CGSize) -> (picture: CGRect, canvas: CGRect) {
        let f = InterfaceScale.current(.padPoints)
        let page = CGSize(width: room.width / f, height: room.height / f)
        let column = WindowLayout.column(width: page.width, columnWidth: PaneDividers.shared.column(in: page.width))
        let strip = MacInfoStrip.height + (ShellFilmStrip.shown ? FilmStripBar.height : 0)
        let canvas = CGRect(x: column.columnWidth + 1, y: 0, width: column.picture, height: max(page.height - strip, 1))
        var aspect = source.rect.width / max(source.rect.height, 1)
        if let id = row.develop?.frameID, let frame = model.library.frame(id), !frame.isComposite {
            var bare = frame.edit
            bare.filmEdge.active = false; bare.dateBack.active = false; bare.watermarks = []
            let size = frame.displaySizeUnder(bare.pictureGeometry(source: frame.originalSize))
            let base = CGSize(width: size.width, height: size.height)
            let cut = bare.printCrop.onFinished(base).outputSize(for: base)
            aspect = max(cut.width / max(cut.height, 1), 0.0001)
        }
        let inset = (12 * 10 / 9 / InterfaceScale.padTarget).rounded()
        let area = CGSize(width: max(canvas.width - 2 * inset, 1), height: max(canvas.height - 2 * inset, 1))
        let fit = area.width / area.height > aspect
            ? CGSize(width: (area.height * aspect).rounded(), height: area.height)
            : CGSize(width: area.width, height: (area.width / aspect).rounded())
        let picture = CGRect(x: canvas.midX - fit.width / 2, y: canvas.midY - fit.height / 2, width: fit.width, height: fit.height)
        let scale = CGAffineTransform(scaleX: f, y: f)
        return (picture.applying(scale), canvas.applying(scale))
    }

    func route(_ route: Route?, model: AppServices) {
        let previous = lastRoute
        lastRoute = route
        if let route {
            guard case .develop(let id) = route else { end(); return }
            if phase == .flyingOut, frameID == id, let target {
                let rect = surface?.pictureRect
                let carried = surface?.capturedAsset
                interrupt(); phase = .flyingIn; inward = true; mounted = true
                expectedInAspect = target.rect.width / target.rect.height
                if let carried { departure?.asset = carried }
                if let rect, let departure { surface?.show(departure.asset, at: rect, preserveBackdrop: true) }
                startIn(targetID: id, target: target)
            } else if inward, active, !mounted {
                startIn(targetID: id, target: target?.id == id ? target : nil)
            } else if previous != route, active { end() }
        } else if previous != nil {
            beginOut(model: model)
        }
    }

    private func startIn(targetID: LibraryFrame.ID, target: Target?) {
        frameID = targetID; mounted = true
        surface?.revealPage()
        libraryOpacity = FilmLabFlightOptions.hold.map { 1 - FilmLabFlightOptions.eased($0) } ?? 0
        later(1.5 * FilmLabFlightOptions.slow) { $0.fade(reason: "timeout") }
        if let target { reportTarget(id: targetID, rect: target.rect, clip: target.clip, asset: target.asset, ready: target.ready) }
    }

    func reportTarget(id: LibraryFrame.ID, rect: CGRect, clip: CGRect?, asset: FilmLabFlightAsset?, ready: Bool) {
        guard rect.flightValid else { return }
        // A kept, edged preview can briefly size the new canvas. Keep the edgeless flight's destination until the
        // aspect agrees (0.2% allows the canvas's point rounding), or the ready picture confirms a different shape.
        // Filter before storing: an unaccepted rect must not later look like an already-applied ready destination.
        if active, inward, phase != .fading, frameID == nil || frameID == id, !ready,
           let expectedInAspect, abs((rect.width / rect.height) / expectedInAspect - 1) > 0.002 {
            FilmLabMotionFlightProbe.retargetSkipped(rect, expectedAspect: expectedInAspect)
            return
        }
        let old = target
        target = Target(id: id, rect: rect, clip: clip, asset: asset, ready: ready)
        guard active, inward, mounted, frameID == id, phase != .fading else { return }
        if ready, readyAt == nil { readyAt = CACurrentMediaTime(); FilmLabMotionFlightProbe.ready(after: readyAt! - began) }
        if movingUntil == 0 || old?.id != id || old?.rect != rect || old?.clip != clip || inDestination?.rect != rect || inDestination?.clip != clip {
            FilmLabMotionFlightProbe.measuredDestination(rect)
            travel(to: rect, map: departure?.asset.landingMap ?? departure?.asset.map ?? .identity, reverse: false, clip: clip)
        } else if phase == .landedWaitingForPicture, ready { fade(reason: "ready") }
    }

    private func travel(to rect: CGRect, map: MaskMatrix, reverse: Bool, clip: CGRect?) {
        motion += 1
        let ticket = motion
        let now = CACurrentMediaTime()
        let remaining: Double
        if movingUntil == 0 || FilmLabFlightOptions.hold != nil { remaining = duration }
        else if !reverse { remaining = movingUntil > now ? movingUntil - now : 0.12 * FilmLabFlightOptions.slow }
        else { remaining = max(0.06, movingUntil - now) }
        if movingUntil == 0 { movingUntil = now + duration }
        if !reverse { inDestination = (rect, clip); phase = .flyingIn }
        if calm {
            // Reduce Motion never interpolates a position, scale, sampling map or column offset.
            surface?.hidePicture()
            surface?.fade(seconds: remaining)
        } else {
            surface?.move(to: rect, map: map, clip: clip, seconds: remaining)
        }
        // Measured retargets can themselves be followed by a long render/page update. Send the replacement now;
        // pre-navigation travel is already inside prepare's explicit transaction and is flushed by that caller.
        if mounted { CATransaction.flush() }
        FilmLabMotionFlightProbe.destination(rect)
        guard FilmLabFlightOptions.hold == nil else { return }
        later(remaining) { flight in
            guard flight.motion == ticket else { return }
            flight.arrived(ticket: ticket, reverse: reverse, at: rect)
        }
    }

    private func arrived(ticket: Int, reverse: Bool, at rect: CGRect) {
        guard motion == ticket else { return }
        if !calm, let surface, FilmLabMotionFlightProbe.edgeError(surface.pictureRect, rect) > 0.25 {
            // The timer can precede the compositor's last display by one refresh. Do not snap the plate to catch up.
            later(1.0 / 60) { $0.arrived(ticket: ticket, reverse: reverse, at: rect) }
            return
        }
        if reverse { fade(reason: "returned") }
        else {
            phase = .landedWaitingForPicture
            if target?.ready == true { fade(reason: "ready") }
        }
    }

    private func beginOut(model: AppServices) {
        guard !FilmLabFlightOptions.off, let target, let asset = target.asset,
              let row = MacLibraryUI.store(model).images.first(where: { $0.develop?.frameID == target.id }) else {
            end(); FilmLabMotionFlightProbe.baseline("out-fallback"); return
        }
        let rect = active ? (surface?.pictureRect ?? target.rect) : target.rect
        let kept = active ? surface?.capturedAsset : nil
        let captured = surface?.capturePage(excluding: rect.intersection(target.clip ?? rect)) == true
        interrupt()
        rowID = row.id; frameID = target.id; inward = false; mounted = true; phase = .flyingOut
        began = CACurrentMediaTime(); reverseCanLand = true; libraryOpacity = 0; usesSnapshot = captured
        departure = Endpoint(row: row.id, rect: rect, asset: kept ?? asset, epoch: generation)
        CATransaction.begin()
        surface?.show(kept ?? asset, at: rect, clip: target.clip, preserveBackdrop: captured)
        if captured { surface?.fadeBackdrop(seconds: duration) }
        if calm { surface?.hidePicture() }
        CATransaction.commit(); CATransaction.flush()
        FilmLabMotionFlightProbe.begin("out", source: rect, destination: nil)
        let browser = MacLibraryBrowser.shared
        browser.selection = [row.id]; browser.focus = row.id
        // The hidden grid may have been removed by the existing resize policy. Let its reader mount first.
        later(0) { flight in
            var still = Transaction(); still.disablesAnimations = true
            withTransaction(still) { browser.scrollTarget = row.id }
            flight.libraryOpacity = FilmLabFlightOptions.hold.map(FilmLabFlightOptions.eased) ?? 1
            flight.surface?.revealPage()
        }
        later(0.3) { flight in if flight.reverseCanLand { flight.fade(reason: "no-cell-anchor") } }
    }

    func cancelForOtherMode(_ mode: WorkspaceMode?) {
        if let mode, mode != .develop, mode != .library, active {
            if FilmLabFlightOptions.hold != nil { end() } else { fade(reason: "other-mode") }
        }
    }

    private func fade(reason: String) {
        guard active, phase != .fading, FilmLabFlightOptions.hold == nil else { return }
        motion += 1; phase = .fading
        let ticket = motion
        surface?.fade(seconds: fadeDuration)
        later(fadeDuration) { flight in
            guard flight.motion == ticket else { return }
            FilmLabMotionFlightProbe.handoff(overlay: flight.surface?.pictureRect ?? .zero,
                canvas: flight.target?.rect, destination: flight.inward ? flight.target?.rect : flight.returnDestination?.rect,
                reason: reason)
            flight.end()
        }
    }

    private func interrupt() {
        FilmLabMotionFlightProbe.interrupted()
        generation += 1; motion += 1; movingUntil = 0; reverseCanLand = false; returnDestination = nil; expectedInAspect = nil; inDestination = nil
    }
    func end() {
        interrupt(); phase = .idle; mounted = false; rowID = nil; frameID = nil
        departure = nil; usesSnapshot = false; surface?.clear()
    }
    private func later(_ seconds: Double, _ action: @escaping @MainActor (FilmLabMotionFlight) -> Void) {
        let ticket = generation
        Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.generation == ticket else { return }
            action(self)
        }
    }
}

// MARK: - one plate, animated by the compositor; the shell never reads its presentation on a display tick

@MainActor final class FilmLabFlightSurface: UIView {
    private let imageStage = UIView()
    private let plate = UIView()
    private let bitmap = UIImageView()
    private let aperture = CAShapeLayer()
    private var asset: FilmLabFlightAsset?
    private var originRect = CGRect.zero
    private var originClip = CGRect.zero
    private var pageSnapshot: UIView?
    private var pageShield: UIView?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false; backgroundColor = .clear; clipsToBounds = true
        imageStage.isUserInteractionEnabled = false; imageStage.layer.mask = aperture
        plate.isUserInteractionEnabled = false; plate.clipsToBounds = true
        plate.layer.anchorPoint = .zero
        bitmap.contentMode = .scaleToFill; bitmap.layer.anchorPoint = .zero
        bitmap.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        bitmap.layer.position = .zero
        plate.addSubview(bitmap); imageStage.addSubview(plate); addSubview(imageStage)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageStage.frame = bounds; aperture.frame = imageStage.bounds; pageShield?.frame = bounds
        CATransaction.commit()
    }

    /// UIKit's retained snapshot view avoids a bitmap render/decode on the main thread. Crop the window into this
    /// page host (the toolbar remains live), and punch out the departing photograph so it never appears twice.
    /// The shield hides the old live page until SwiftUI can commit its replacement; the snapshot itself fades in CA.
    func capturePage(excluding photograph: CGRect) -> Bool {
        if pageSnapshot != nil { return true }
        guard let window, bounds.width > 1, bounds.height > 1 else { return false }
        let hidden = isHidden
        isHidden = true
        let captured = window.snapshotView(afterScreenUpdates: false)
        isHidden = hidden
        guard let captured else { return false }
        let shield = UIView(frame: bounds)
        shield.backgroundColor = UIColor(Theme.background); shield.isUserInteractionEnabled = false
        let page = UIView(frame: bounds)
        page.isUserInteractionEnabled = false; page.clipsToBounds = true
        captured.frame = convert(window.bounds, from: window)
        page.addSubview(captured)
        let cut = CAShapeLayer()
        cut.frame = bounds; cut.fillRule = .evenOdd
        let path = CGMutablePath(); path.addRect(bounds)
        let hole = photograph.intersection(bounds)
        if !hole.isNull { path.addRect(hole) }
        cut.path = path; page.layer.mask = cut
        insertSubview(shield, belowSubview: imageStage)
        insertSubview(page, belowSubview: imageStage)
        pageShield = shield; pageSnapshot = page
        return true
    }
    func fadeBackdrop(seconds: Double) {
        guard let pageSnapshot else { return }
        let from = (pageSnapshot.layer.presentation() ?? pageSnapshot.layer).opacity
        CATransaction.begin(); CATransaction.setDisableActions(true); pageSnapshot.layer.opacity = 0; CATransaction.commit()
        animate(pageSnapshot.layer, "opacity", from: NSNumber(value: from), to: NSNumber(value: 0), seconds: seconds)
    }
    func revealPage() { pageShield?.removeFromSuperview(); pageShield = nil }
    func hidePicture() { imageStage.isHidden = true }
    var pictureRect: CGRect {
        let p = plate.layer.presentation() ?? plate.layer
        return CGRect(origin: p.position, size: p.bounds.size)
    }
    var capturedAsset: FilmLabFlightAsset? {
        guard var asset else { return nil }
        let t = (bitmap.layer.presentation() ?? bitmap.layer).transform
        let size = pictureRect.size
        guard size.width > 0, size.height > 0 else { return asset }
        let fromBitmap = MaskMatrix([Double(t.m11 / size.width), Double(t.m21 / size.width), Double(t.m41 / size.width),
            Double(t.m12 / size.height), Double(t.m22 / size.height), Double(t.m42 / size.height),
            Double(t.m14), Double(t.m24), Double(t.m44)])
        let map = fromBitmap.inverted
        if map.m.allSatisfy({ $0.isFinite }) { asset.map = map }
        return asset
    }
    func show(_ asset: FilmLabFlightAsset, at rect: CGRect, clip: CGRect? = nil, preserveBackdrop: Bool = false) {
        clear(preserveBackdrop: preserveBackdrop); isHidden = false; imageStage.isHidden = false
        bitmap.image = asset.image; self.asset = asset
        originRect = rect; originClip = clip ?? bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        aperture.frame = bounds
        plate.layer.opacity = 1; plate.layer.position = rect.origin; plate.bounds = CGRect(origin: .zero, size: rect.size)
        bitmap.layer.transform = transform(asset.map, size: rect.size)
        aperture.path = CGPath(rect: clip ?? bounds, transform: nil)
        CATransaction.commit()
        layoutIfNeeded()
    }
    func move(to rect: CGRect, map: MaskMatrix, clip: CGRect?, seconds: Double) {
        let holding = FilmLabFlightOptions.hold != nil
        let from = holding ? originRect : pictureRect
        let fromMap = holding ? transform(asset?.map ?? .identity, size: originRect.size) : (bitmap.layer.presentation() ?? bitmap.layer).transform
        let fromClip = holding ? CGPath(rect: originClip, transform: nil) : ((aperture.presentation() as? CAShapeLayer)?.path ?? aperture.path)
        let fromOpacity = (plate.layer.presentation() ?? plate.layer).opacity
        plate.layer.removeAllAnimations(); bitmap.layer.removeAllAnimations(); aperture.removeAllAnimations()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        plate.layer.position = rect.origin; plate.bounds = CGRect(origin: .zero, size: rect.size)
        plate.layer.opacity = 1
        let toMap = transform(map, size: rect.size)
        bitmap.layer.transform = toMap
        let toClip = CGPath(rect: clip ?? bounds, transform: nil)
        aperture.path = toClip
        CATransaction.commit()
        animate(plate.layer, "position", from: NSValue(cgPoint: from.origin), to: NSValue(cgPoint: rect.origin), seconds: seconds)
        animate(plate.layer, "bounds", from: NSValue(cgRect: CGRect(origin: .zero, size: from.size)),
                to: NSValue(cgRect: CGRect(origin: .zero, size: rect.size)), seconds: seconds)
        animate(bitmap.layer, "transform", from: NSValue(caTransform3D: fromMap), to: NSValue(caTransform3D: toMap), seconds: seconds)
        if let fromClip { animate(aperture, "path", from: fromClip, to: toClip, seconds: seconds) }
        if fromOpacity < 0.999 { animate(plate.layer, "opacity", from: NSNumber(value: fromOpacity), to: NSNumber(value: 1), seconds: min(0.12, seconds)) }
    }
    func fade(seconds: Double) {
        let from = (plate.layer.presentation() ?? plate.layer).opacity
        CATransaction.begin(); CATransaction.setDisableActions(true); plate.layer.opacity = 0; CATransaction.commit()
        animate(plate.layer, "opacity", from: NSNumber(value: from), to: NSNumber(value: 0), seconds: seconds)
    }
    func clear(preserveBackdrop: Bool = false) {
        plate.layer.removeAllAnimations(); bitmap.layer.removeAllAnimations(); aperture.removeAllAnimations()
        bitmap.image = nil; asset = nil
        if !preserveBackdrop {
            pageSnapshot?.layer.removeAllAnimations(); pageSnapshot?.removeFromSuperview(); pageSnapshot = nil
            revealPage()
        }
    }
    private func animate(_ layer: CALayer, _ key: String, from: Any, to: Any, seconds: Double) {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from; a.toValue = to; a.duration = seconds
        a.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.6, 0.35, 1)
        if let hold = FilmLabFlightOptions.hold { a.speed = 0; a.timeOffset = seconds * hold }
        layer.add(a, forKey: key)
    }
    private func transform(_ map: MaskMatrix, size: CGSize) -> CATransform3D {
        let m = map.inverted.m
        var t = CATransform3DIdentity
        t.m11 = CGFloat(m[0]) * size.width; t.m21 = CGFloat(m[1]) * size.width; t.m41 = CGFloat(m[2]) * size.width
        t.m12 = CGFloat(m[3]) * size.height; t.m22 = CGFloat(m[4]) * size.height; t.m42 = CGFloat(m[5]) * size.height
        t.m14 = CGFloat(m[6]); t.m24 = CGFloat(m[7]); t.m44 = CGFloat(m[8])
        return t
    }
}

private struct FilmLabFlightPlate: UIViewRepresentable {
    let flight: FilmLabMotionFlight
    func makeUIView(context: Context) -> FilmLabFlightSurface {
        let view = FilmLabFlightSurface(frame: .zero); flight.surface = view; return view
    }
    func updateUIView(_ uiView: FilmLabFlightSurface, context: Context) {}
}

private struct FilmLabFlightHost: ViewModifier {
    let develop: Route?
    let model: AppServices
    @State private var flight = FilmLabMotionFlight()
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .environment(\.filmLabFlight, flight)
            .overlay { if !FilmLabFlightOptions.off { FilmLabFlightPlate(flight: flight).allowsHitTesting(false).accessibilityHidden(true) } }
            .coordinateSpace(name: FilmLabMotionFlight.space)
            .onAppear {
                FilmLabMotionFlight.current = flight; flight.reduce = reduce
                flight.route(develop, model: model)
                FilmLabMotionFlightProbe.startIfAsked(model: model)
            }
            .onChange(of: develop) { _, now in flight.route(now, model: model) }
            .onChange(of: reduce) { _, now in flight.reduce = now; if flight.active { flight.end() } }
            .onChange(of: MacShellBar.shared.develop?.surface) { _, now in flight.cancelForOtherMode(now) }
            .onDisappear { flight.end(); if FilmLabMotionFlight.current === flight { FilmLabMotionFlight.current = nil } }
    }
}

private struct FilmLabFlightLibrary: ViewModifier {
    let inDevelop: Bool
    let motion: Animation?
    @Environment(\.filmLabFlight) private var flight
    func body(content: Content) -> some View {
        let owns = flight?.ownsTransition == true
        let snapshot = owns && flight?.usesSnapshot == true
        let opacity = snapshot ? (inDevelop ? 0.0 : 1.0) : (owns ? (flight?.libraryOpacity ?? 1) : (inDevelop ? 0 : 1))
        if FilmLabFlightOptions.off {
            content.animation(inDevelop ? nil : motion) { $0.opacity(inDevelop ? 0 : 1) }
        } else {
            // Scope the animation to drawing. A value animation here would also animate a simultaneous scroll/resize.
            content.compositingGroup()
                .animation(snapshot ? nil : owns ? (FilmLabFlightOptions.hold == nil ? FilmLabFlightOptions.animation(seconds: flight?.duration ?? 0.38) : nil)
                           : (inDevelop ? nil : motion)) { $0.opacity(opacity) }
                .zIndex(owns && flight?.inward == true ? 2 : 0)
        }
    }
}

private struct FilmLabFlightVeil: ViewModifier {
    @Environment(\.filmLabFlight) private var flight
    func body(content: Content) -> some View { content.opacity(flight?.ownsTransition == true ? 0 : 1) }
}

private struct FilmLabFlightReading: Equatable {
    let rect: CGRect
    let image: ObjectIdentifier?
    let stamp: String?
    let generation: Int
    let inLibrary: Bool
    var clip: CGRect? = nil
}

private struct FilmLabFlightSource: ViewModifier {
    let row: MacImage
    let role: FilmLabFlightSourceRole
    let enabled: Bool
    @Environment(\.filmLabFlight) private var flight
    @Environment(\.flightPreview) private var preview
    @Environment(AppServices.self) private var model
    @Environment(AppRouter.self) private var router
    func body(content: Content) -> some View {
        let chosen = enabled && flight != nil && !FilmLabFlightOptions.off && (role != .preview || preview)
        let hidden = chosen && flight?.hidesPicture == true && flight?.rowID == row.id
        content
            .environment(\.flightSource, chosen ? FilmLabFlightSourceContext(row: row, role: role) : nil)
            .background {
                if chosen {
                    let frame = row.develop.flatMap { model.library.frame($0.frameID) }.map { MacShownFrame.of($0, model: model) }
                    let asset = frame.flatMap { FilmLabFlightAsset.cached(frame: $0, edit: $0.edit, model: model) }
                    Color.clear.onGeometryChange(for: FilmLabFlightReading.self) { geo in
                        let box = geo.frame(in: .named(FilmLabMotionFlight.space))
                        return FilmLabFlightReading(rect: asset.map { box.flightFit($0.displaySize ?? $0.image.size) } ?? box, image: asset?.identity,
                            stamp: frame?.shownDevelop?.stamp, generation: flight?.generation ?? 0,
                            inLibrary: MacShellPath.develop(router.path) == nil)
                    } action: { reading in
                        guard let flight else { return }
                        guard var asset else {
                            if frame != nil { flight.forgetSource(row.id, role: role) }
                            return
                        }
                        if let frame { asset.withoutEdge(frame: frame, model: model) }
                        flight.reportSource(row, role: role, rect: reading.rect, asset: asset,
                                            epoch: reading.generation, inLibrary: reading.inLibrary)
                    }
                    .onDisappear { flight?.forgetSource(row.id, role: role) }
                }
            }
            .animation(hidden ? nil : FilmLabFlightOptions.animation(seconds: flight?.fadeDuration ?? 0.12)) { $0.opacity(hidden ? 0 : 1) }
    }
}

private struct FilmLabFlightBitmap: ViewModifier {
    let image: UIImage?
    @Environment(\.flightSource) private var source
    @Environment(\.filmLabFlight) private var flight
    @Environment(AppRouter.self) private var router
    func body(content: Content) -> some View {
        content.background {
            if let source, let flight {
                Color.clear.onGeometryChange(for: FilmLabFlightReading.self) { geo in
                    let box = geo.frame(in: .named(FilmLabMotionFlight.space))
                    return FilmLabFlightReading(rect: image.map { box.flightFit($0.size) } ?? box,
                        image: image.map(ObjectIdentifier.init), stamp: nil, generation: flight.generation,
                        inLibrary: MacShellPath.develop(router.path) == nil)
                } action: { reading in
                    guard let image else { return }
                    flight.reportSource(source.row, role: source.role, rect: reading.rect, asset: FilmLabFlightAsset(image: image),
                                        epoch: reading.generation, inLibrary: reading.inLibrary)
                }
            }
        }
    }
}

private struct FilmLabFlightTarget: ViewModifier {
    let frame: LibraryFrame
    let edit: FrameEdit
    let developed: DevelopedPicture?
    let original: Bool
    let enabled: Bool
    let canvas: CGRect
    @Environment(\.filmLabFlight) private var flight
    @Environment(AppServices.self) private var model
    @State private var receipt: FilmLabFlightReading?
    private func picture() -> FilmLabFlightAsset? {
        var asset = FilmLabFlightAsset.cached(frame: frame, edit: edit, developed: developed, original: original, model: model)
        if !original, edit.finishedActs(isComposite: frame.isComposite), let cg = model.openSession(frame.id)?.layer2.shown {
            asset?.image = UIImage(cgImage: cg)
        }
        return asset
    }
    func body(content: Content) -> some View {
        if enabled, let flight, !FilmLabFlightOptions.off {
            let asset = picture()
            let made = developed ?? frame.shownDevelop
            let ready = !original && made != nil && asset != nil && (developed != nil || edit.filmEdge.active == frame.edit.filmEdge.active)
            let hidden = flight.hidesPicture && (flight.frameID == nil || flight.frameID == frame.id)
            content
                .onGeometryChange(for: FilmLabFlightReading.self) { geo in
                    FilmLabFlightReading(rect: geo.frame(in: .named(FilmLabMotionFlight.space)), image: asset?.identity,
                        stamp: "\(made?.stamp ?? "")|\(asset?.map.key ?? "")|\(ready)", generation: flight.generation, inLibrary: false, clip: canvas)
                } action: { reading in
                    // This is the scoped canvas identity specified by phase B, not a GPU/presentation fence.
                    receipt = reading
                    flight.reportTarget(id: frame.id, rect: reading.rect, clip: reading.clip, asset: asset, ready: false)
                }
                .task(id: receipt) {
                    guard let receipt else { return }
                    // Let the normal FramePicture task consume the in-memory image. No new decode or pipeline hook.
                    await Task.yield()
                    guard !Task.isCancelled, receipt.generation == flight.generation else { return }
                    flight.reportTarget(id: frame.id, rect: receipt.rect, clip: receipt.clip, asset: asset, ready: ready)
                }
                .animation(hidden ? nil : FilmLabFlightOptions.animation(seconds: flight.fadeDuration)) { $0.opacity(hidden ? 0 : 1) }
        } else { content }
    }
}

/// The owner adds this to PadDevelopPage's column Group, before `.padPart(.controls)`. Only drawing moves; the
/// DevelopRegions proposal is final from the first frame. Kept here so that session can add exactly one line.
private struct FilmLabFlightColumn: ViewModifier {
    @Environment(\.filmLabFlight) private var flight
    @State private var appeared = false
    func body(content: Content) -> some View {
        let arriving = flight?.ownsTransition == true && flight?.inward == true
        let amount = arriving ? (appeared ? (flight?.libraryOpacity ?? 0) : 1) : 0
        content.compositingGroup()
            .animation(FilmLabFlightOptions.hold == nil ? FilmLabFlightOptions.animation(seconds: flight?.duration ?? 0.38) : nil) {
                $0.opacity(1 - amount).offset(x: flight?.calm == true ? 0 : 28 * CGFloat(amount))
            }
            .onAppear { appeared = true }
    }
}

extension View {
    func filmLabFlightHost(develop: Route?, model: AppServices) -> some View { modifier(FilmLabFlightHost(develop: develop, model: model)) }
    func filmLabFlightLibrary(inDevelop: Bool, motion: Animation?) -> some View { modifier(FilmLabFlightLibrary(inDevelop: inDevelop, motion: motion)) }
    func filmLabFlightVeil() -> some View { modifier(FilmLabFlightVeil()) }
    func filmLabFlightPreviewSource() -> some View { environment(\.flightPreview, true) }
    func filmLabFlightSource(_ row: MacImage, role: FilmLabFlightSourceRole, enabled: Bool = true) -> some View {
        modifier(FilmLabFlightSource(row: row, role: role, enabled: enabled))
    }
    func filmLabFlightBitmap(_ image: UIImage?) -> some View { modifier(FilmLabFlightBitmap(image: image)) }
    func filmLabFlightTarget(frame: LibraryFrame, edit: FrameEdit, developed: DevelopedPicture?, original: Bool, enabled: Bool, canvas: CGRect) -> some View {
        modifier(FilmLabFlightTarget(frame: frame, edit: edit, developed: developed, original: original, enabled: enabled, canvas: canvas))
    }
    func filmLabFlightColumn() -> some View { modifier(FilmLabFlightColumn()) }
}

private extension CGRect {
    var flightValid: Bool { !isNull && !isInfinite && [minX, minY, width, height].allSatisfy { $0.isFinite } && width > 1 && height > 1 }
    func flightFit(_ size: CGSize) -> CGRect {
        let scale = min(width / max(size.width, 1), height / max(size.height, 1))
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: midX - fitted.width / 2, y: midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }
}
