// 图库 → 冲洗 only. SwiftUI reports bounds; ONE external UIView draws opaque section veils. Their CA animations
// survive a blocked main thread. No snapshots, platform views in the stock drawing, or explicit transaction flush.
import SwiftUI
import UIKit

@MainActor
enum FilmLabColumnEntrance {
    static let off = CommandLine.arguments.contains("--filmlab-column-entrance-off")
    static let slow: Double = {
        let n = FilmLabCheckArgs.value("--filmlab-column-entrance-slow").flatMap(Double.init) ?? 1
        return n.isFinite ? max(0.1, n) : 1
    }()
    static var pending: Ticket?
    static var ownsPageVeil = false
    @MainActor final class Ticket {
        let press = FilmLabModeProbe.columnPress ?? CACurrentMediaTime()
        let frame: LibraryFrame.ID?
        var appeared: CFTimeInterval?
        var finished = false
        weak var view: FilmLabColumnVeils?
        init(frame: LibraryFrame.ID?) { self.frame = frame }
        func log(_ text: String) { FilmLabColumnProbe.entrance(text, press: press) }
    }
    /// Before flight preparation (also before its cache-miss exit); launch/develop and photo switches never arm it.
    static func arm(frame: LibraryFrame.ID?, inLibrary: Bool) {
        pending = nil; ownsPageVeil = false
        guard !off, inLibrary else { return }
        pending = Ticket(frame: frame)
    }
    @MainActor final class Visit {
        private var checked = false
        private var ticket: Ticket?
        private var frame: LibraryFrame.ID?
        func take(frame: LibraryFrame.ID, mode: WorkspaceMode) -> Ticket? {
            if !checked {
                checked = true; self.frame = frame
                if let asked = pending, asked.frame == nil || asked.frame == frame {
                    pending = nil
                    if mode == .develop { ticket = asked; ownsPageVeil = true }
                }
            }
            return self.frame == frame && mode == .develop && ticket?.finished == false ? ticket : nil
        }
    }
    enum Section: Int, CaseIterable { case histogram, layers, film, paper, decode, grain, viewport, fallback }
    struct Bounds: PreferenceKey {
        static var defaultValue: [Section: [Anchor<CGRect>]] { [:] }
        static func reduce(value: inout [Section: [Anchor<CGRect>]], nextValue: () -> [Section: [Anchor<CGRect>]]) {
            value.merge(nextValue(), uniquingKeysWith: +)
        }
    }
}

extension View {
    func filmLabColumnSection(_ section: FilmLabColumnEntrance.Section) -> some View {
        // A viewport contains the film/paper/decode anchors. A fresh anchorPreference value here replaced that
        // entire subtree's dictionary with just .viewport; transform the accumulated value instead.
        transformAnchorPreference(key: FilmLabColumnEntrance.Bounds.self, value: .bounds) { value, anchor in
            value[section, default: []].append(anchor)
        }
    }
    func filmLabColumnEntrance(_ visit: FilmLabColumnEntrance.Visit, frame: LibraryFrame.ID,
                               mode: WorkspaceMode, stock: Bool, layers: Bool, grain: Bool) -> some View {
        modifier(FilmLabColumnEntranceHost(ticket: visit.take(frame: frame, mode: mode), stock: stock, layers: layers, grain: grain))
    }
}

private struct FilmLabColumnEntranceHost: ViewModifier {
    let ticket: FilmLabColumnEntrance.Ticket?
    let stock: Bool, layers: Bool, grain: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var done = false
    func body(content: Content) -> some View {
        content.overlayPreferenceValue(FilmLabColumnEntrance.Bounds.self) { anchors in
            if let ticket, !done {
                GeometryReader { room in
                    let frames = anchors.mapValues { $0.map { room[$0] }.reduce(CGRect.null) { $0.union($1) } }
                    let required = Set<FilmLabColumnEntrance.Section>([.histogram])
                        .union(stock ? [.film, .paper, .decode, .viewport] : []).union(layers ? [.layers] : []).union(grain ? [.grain] : [])
                    FilmLabColumnVeilPlate(ticket: ticket, frames: frames, required: required,
                                           reduce: reduce || FilmLabModeMotion.calmCheck, done: { done = true })
                        .frame(width: room.size.width, height: room.size.height)
                }
                .allowsHitTesting(false).accessibilityHidden(true)
                .onAppear {
                    if ticket.appeared == nil { ticket.appeared = CACurrentMediaTime() }
                    ticket.view?.start()
                }
            }
        }
    }
}

