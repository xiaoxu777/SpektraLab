//  FilmLabMotionPhotoProbe.swift — a check's launch, never a layout input.
//
//  --filmlab-photo-probe WAIT [--filmlab-photo-walk next,next,prev,strip:0,...]
//  Run on an open develop page. Arrows use the live bar's switchFrame closure through MacDevelopOpening;
//  strip:N (zero based, in the strip's filtered order) uses browser.click and the shell's selection watch.
//  No key registry/responder is needed for either path. Out-of-range steps are explicitly skipped.
//  --filmlab-window-size W,H independently sets the main window once, in native Mac points (also in Release).
//  Geometry is in SwiftUI's global/window points, after interface scaling. This sees layout frames, not
//  Core Animation presentation layers. Nothing observes the measurements, and disk writes wait until the
//  600 ms sampling window has ended. A run appends to ~/Library/Logs/FilmLab-photo.txt and leaves the app up.

import SwiftUI
import UIKit

/// Geometry and breadcrumbs in plain reference storage. In particular, none of these writes invalidates a view.
@MainActor
private final class FilmLabPhotoMeasurements {
    static let shared = FilmLabPhotoMeasurements()
    var frames: [String: CGRect] = [:]
    var owners: [String: UUID] = [:]
    var values: [String: String] = [:]
    var bodies = 0
    var recording = false
    var events: [(time: CFTimeInterval, text: String)] = []

    func note(_ text: String) {
        if recording { events.append((CACurrentMediaTime(), text)) }
    }

    func value(_ name: String, _ text: String) {
        guard values[name] != text else { return }
        note("\(name) \(values[name] ?? "?") → \(text)")
        values[name] = text
    }

    func report(_ name: String, _ frame: CGRect, owner: UUID) {
        owners[name] = owner
        frames[name] = frame
    }

    func remove(_ name: String, owner: UUID) {
        note("unmount \(name) \(owner)")
        // A centring change moves the mode between two branches. The old branch must not erase the new one.
        if owners[name] == owner { owners[name] = nil; frames[name] = nil }
    }
}

private struct FilmLabBarPhotoMeasurement: ViewModifier {
    let name: String
    // Identity only; never written by a geometry callback or display tick.
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                FilmLabPhotoMeasurements.shared.report(name, frame, owner: owner)
            }
            .onAppear { FilmLabPhotoMeasurements.shared.note("mount \(name) \(owner)") }
            .onDisappear { FilmLabPhotoMeasurements.shared.remove(name, owner: owner) }
    }
}

extension View {
    @ViewBuilder func filmLabBarProbe(_ name: String) -> some View {
        if FilmLabMotionPhotoProbe.enabled { modifier(FilmLabBarPhotoMeasurement(name: name)) }
        else { self }
    }
}

@MainActor
final class FilmLabMotionPhotoProbe: NSObject {
    private static let wait = FilmLabCheckArgs.value("--filmlab-photo-probe").flatMap(Double.init)
    static var enabled: Bool { wait.map { $0.isFinite && $0 >= 0 } ?? false }
    private static var started = false
    private static var running: FilmLabMotionPhotoProbe?
    private static var windowSizeAsked = false

    static func startIfAsked(model: AppServices) {
        sizeWindowIfAsked()
        guard enabled, !started, let wait else { return }
        started = true
        let probe = FilmLabMotionPhotoProbe(model: model)
        running = probe
        FilmLabPhotoMeasurements.shared.recording = true
        probe.append("\(ISO8601DateFormatter().string(from: Date()))  args \(CommandLine.arguments.dropFirst().joined(separator: " "))\n")
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { probe.start() }
    }

