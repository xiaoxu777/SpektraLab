// --filmlab-column-probe, alongside --filmlab-mode-probe: observe, never drive, the column.
// Catalyst's floor is 17.0 (gen_project.py). A background GeometryReader sizes a transparent UIKit marker;
// it makes no proposal to the tagged content. Read its model AND presentation layers on each display tick:
// geometry-change callbacks alone miss drawing transitions and ancestor scroll offsets between layouts.
// No measured value is observable. Buffer each press, then append off-main, outside its sampling window.

import SwiftUI
import UIKit

extension View {
    @ViewBuilder func filmLabColumnTag(_ name: String?, motion: FilmLabColumnProbe.Motion? = nil) -> some View {
        if FilmLabColumnProbe.enabled, let name { modifier(FilmLabColumnTag(name: name, motion: motion)) }
        else { self }
    }
}

private struct FilmLabColumnTag: ViewModifier {
    let name: String
    let motion: FilmLabColumnProbe.Motion?
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { room in
                    FilmLabColumnMarker(name: name, owner: owner, motion: motion)
                        .frame(width: room.size.width, height: room.size.height)
                }
                .allowsHitTesting(false).accessibilityHidden(true)
            }
            .onAppear { FilmLabColumnProbe.shared.event("appear", name: name, owner: owner) }
            .onDisappear { FilmLabColumnProbe.shared.event("disappear", name: name, owner: owner) }
    }
}

private struct FilmLabColumnMarker: UIViewRepresentable {
    let name: String
    let owner: UUID
    let motion: FilmLabColumnProbe.Motion?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        FilmLabColumnProbe.shared.attach(view, name: name, owner: owner, motion: motion)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        FilmLabColumnProbe.shared.update(owner: owner, motion: motion)
    }
    func makeCoordinator() -> UUID { owner }

    static func dismantleUIView(_ view: UIView, coordinator: UUID) {
        FilmLabColumnProbe.shared.detach(coordinator)
    }
}

@MainActor
final class FilmLabColumnProbe: NSObject {
    static let enabled = CommandLine.arguments.contains("--filmlab-column-probe")
    fileprivate static let shared = FilmLabColumnProbe()
    private static let writer = DispatchQueue(label: "FilmLab.column-probe.log", qos: .utility)

    struct Motion: Equatable {
        let gone: CGFloat
        let opacity: CGFloat
        let phase: String
    }

    /// The kept panel's body sample. Transition parts use their mounted marker's updateUIView instead, so a
    /// preparation/identity evaluation cannot replace the interpolated drawing. Neither path is Observable.
    static func motion(_ tag: String, gone: CGFloat, opacity: CGFloat, phase: String) {
        guard enabled else { return }
        shared.motions[tag] = Motion(gone: gone, opacity: opacity, phase: phase)
    }

    private final class Marker {
        let name: String
        weak var view: UIView?
        var motion: Motion?
        init(_ name: String, _ view: UIView, motion: Motion?) { self.name = name; self.view = view; self.motion = motion }
    }

    private struct Frames {
        let layout: CGRect
        let draw: CGRect
        let motion: Motion?

        func changed(from old: Self) -> Bool {
            motion != old.motion || zip(numbers, old.numbers).contains { abs($0 - $1) >= 0.5 }
        }

        private var numbers: [CGFloat] {
            [layout.minY, layout.height, layout.minX, layout.width, draw.minY, draw.height, draw.minX, draw.width]
        }
    }

    private final class Press {
        let name: String
        let number: Int
        let began: CFTimeInterval
        let end: CFTimeInterval
        var tick = 0
        var lastTick: Double = 0
        var frames: [UUID: Frames] = [:]
        var lines: [String] = []

        init(_ name: String, number: Int, began: CFTimeInterval, duration: Double) {
            self.name = name; self.number = number; self.began = began; end = began + duration
        }

        func note(_ text: String, at now: CFTimeInterval) {
            lines.append(String(format: "%@ #%d +%8.2fms tick=%d %@", name, number, (now - began) * 1000, tick, text))
        }
    }

    private var markers: [UUID: Marker] = [:]
    private var motions: [String: Motion] = [:]
    private var presses: [Press] = []
    private var sequence = 0
    private var bodies = 0
    private var link: CADisplayLink?
    private var walkFinished = false

    /// Entrance CA schedules/cleanup may outlive a mode probe's 0.8 s window, or come from a real double-click.
    static func entrance(_ text: String, press: CFTimeInterval) {
        guard enabled else { return }
        shared.append(String(format: "library→develop +%.2fms entrance pressMedia=%.6f %@\n", (CACurrentMediaTime() - press) * 1000, press, text))
    }