private struct FilmLabColumnVeilPlate: UIViewRepresentable {
    let ticket: FilmLabColumnEntrance.Ticket
    let frames: [FilmLabColumnEntrance.Section: CGRect]
    let required: Set<FilmLabColumnEntrance.Section>
    let reduce: Bool
    let done: () -> Void
    func makeUIView(context: Context) -> FilmLabColumnVeils { FilmLabColumnVeils(ticket: ticket, done: done) }
    func updateUIView(_ view: FilmLabColumnVeils, context: Context) {
        view.frames = frames; view.required = required; view.reduce = reduce; view.start()
    }
    static func dismantleUIView(_ view: FilmLabColumnVeils, coordinator: ()) { view.finish("unmounted") }
}

@MainActor
final class FilmLabColumnVeils: UIView {
    private let ticket: FilmLabColumnEntrance.Ticket
    private var done: (() -> Void)?
    var frames: [FilmLabColumnEntrance.Section: CGRect] = [:]
    var required: Set<FilmLabColumnEntrance.Section> = []
    var reduce = false
    private var installed = false
    private var initialSize = CGSize.zero
    private var veils: [CALayer] = []
    private var link: CADisplayLink?
    private var ticked = false
    private var lifted = false
    private var attempts = 0
    private var fallback = false
    init(ticket: FilmLabColumnEntrance.Ticket, done: @escaping () -> Void) {
        self.ticket = ticket; self.done = done
        super.init(frame: .zero)
        isUserInteractionEnabled = false; accessibilityElementsHidden = true; clipsToBounds = true
        // Covers the first frame even if the stock GeometryReader's anchors reach the host one update later.
        backgroundColor = UIColor(Theme.background)
        ticket.view = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, link == nil, !ticked, !ticket.finished {
            let l = CADisplayLink(target: self, selector: #selector(firstTick(_:)))
            l.add(to: .main, forMode: .common); link = l
            start()
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if installed, bounds.size != initialSize { finish("resize") } else { start() }
    }
    func start() {
        attempts += 1
        let missing = required.filter { frames[$0] == nil }.sorted { $0.rawValue < $1.rawValue }
        let invalid = required.filter { frames[$0] != nil && !valid(frames[$0]) }.sorted { $0.rawValue < $1.rawValue }
        let complete = !required.isEmpty && missing.isEmpty && invalid.isEmpty
        if FilmLabColumnProbe.enabled {
            let names = required.sorted { $0.rawValue < $1.rawValue }
            let have = names.filter { valid(frames[$0]) }
            let geometry = frames.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key):\($0.value)" }.joined(separator: ";")
            ticket.log("start attempt=\(attempts) bounds=\(bounds) window=\(window != nil) appearedMedia=\(ticket.appeared ?? 0) installed=\(installed) ticked=\(ticked) finished=\(ticket.finished) required=\(names) have=\(have) missing=\(missing) invalid=\(invalid) frames=[\(geometry)]")
        }
        guard !ticket.finished, !installed, window != nil, valid(bounds),
              ticket.appeared != nil || ticked, complete || ticked else { return }
        installed = true; initialSize = bounds.size
        fallback = !complete
        // The first display callback is a hard deadline. Missing geometry gets a whole-column CA fade NOW,
        // never another main-queue wait or an opaque plate cut away later.
        let colour = UIColor(Theme.background).resolvedColor(with: traitCollection).cgColor
        let sections = frames.filter { $0.key != .viewport }.map { part -> (key: FilmLabColumnEntrance.Section, value: CGRect) in
            let stock = [.film, .paper, .decode].contains(part.key)
            return (part.key, part.value.intersection(stock ? (frames[.viewport] ?? bounds).intersection(bounds) : bounds))
        }.sorted { $0.key.rawValue < $1.key.rawValue }.filter {
            !$0.value.isNull && !$0.value.isInfinite && !$0.value.intersection(bounds).isEmpty
        }
        let visible = fallback ? [(key: FilmLabColumnEntrance.Section.fallback, value: bounds)] : sections
        if fallback { ticket.log("fallback whole-column deadline=first-display missing=\(missing) invalid=\(invalid)") }
        // The veils start to lift when they first reach the screen (`lift`), not at the column's appearance
        // (2026-11-27: timed from `onAppear` + 50 ms, the whole stagger had run while the main thread was still building
        // the page, ~350 ms before the column was first on screen, and it simply popped in).
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for part in visible {
            let veil = CALayer(); veil.name = String(describing: part.key); veil.frame = part.value.intersection(bounds)
            veil.backgroundColor = colour; veil.opacity = 1
            layer.addSublayer(veil); veils.append(veil)
        }
        backgroundColor = .clear
        CATransaction.commit() // Normal SwiftUI commit only; NEVER flush here.
        lift()
    }

    /// The veils' fades, one after another, on the render server: they run through the main thread's second stall
    /// after the page's first frame (~0.5 s, measured 2026-11-27). Each is a group with no begin time of its own, which
    /// Core Animation stamps with the moment the transaction reaches the screen — the frame the column is first seen
    /// in — and the fade inside it starts `index × delay` later. No clock of the main thread's decides when it starts.
    private func lift() {
        guard installed, !lifted, !ticket.finished else { return }
        lifted = true
        let duration = (reduce ? 0.15 : 0.30) * FilmLabColumnEntrance.slow
        let delay = (reduce ? 0 : 0.035) * FilmLabColumnEntrance.slow
        let fallback = fallback
        CATransaction.begin(); CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in self?.finish(fallback ? "completed-fallback" : "completed") }
        for (index, veil) in veils.enumerated() {
            veil.opacity = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1; fade.toValue = 0; fade.duration = duration
            fade.beginTime = Double(index) * delay; fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let group = CAAnimationGroup()
            group.animations = [fade]; group.duration = Double(index) * delay + duration
            veil.add(group, forKey: "entrance")
            let box = window.map { convert(veil.frame, to: $0) } ?? veil.frame
            ticket.log("veil index=\(index) section=\(veil.name ?? "?") window=\(box) startsAfterShownMS=\(Double(index) * delay * 1000) installedPressMS=\((CACurrentMediaTime() - ticket.press) * 1000)")
        }
        CATransaction.commit()
    }
    private func valid(_ rect: CGRect?) -> Bool {
        rect.map { !$0.isNull && !$0.isInfinite && $0.width > 0 && $0.height > 0 } ?? false
    }
    @objc private func firstTick(_ display: CADisplayLink) {
        ticked = true; link?.invalidate(); link = nil
        ticket.log("first-display media=\(CACurrentMediaTime()) displayTimestamp=\(display.timestamp) appearedMedia=\(ticket.appeared ?? 0)")
        // Where each veil's fade stood at this first callback (1 = not started): shows whether it started with the frame.
        if FilmLabColumnProbe.enabled {
            ticket.log("first-display veils " + veils.map { "\($0.name ?? "?")=\(String(format: "%.2f", $0.presentation()?.opacity ?? -1))" }.joined(separator: " "))
        }
        if !installed { start(); CATransaction.flush() }
    }
    func finish(_ reason: String) {
        guard !ticket.finished else { return }
        ticket.finished = true; link?.invalidate(); link = nil
        ticket.log("veils removed count=\(veils.count) reason=\(reason) media=\(CACurrentMediaTime())")
        for (index, veil) in veils.enumerated() {
            veil.removeAllAnimations(); veil.removeFromSuperlayer()
            ticket.log("veil removed index=\(index) section=\(veil.name ?? "?") reason=\(reason) media=\(CACurrentMediaTime())")
        }
        veils.removeAll(); isHidden = true
        let completion = done; done = nil
        // Dismantling already removes the hierarchy; don't write SwiftUI state from dismantleUIView.
        if reason != "unmounted" { DispatchQueue.main.async { completion?() } }
    }
}