    private static func sizeWindowIfAsked() {
        guard !windowSizeAsked, let raw = FilmLabCheckArgs.value("--filmlab-window-size") else { return }
        windowSizeAsked = true
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let width = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let height = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              width.isFinite, height.isFinite, width > 0, height > 0 else {
            NSLog("[filmlab-window-size] expected positive finite W,H points; got %@", raw)
            return
        }
        // Let launch attach/show the window. Reuse FilmLabResizeProbe's AppKit runtime path, once rather
        // than at every display tick. AppKit frames already use native Mac points: no interface scaling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard let app = (NSClassFromString("NSApplication") as? NSObject.Type)?.value(forKey: "sharedApplication") as? NSObject,
                  let windows = app.value(forKey: "windows") as? [NSObject],
                  // The tallest visible window: a background launch has no main window, and the helper windows are 45 pt.
                  let window = windows.filter({ ($0.value(forKey: "isVisible") as? Bool) == true })
                    .max(by: { (($0.value(forKey: "frame") as? NSValue)?.cgRectValue.height ?? 0) < (($1.value(forKey: "frame") as? NSValue)?.cgRectValue.height ?? 0) }),
                  let base = (window.value(forKey: "frame") as? NSValue)?.cgRectValue else {
                NSLog("[filmlab-window-size] no visible main window at launch")
                return
            }
            let sel = NSSelectorFromString("setFrame:display:")
            typealias Fn = @convention(c) (NSObject, Selector, CGRect, Bool) -> Void
            let fn = unsafeBitCast(window.method(for: sel), to: Fn.self)
            // AppKit's origin is bottom-left: retain the top-left corner, as the resize probe does.
            let frame = CGRect(x: base.minX, y: base.maxY - CGFloat(height), width: CGFloat(width), height: CGFloat(height))
            fn(window, sel, frame, true)
            NSLog("[filmlab-window-size] requested %.1f x %.1f pt; actual %@", width, height,
                  String(describing: (window.value(forKey: "frame") as? NSValue)?.cgRectValue))
        }
    }

    static func value(_ name: String, _ text: @autoclosure () -> String) {
        guard enabled else { return }
        FilmLabPhotoMeasurements.shared.value(name, text())
    }

    static func bodyEvaluated(compact: Int, centred: Bool) {
        guard enabled else { return }
        let m = FilmLabPhotoMeasurements.shared
        m.bodies += 1
        m.value("layout-state", "compact=\(compact) centred=\(centred)")
        m.note("body #\(m.bodies) compact=\(compact) centred=\(centred)")
    }

    private let model: AppServices
    private let steps: [String]
    private var index = 0
    private var link: CADisplayLink?
    private var began: CFTimeInterval = 0
    private var sampling = false
    private var before: [String: CGRect] = [:]
    private var last: [String: CGRect] = [:]
    private var moved: Set<String> = []
    private var ticks = 0
    private var bodyBefore = 0
    private var photoBefore: LibraryFrame.ID?
    private var lines: [String] = []

    private init(model: AppServices) {
        self.model = model
        steps = FilmLabCheckArgs.value("--filmlab-photo-walk")?
            .split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            ?? ["next", "next", "next", "prev", "prev", "prev"]
    }

    private func start() {
        guard !steps.isEmpty, steps.allSatisfy({ $0 == "next" || $0 == "prev" || Self.stripIndex($0) != nil }) else {
            lines.append("aborted: photo-walk accepts next,prev,strip:N (zero-based index)"); finish(); return
        }
        guard MacShellPath.develop(model.router.path) != nil, MacShellBar.shared.develop != nil,
              !FilmLabHome.shared.shown, !FilmLabHome.shared.welcome else {
            lines.append("aborted: open a photo on the develop page before WAIT expires"); finish(); return
        }
        keyDiagnostic() // Read-only, once, before sampling; never gates or performs a walk step.
        let display = CADisplayLink(target: self, selector: #selector(tick(_:)))
        display.add(to: .main, forMode: .common)
        link = display
        next()
    }

    private func next() {
        guard index < steps.count else { finish(); return }
        let m = FilmLabPhotoMeasurements.shared
        began = CACurrentMediaTime()
        drainEvents()
        before = m.frames; last = before; moved = []; ticks = 0; bodyBefore = m.bodies
        photoBefore = MacShellBar.shared.develop?.frameID
        let direction = steps[index]
        index += 1
        let action = photoAction(direction)
        lines.append("step \(index)/\(steps.count) \(direction) photo=\(photoBefore?.uuidString ?? "nil")")
        for name in before.keys.sorted() { lines.append("  before \(name) \(Self.rect(before[name]))") }
        for name in m.values.keys.sorted() { lines.append("  before \(name) \(m.values[name] ?? "?")") }
        if before["bar"] == nil || before["mode"] == nil { lines.append("  WARNING: incomplete bar geometry; do not infer stability") }
        lines.append("  \(action.description)")
        began = CACurrentMediaTime()
        sampling = true
        // Schedule before dispatch: synchronous work in opening the photo counts towards the 600 ms.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in endStep() }
        action.run?()
    }

    private static func stripIndex(_ token: String) -> Int? {
        token.hasPrefix("strip:") ? Int(token.dropFirst(6)) : nil
    }

    private func photoAction(_ token: String) -> (description: String, run: (() -> Void)?) {
        guard MacShellPath.develop(model.router.path) != nil, let dev = MacShellBar.shared.develop,
              !dev.inCrop, !FilmLabHome.shared.shown, !FilmLabHome.shared.welcome,
              model.router.cover == nil, model.router.sheets.isEmpty,
              MacShellPath.split(model.router.path).stacked.isEmpty else {
            return ("skipped: no live, uncovered develop page (or crop is open)", nil)
        }
        let store = MacLibraryUI.store(model)
        if let n = Self.stripIndex(token) {
            // Exactly ShellFilmStrip's row set and FilmStripBar's single-click selection path. Its onChange
            // in MainWindowLayout.developWatch opens the row; calling dev.open here too would double-open it.
            let rows = FilmLabRollFilterState.shared.apply(store.images, library: model.library)
            guard rows.indices.contains(n) else {
                return ("skipped: strip index=\(n) out of range; count=\(rows.count) (zero based)", nil)
            }
            let row = rows[n]
            return ("dispatch strip index=\(n) count=\(rows.count) target=\(row.fileName) same-photo=\(row.develop?.frameID == dev.frameID) shown=\(ShellFilmStrip.shown)", {
                MacLibraryBrowser.shared.click(row.id, command: false, shift: false, in: rows)
            })
        }
        // PadDevelopPage.browserNeighbour is private to its file. Use its exact frame-ID/order lookup,
        // then the arrow action's existing open path, whose live bar closure calls switchFrame(to:).
        let rows = store.images
        guard let i = rows.firstIndex(where: { $0.develop?.frameID == dev.frameID }) else {
            return ("skipped: live frame \(dev.frameID) absent from store rows; count=\(rows.count)", nil)
        }
        let j = i + (token == "next" ? 1 : -1)
        guard rows.indices.contains(j) else {
            return ("skipped: \(token) boundary current=\(i) target=\(j) count=\(rows.count) (zero based)", nil)
        }
        let row = rows[j]
        return ("dispatch direct \(token) index=\(i)→\(j) count=\(rows.count) target=\(row.fileName)", {
            MacDevelopOpening.open(row, store: store, into: dev.open)
        })
    }

    private func keyDiagnostic() {
        let registry = MacShortcutRegistry.shared
        let rows = MacLibraryUI.store(model).images
        let current = MacShellBar.shared.develop?.frameID
        lines.append("key-diagnostic typing=\(registry.typing) browser-modal=\(MacLibraryBrowser.shared.modal) rows=\(rows.count) current-index=\(rows.firstIndex { $0.develop?.frameID == current }.map(String.init) ?? "absent")")
        for (name, input, expected) in [("next", UIKeyCommand.inputRightArrow, L("Next photo")),
                                         ("prev", UIKeyCommand.inputLeftArrow, L("Previous photo"))] {
            let command = UIKeyCommand(input: input, modifierFlags: [], action: NSSelectorFromString("spkShortcut:"))
            let offered = registry.keyCommands.filter { $0.input == input }
            let titleGate = offered.contains { $0.modifierFlags.isEmpty && $0.title == expected }
            lines.append("  \(name) canPerform=\(registry.canPerform(command)) old-title-gate=\(titleGate) offered=\(offered.map { "\($0.title) flags=\($0.modifierFlags.rawValue)" })")
            #if DEBUG
            lines.append("  registrations \(registry.registrations(of: input))")
            #endif
        }
        for (i, row) in rows.enumerated() {
            lines.append("  row \(i) \(row.fileName) frame=\(row.develop?.frameID.uuidString ?? "nil")")
        }
    }

    @objc private func tick(_ display: CADisplayLink) {
        guard sampling, CACurrentMediaTime() - began <= 0.6 else { return }
        ticks += 1
        sample()
    }

    private static func changed(_ a: CGRect?, _ b: CGRect?) -> Bool {
        switch (a, b) {
        case let (a?, b?): return abs(a.minX - b.minX) >= 0.5 || abs(a.width - b.width) >= 0.5
        case (nil, nil): return false
        default: return true
        }
    }

    private static func rect(_ r: CGRect?) -> String {
        guard let r else { return "absent" }
        return String(format: "x=%.2f w=%.2f y=%.2f h=%.2f", Double(r.minX), Double(r.width), Double(r.minY), Double(r.height))
    }

    private func sample() {
        drainEvents()
        let frames = FilmLabPhotoMeasurements.shared.frames
        let ms = (CACurrentMediaTime() - began) * 1000
        for name in Set(last.keys).union(frames.keys).sorted() where Self.changed(last[name], frames[name]) {
            lines.append(String(format: "  +%.1f ms %@ %@ → %@", ms, name, Self.rect(last[name]), Self.rect(frames[name])))
            moved.insert(name)
            last[name] = frames[name]
        }
    }

    private func drainEvents() {
        let m = FilmLabPhotoMeasurements.shared
        for e in m.events { lines.append(String(format: "  %+.1f ms %@", (e.time - began) * 1000, e.text)) }
        m.events.removeAll(keepingCapacity: true)
    }

    private func endStep() {
        sampling = false
        sample() // Endpoint too, even when the main thread missed every display tick.
        let m = FilmLabPhotoMeasurements.shared
        let twitch = moved.filter { !Self.changed(before[$0], m.frames[$0]) }.sorted()
        let settle = moved.filter { Self.changed(before[$0], m.frames[$0]) }.sorted()
        let photo = MacShellBar.shared.develop?.frameID
        lines.append(String(format: "  summary step %d frames=%d elapsed=%.1f ms bodies=+%d twitch=[%@] settle=[%@] photo=%@ changed=%@",
                            index, ticks, (CACurrentMediaTime() - began) * 1000, m.bodies - bodyBefore,
                            twitch.joined(separator: ","), settle.joined(separator: ","), photo?.uuidString ?? "nil",
                            photo != photoBefore ? "yes" : "no"))
        if ticks == 0 { lines.append("  WARNING: no display sample in 600 ms; transient motion may have been missed") }
        append(lines.joined(separator: "\n") + "\n"); lines.removeAll(keepingCapacity: true)
        if index == steps.count { finish(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1.2 - (CACurrentMediaTime() - began), 0)) { [self] in next() }
    }

    private func finish() {
        link?.invalidate(); link = nil
        if began == 0 { began = CACurrentMediaTime() }
        drainEvents()
        FilmLabPhotoMeasurements.shared.recording = false
        lines.append("done (app left running; twitch/settle compare layout minX/width at the 600 ms endpoint)")
        append(lines.joined(separator: "\n") + "\n")
        Self.running = nil
    }

    private func append(_ text: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/FilmLab-photo.txt")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let h = try FileHandle(forWritingTo: url)
                defer { try? h.close() }
                h.seekToEndOfFile(); h.write(Data(text.utf8))
            } else { try Data(text.utf8).write(to: url) }
        } catch { NSLog("[filmlab-photo] log write failed: %@", error.localizedDescription) }
    }
}
