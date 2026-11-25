//  FilmLabResizeProbe.swift — a check's launch only: the window resized by the app itself, and how smoothly it went.
//
//  The owner, 2026-11-24: "改变窗口大小好卡啊". A drag on the window's edge cannot be driven from outside here, so
//  `--filmlab-resize-probe SECONDS` waits SECONDS (the page settles, a develop finishes), then for four seconds asks
//  the window for a new width at every display frame — narrower and back, as a hand drags it — and writes what
//  happened to `~/Library/Logs/FilmLab-resize.txt`: how many sizes the window took, and the gaps between display
//  frames (a long gap is the main thread busy re-laying out the page). Nothing is changed in the library or settings.

import UIKit

@MainActor
final class FilmLabResizeProbe: NSObject {
    private static var running: FilmLabResizeProbe?

    static func startIfAsked() {
        guard running == nil, let wait = FilmLabCheckArgs.value("--filmlab-resize-probe").flatMap(Double.init) else { return }
        let probe = FilmLabResizeProbe()
        running = probe
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { probe.start() }
    }

    private var link: CADisplayLink?
    private var scene: UIWindowScene?
    private var origin = CGRect.zero
    private var t0: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var gaps: [Double] = []
    private var sizes: Set<Int> = []
    private let duration: CFTimeInterval = 4

    private func start() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        self.scene = scene
        origin = scene.effectiveGeometry.systemFrame
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        t0 = CACurrentMediaTime()
        last = t0
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        gaps.append((now - last) * 1000)
        last = now
        guard let scene else { return }
        sizes.insert(Int(scene.windows.first?.bounds.width ?? 0)); nsSizes.insert(Int((nsWindow?.value(forKey: "frame") as? NSValue)?.cgRectValue.width ?? -1))
        let t = now - t0
        if t >= duration {
            l.invalidate(); link = nil
            setFrame(origin)
            write()
            return
        }
        // Out by 360 pt and back in (the window opens at its smallest), twice, as a hand drags the edge.
        let phase = (t / duration) * 2
        let swing = 1 - abs((phase.truncatingRemainder(dividingBy: 1)) * 2 - 1)
        var frame = origin
        frame.size.width = origin.width + 360 * swing
        frame.size.height = origin.height + (CommandLine.arguments.contains("--filmlab-resize-wide") ? 0 : 160) * swing
        setFrame(frame)
    }

    /// The AppKit window's frame set, as a drag on its edge sets it (`requestGeometryUpdate` is coalesced away when
    /// asked at every display frame). Reached through the runtime, as the app reaches AppKit elsewhere.
    private var nsWindow: NSObject?
    private func setFrame(_ r: CGRect) {
        if nsWindow == nil,
           let app = (NSClassFromString("NSApplication") as? NSObject.Type)?.value(forKey: "sharedApplication") as? NSObject,
           let windows = app.value(forKey: "windows") as? [NSObject] {
            nsWindow = windows.first { ($0.value(forKey: "isVisible") as? Bool) == true && ($0.value(forKey: "isMainWindow") as? Bool) == true }
                ?? windows.first { ($0.value(forKey: "isVisible") as? Bool) == true }
            if let w = nsWindow, let f = (w.value(forKey: "frame") as? NSValue)?.cgRectValue { originNS = f }
        }
        guard let w = nsWindow, let base = originNS else { return }
        let sel = NSSelectorFromString("setFrame:display:")
        typealias Fn = @convention(c) (NSObject, Selector, CGRect, Bool) -> Void
        let fn = unsafeBitCast(w.method(for: sel), to: Fn.self)
        // AppKit's frame is bottom-left based: keep the top edge where it was.
        let f = CGRect(x: base.minX, y: base.maxY - r.height, width: r.width, height: r.height)
        fn(w, sel, f, true)
    }
    private var originNS: CGRect?
    private var nsSizes: Set<Int> = []

    private func write() {
        let sorted = gaps.dropFirst().sorted()
        let mean = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let over50 = sorted.filter { $0 > 50 }.count
        let line = String(format: "%@  frames %d  sizes %d  mean %.1f ms  p95 %.1f ms  max %.1f ms  >50ms %d  args %@  win %@\n",
                          ISO8601DateFormatter().string(from: Date()), sorted.count, sizes.count, mean, p95,
                          sorted.last ?? 0, over50, CommandLine.arguments.dropFirst().joined(separator: " "), "ns \(nsSizes.count) \(nsWindow.map { String(describing: type(of: $0)) } ?? "nil") \(originNS.map { "\($0)" } ?? "-") now \((nsWindow?.value(forKey: "frame") as? NSValue)?.cgRectValue ?? .zero)")
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/FilmLab-resize.txt")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
        Self.running = nil
    }
}
