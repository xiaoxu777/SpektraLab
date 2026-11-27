//  FilmLabMotionFlightProbe.swift — opt-in diagnostics, kept out of the layout and rendering pipeline.
//
//  The driver follows the grid's MacLibraryGo.open path, not a synthetic develop route. Three round trips may make
//  the ordinary session sidecars/previews, just as double-clicking the selected photograph would. Buffered results
//  reach disk after the flight; display callbacks never write a log or observable view state.

import Darwin
import SwiftUI
import UIKit

@MainActor enum FilmLabFlightOptions {
    static let off = CommandLine.arguments.contains("--filmlab-flight-off")
    static let calm = CommandLine.arguments.contains("--filmlab-reduce-motion")
    static let slow: Double = {
        let n = FilmLabCheckArgs.value("--filmlab-flight-slow").flatMap(Double.init) ?? 1
        return n.isFinite && n > 0 ? min(n, 100) : 1
    }()
    static let hold: Double? = {
        guard let n = FilmLabCheckArgs.value("--filmlab-flight-hold").flatMap(Double.init), n.isFinite else { return nil }
        return n.clamped(to: 0...1)
    }()
    static func animation(seconds: Double) -> Animation { .timingCurve(0.25, 0.6, 0.35, 1, duration: seconds) }
    /// Core Animation's timing curve at an elapsed fraction; used only once to freeze the other drawing layers.
    static func eased(_ t: Double) -> Double {
        func b(_ s: Double, _ a: Double, _ b: Double) -> Double { 3 * (1-s) * (1-s) * s * a + 3 * (1-s) * s * s * b + s*s*s }
        var low = 0.0, high = 1.0
        for _ in 0..<24 { let mid = (low + high) / 2; if b(mid, 0.25, 0.35) < t { low = mid } else { high = mid } }
        return b((low + high) / 2, 0.6, 1)
    }
}

@MainActor final class FilmLabMotionFlightProbe: NSObject {
    private static let wait = FilmLabCheckArgs.value("--filmlab-flight-probe").flatMap(Double.init)
    private static var driver: Task<Void, Never>?
    private static var meter: FilmLabMotionFlightProbe?
    private static var started = false
    private static let logQueue = DispatchQueue(label: "FilmLab.flight-log", qos: .utility)
    private let cpu = MainCPU()
    private var link: CADisplayLink?
    private let began = CACurrentMediaTime()
    private var previous = CACurrentMediaTime()
    private var gaps: [Double] = []
    private var lines: [String] = []
    private var cpuStart: Double?
    private var readyTime: Double?
    private var destinationAtStart: CGRect?
    private var direction = "?"
    private var committedAt: CFTimeInterval?
    private var lastMeasuredDestination: CGRect?
    private var previousPicture: CGRect?
    private var presentationTicks: [(ms: Double, rect: CGRect, gap: Double, refresh: Double, missed: Int, jump: CGFloat)] = []
    private var largestJump: CGFloat = 0
    private var largestTimelyJump: CGFloat = 0
    private var missedTicks = 0
    private var refreshInterval: CFTimeInterval = 1.0 / 60

    static func startIfAsked(model: AppServices) {
        guard !started, let wait, wait.isFinite, wait >= 0 else { return }
        started = true
        driver = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            let store = MacLibraryUI.store(model)
            let browser = MacLibraryBrowser.shared
            guard MacShellPath.develop(model.router.path) == nil,
                  let row = browser.primary(store.images) ?? store.images.first else {
                write("probe skipped: start in 图库 with the launch photo selected\n"); return
            }
            for round in 1...3 {
                browser.selection = [row.id]; browser.focus = row.id; browser.scrollTarget = row.id
                // Let the selected image publish its source rect before using the double-click path.
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                write("round \(round)\n")
                MacLibraryGo.open(row, model: model)
                // Measure the two-second dwell from entry, rather than charging catalog frame-making to it.
                for _ in 0..<100 {
                    if MacShellPath.develop(model.router.path) != nil { break }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
                guard MacShellPath.develop(model.router.path) != nil else { write("probe stopped: open failed\n"); return }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                model.router.toLibrary()
                do { try await Task.sleep(for: .seconds(max(0.8, 0.6 * FilmLabFlightOptions.slow))) } catch { return }
            }
            write("probe finished: 3 round trips\n"); driver = nil
        }
    }