    static func startIfAsked() {
        guard enabled else { return }
        shared.walkFinished = false
        guard shared.link == nil else { return }
        let link = CADisplayLink(target: shared, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        shared.link = link
    }

    /// Called immediately before the mode probe uses the bar's action, with that probe's name and press clock.
    /// Separate windows allow --mode-gap shorter than 0.8 * slow without truncating the preceding press.
    static func press(_ name: String, at began: CFTimeInterval, round: Int) {
        guard enabled else { return }
        let probe = shared
        probe.sequence += 1
        let press = Press(name, number: probe.sequence, began: began, duration: 0.8 * FilmLabModeMotion.slow)
        probe.presses.append(press)
        press.note("begin \(ISO8601DateFormatter().string(from: Date())) round=\(round) simple=\(FeatureFlags.simpleWindow) slow=\(FilmLabModeMotion.slow) windowMS=\((press.end - began) * 1000)", at: began)
        probe.sample(press, at: CACurrentMediaTime(), kind: "baseline")
    }

    static func columnBody(mode: WorkspaceMode, stockShown: Bool) {
        guard enabled else { return }
        shared.bodies += 1
        shared.note("body=\(shared.bodies) mode=\(mode.rawValue) stockShown=\(stockShown)")
    }

    static func finishWalk() {
        guard enabled else { return }
        shared.walkFinished = true
        shared.stopIfFinished()
    }

    fileprivate func attach(_ view: UIView, name: String, owner: UUID, motion: Motion?) {
        markers[owner] = Marker(name, view, motion: motion)
        event("attach", name: name, owner: owner)
    }

    /// updateUIView belongs to the mounted drawing. Transition endpoint/body evaluations alone cannot overwrite it;
    /// two drawings with the same tag each retain their own owner and their own interpolated values.
    fileprivate func update(owner: UUID, motion: Motion?) {
        markers[owner]?.motion = motion
    }

    fileprivate func detach(_ owner: UUID) {
        if let marker = markers.removeValue(forKey: owner) { event("detach", name: marker.name, owner: owner) }
        // Keep the last emitted rectangle until the press ends; an onDisappear can precede the removal's last tick.
    }

    fileprivate func event(_ event: String, name: String, owner: UUID) {
        note("\(event) \(name)@\(owner.uuidString.prefix(8))")
    }

    private func note(_ text: String) {
        let now = CACurrentMediaTime()
        for press in presses where now <= press.end { press.note(text, at: now) }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        for press in presses where now <= press.end {
            press.tick += 1
            press.lastTick = (now - press.began) * 1000
            sample(press, at: now, kind: "frame")
        }
        for press in presses where now > press.end {
            press.note(String(format: "end ticks=%d lastTickMS=%.2f endLateMS=%.2f", press.tick, press.lastTick, (now - press.end) * 1000), at: now)
            append(press.lines.joined(separator: "\n") + "\n")
        }
        presses.removeAll { now > $0.end }
        stopIfFinished()
    }

    private func sample(_ press: Press, at now: CFTimeInterval, kind: String) {
        for (owner, marker) in markers.sorted(by: { $0.value.name < $1.value.name }) {
            guard let view = marker.view, let window = view.window else { continue }
            let layout = view.convert(view.bounds, to: window)
            // Never convert between a model layer and a presentation layer (different trees on an insertion tick).
            let draw: CGRect
            let source: String
            if let layer = view.layer.presentation(), let target = window.layer.presentation() {
                draw = layer.convert(layer.bounds, to: target)
                source = "P"
            } else { draw = layout; source = "M" }
            let motion = marker.motion ?? (marker.name == "keptStock.content" ? motions["keptStock"] : nil)
            let frames = Frames(layout: layout, draw: draw, motion: motion)
            if let old = press.frames[owner], !frames.changed(from: old) { continue }
            press.frames[owner] = frames
            // Both rectangles are window points, top-left origin; un-clipped content can extend outside the viewport.
            let ownMotion = motion.map { String(format: " motion=%@ phase=%@ gone=%.4f opacity=%.4f", marker.motion == nil ? "body" : "render", $0.phase, $0.gone, $0.opacity) } ?? ""
            let keptMotion = motions["keptStock"].map { String(format: " kept.opacity=%.4f kept.gone=%.4f", $0.opacity, $0.gone) } ?? " kept.opacity=n/a"
            press.note("\(kind) \(marker.name)@\(owner.uuidString.prefix(8)) layout[y,h,x,w]=\(rect(frames.layout)) draw(\(source))[y,h,x,w]=\(rect(frames.draw))" + ownMotion + keptMotion, at: now)
        }
    }

    private func rect(_ frame: CGRect) -> String {
        String(format: "[%.2f,%.2f,%.2f,%.2f]", frame.minY, frame.height, frame.minX, frame.width)
    }

    private func stopIfFinished() {
        if walkFinished, presses.isEmpty { link?.invalidate(); link = nil }
    }

    private func append(_ text: String) {
        Self.writer.async {
            let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/FilmLab-column.txt")
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
                let file = try FileHandle(forWritingTo: url)
                defer { try? file.close() }
                try file.seekToEnd()
                try file.write(contentsOf: Data(text.utf8))
            } catch { NSLog("[filmlab-column] append failed: %@", String(describing: error)) }
        }
    }
}