    static func begin(_ direction: String, source: CGRect, destination: CGRect?) {
        guard let wait, wait.isFinite, wait >= 0 else { return }
        interrupted()
        let p = FilmLabMotionFlightProbe(); meter = p; p.direction = direction
        p.lines = ["\(ISO8601DateFormatter().string(from: Date())) \(direction) source=\(rect(source))"]
        if let destination { p.destinationAtStart = destination; p.lines.append("destination.start=\(rect(destination))") }
        p.cpuStart = p.cpu.milliseconds()
        let l = CADisplayLink(target: p, selector: #selector(tick(_:)))
        p.refreshInterval = 1 / Double(max(1, FilmLabMotionFlight.current?.surface?.window?.screen.maximumFramesPerSecond ?? 60))
        p.previousPicture = source
        p.link = l; l.add(to: .main, forMode: .common)
    }
    static func committed() {
        guard let p = meter else { return }
        p.committedAt = CACurrentMediaTime()
        p.lines.append(String(format: "preflight_commit_ms=%.3f flushed_before_navigation=true", (p.committedAt! - p.began) * 1000))
    }
    static func navigation() {
        guard let p = meter, let committed = p.committedAt else { return }
        p.lines.append(String(format: "navigation_after_commit_ms=%.3f", (CACurrentMediaTime() - committed) * 1000))
    }
    static func measuredDestination(_ rect: CGRect) {
        guard let p = meter, p.lastMeasuredDestination != rect else { return }
        p.lastMeasuredDestination = rect
        p.lines.append("destination.measured=\(self.rect(rect))")
    }
    static func retargetSkipped(_ rect: CGRect, expectedAspect: CGFloat) {
        meter?.lines.append(String(format: "retarget_skipped=aspect-mismatch rect=%@ expected_aspect=%.6f measured_aspect=%.6f ready=false",
                                  self.rect(rect), expectedAspect, rect.width / rect.height))
    }
    static func destination(_ rect: CGRect) {
        guard let p = meter else { return }
        if p.destinationAtStart == nil { p.destinationAtStart = rect; p.lines.append("destination.start=\(self.rect(rect))") }
    }
    static func baseline(_ reason: String) {
        guard wait != nil else { return }
        begin(reason, source: .zero, destination: nil)
        let recording = meter
        Task { @MainActor in
            do { try await Task.sleep(for: .seconds(0.6 * FilmLabFlightOptions.slow)) } catch { return }
            guard meter === recording else { return }
            recording?.finish(reason: reason); meter = nil
        }
    }
    static func ready(after seconds: Double) { meter?.readyTime = seconds }
    static func handoff(overlay: CGRect, canvas: CGRect?, destination: CGRect?, reason: String) {
        guard let p = meter else { return }
        p.lines.append("handoff reason=\(reason) overlay.final=\(rect(overlay)) destination.handoff=\(destination.map(rect) ?? "none") canvas=\(canvas.map(rect) ?? "none")")
        let reference = p.direction == "in" ? canvas : destination
        if let reference {
            let error = edgeError(overlay, reference)
            p.lines.append(String(format: "max_edge_error_pt=%.4f", error))
            if FilmLabMotionFlight.current?.calm == true { p.lines.append("geometry_check=not-applicable-reduce-motion") }
        }
        p.finish(reason: reason); meter = nil
    }
    static func interrupted() {
        guard let p = meter else { return }
        p.finish(reason: "interrupted"); meter = nil
    }
    @objc private func tick(_ display: CADisplayLink) {
        let now = CACurrentMediaTime()
        let gap = now - previous
        gaps.append(gap * 1000); previous = now
        // Use the link's target interval (variable refresh), not elapsed callback time: a blocked callback must not
        // become one very long "frame" when estimating the missing samples.
        let interval = display.targetTimestamp - display.timestamp
        let nominal = interval > 0 && interval < 0.1 ? interval : refreshInterval
        refreshInterval = nominal
        let missed = max(0, Int((gap / nominal).rounded()) - 1)
        missedTicks += missed
        guard let flight = FilmLabMotionFlight.current, flight.active, let rect = flight.surface?.pictureRect else { return }
        let jump = previousPicture.map { hypot(rect.midX - $0.midX, rect.midY - $0.midY) } ?? 0
        previousPicture = rect
        largestJump = max(largestJump, jump)
        if missed == 0 { largestTimelyJump = max(largestTimelyJump, jump) }
        presentationTicks.append(((now - began) * 1000, rect, gap * 1000, nominal * 1000, missed, jump))
    }
    private func finish(reason: String) {
        link?.invalidate(); link = nil
        // Include a final unfinished interval: a blocked main thread must not disappear from the result.
        let tail = CACurrentMediaTime() - previous
        gaps.append(tail * 1000)
        missedTicks += max(0, Int((tail / refreshInterval).rounded(.down)))
        let cpuMS = cpuStart.flatMap { start in cpu.milliseconds().map { max(0, $0 - start) } }
        lines.append(String(format: "finish=%@ elapsed_ms=%.1f ready_ms=%@ longest_gap_ms=%.2f gaps_gt_33=%d main_cpu_ms=%@",
            reason, (CACurrentMediaTime() - began) * 1000, readyTime.map { String(format: "%.1f", $0 * 1000) } ?? "none",
            gaps.max() ?? 0, gaps.filter { $0 > 33 }.count, cpuMS.map { String(format: "%.2f", $0) } ?? "unavailable"))
        lines.append(String(format: "presentation_ticks=%d missed_ticks=%d missed_ticks_estimated=true largest_tick_jump_pt=%.3f largest_unmissed_tick_jump_pt=%.3f",
            presentationTicks.count, missedTicks, largestJump, largestTimelyJump))
        // A jump across a late main-thread callback spans missed display samples; it is not evidence that CA froze.
        // Keep every delivered sample so a recording can be aligned with the compositor path and the missed ticks.
        lines += presentationTicks.map {
            String(format: "presentation_tick_ms=%.3f rect=%@ gap_ms=%.3f refresh_ms=%.3f missed=%d center_jump_pt=%.3f",
                   $0.ms, Self.rect($0.rect), $0.gap, $0.refresh, $0.missed, $0.jump)
        }
        Self.write(lines.joined(separator: "\n") + "\n")
    }
    static func edgeError(_ a: CGRect, _ b: CGRect) -> CGFloat {
        [abs(a.minX-b.minX), abs(a.minY-b.minY), abs(a.maxX-b.maxX), abs(a.maxY-b.maxY)].max() ?? 0
    }
    private static func rect(_ r: CGRect) -> String { String(format: "[%.3f,%.3f,%.3f,%.3f]", r.minX, r.minY, r.width, r.height) }
    private static func write(_ text: String) {
        logQueue.async {
            let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs", isDirectory: true)
            let url = folder.appendingPathComponent("FilmLab-flight.txt")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let data = Data(text.utf8)
                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd(); try handle.write(contentsOf: data)
                } else { try data.write(to: url) }
            } catch { NSLog("[filmlab-flight] log write failed: %@", error.localizedDescription) }
        }
    }
    /// Same thread accounting as FilmLabModeProbe. RSS omits the Metal pool; no memory claim is made here.
    private final class MainCPU {
        private let thread = mach_thread_self()
        deinit { mach_port_deallocate(mach_task_self_, thread) }
        func milliseconds() -> Double? {
            var info = thread_basic_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            guard status == KERN_SUCCESS else { return nil }
            return (Double(info.user_time.seconds) + Double(info.system_time.seconds)) * 1000
                + (Double(info.user_time.microseconds) + Double(info.system_time.microseconds)) / 1000
        }
    }
}
