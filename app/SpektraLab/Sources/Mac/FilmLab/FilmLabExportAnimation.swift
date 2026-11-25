//  FilmLabExportAnimation.swift — what an export looks like while it runs (the owner, 2026-11-25: "图像导出的时候我也希望
//  有对应动画").
//
//  The picture is seen leaving: as a frame's export begins, its thumbnail lifts off the viewer as a card, the frame's own
//  progress along its foot; as its file lands in the folder, the card shrinks and travels down into the folder tray at
//  the column's pinned foot, which settles and counts one more. When the batch has ended the foot says so — a check,
//  "已导出 N 张", 在访达中显示 — and goes back to itself. A frame that fails lifts no further: its card greys and drops
//  back, and the foot names the frame and why, with no check.
//
//  **Only the batch's own events move anything.** `FilmLabExportShow.follow` reads `MacExportRun.lines` when they
//  change (the run's watcher writes them from the scheduler's jobs): a line `.running` is a card lifted and its
//  fraction, `.saved` its flight, `.failed`/`.stopped` its fall. No timer stands in for progress, and nothing in the
//  export waits for a card: the next frame is under way while the last one's card is still in the air.
//
//  **It takes nothing from the page.** The cards are an overlay that takes no clicks (`FilmLabExportFlight`, over the
//  develop page); where they start and land is read from two rectangles the viewer and the tray write as they are laid
//  out (`FilmLabExportStage`, not observed: a resize redraws nothing for them). Stop works throughout.
//
//  **Reduce Motion**: no lift, no flight, no bounce — the card fades in over the viewer's corner and out again, and the
//  foot's bar and count carry the progress.

import SwiftUI

/// Where a card starts and where it lands, in the develop page's own coordinates (`space`, which the page names where
/// it lays the cards over itself). Plain storage, written at layout.
@MainActor
final class FilmLabExportStage {
    static let shared = FilmLabExportStage()
    static let space = "filmlab.export.page"
    /// The picture's area on the develop page.
    var viewer: CGRect = .zero
    /// The folder tray in the pinned foot.
    var tray: CGRect = .zero
}

/// The cards in the air, made from the batch's lines.
@MainActor
@Observable
final class FilmLabExportShow {
    static let shared = FilmLabExportShow()

    struct Card: Identifiable, Equatable {
        enum Phase: Equatable { case lifted, flying, fallen }
        /// The batch's line.
        let id: Int
        let frameID: LibraryFrame.ID
        var phase: Phase = .lifted
        /// The frame's own progress, 0…1.
        var fraction = 0.0
    }

    private(set) var cards: [Card] = []
    /// Counts the cards that reached the tray: the tray settles at each.
    private(set) var landed = 0

    static let flight: Double = 0.62
    static let fall: Double = 0.36

    /// The batch's lines changed: the cards follow.
    func follow(_ lines: [MacExportRun.Line], running: Bool) {
        for line in lines {
            guard let frame = line.frameID else { continue }
            let i = cards.firstIndex { $0.id == line.id }
            switch line.state {
            case .running(let p):
                if let i {
                    if cards[i].phase == .lifted, abs(cards[i].fraction - p.fraction) > 0.004 { cards[i].fraction = p.fraction }
                } else {
                    cards.append(Card(id: line.id, frameID: frame, fraction: p.fraction))
                }
            case .saved:
                // A frame that finished between two looks of the run never showed as running: it flies all the same.
                if i == nil, running || line.ended.map({ Date().timeIntervalSince($0) < 1 }) == true, !gone.contains(line.id) {
                    cards.append(Card(id: line.id, frameID: frame, fraction: 1))
                    // Laid first, sent on the next turn, so the flight animates from the viewer.
                    let id = line.id
                    Task { @MainActor in self.send(id, .flying) }
                } else if let i, cards[i].phase == .lifted {
                    cards[i].fraction = 1
                    send(line.id, .flying)
                }
            case .failed, .stopped, .leftOut:
                if let i, cards[i].phase == .lifted { send(line.id, .fallen) }
            case .waiting:
                break
            }
        }
        // A batch gone (reset, or another begun): cards of lines that no longer exist go.
        if lines.isEmpty, !cards.isEmpty { cards.removeAll() }
        if lines.isEmpty { gone.removeAll() }
    }

    /// Lines whose card has come and gone: never lifted twice.
    @ObservationIgnored private var gone: Set<Int> = []

    private func send(_ id: Int, _ phase: Card.Phase) {
        guard let i = cards.firstIndex(where: { $0.id == id }), cards[i].phase == .lifted else { return }
        gone.insert(id)
        cards[i].phase = phase
        let wait = phase == .flying ? Self.flight : Self.fall
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            self.cards.removeAll { $0.id == id }
            if phase == .flying { self.landed &+= 1 }
        }
    }
}

/// The cards over the develop page. Takes no clicks (the page says so where it lays this).
struct FilmLabExportFlight: View {
    /// The frame open on the page: its card is the page's own picture.
    let current: LibraryFrame.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A check's launch (`--filmlab-reduce-motion`) draws it as under the system's Reduce Motion, which is not a check's to set.
    static let calmCheck = CommandLine.arguments.contains("--filmlab-reduce-motion")
    private var calm: Bool { reduceMotion || Self.calmCheck }
    private var show: FilmLabExportShow { .shared }
    private var run: MacExportRun { .shared }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The batch's lines, followed from a view of its own so the cards alone are drawn again.
            Color.clear
                .onChange(of: run.lines) { _, lines in show.follow(lines, running: run.isRunning) }
            ForEach(show.cards) { card in
                FilmLabExportCard(card: card, viewer: FilmLabExportStage.shared.viewer, tray: FilmLabExportStage.shared.tray, calm: calm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// One frame's card: lifted over the viewer, then on its way to the tray, or fallen.
private struct FilmLabExportCard: View {
    let card: FilmLabExportShow.Card
    let viewer: CGRect
    let tray: CGRect
    let calm: Bool
    @Environment(FrameCatalog.self) private var library
    @Environment(AppServices.self) private var model
    @State private var shown = false

    var body: some View {
        if let kept = library.frame(card.frameID), viewer.width > 40, viewer.height > 40 {
            let frame = MacShownFrame.of(kept, model: model)
            let a = max(0.05, MacShownFrame.aspect(frame))
            // The card: the picture at a little under half the viewer.
            let room = CGSize(width: min(viewer.width * 0.46, 420), height: min(viewer.height * 0.46, 320))
            let size = room.width / room.height > a ? CGSize(width: room.height * a, height: room.height)
                                                    : CGSize(width: room.width, height: room.width / a)
            // Lifted: over the viewer's middle, a little up. Reduce Motion: smaller, in the viewer's corner, and still.
            let home = calm ? CGPoint(x: viewer.minX + 24 + size.width * 0.3, y: viewer.maxY - 24 - size.height * 0.3)
                            : CGPoint(x: viewer.midX, y: viewer.midY)
            let rest: CGFloat = calm ? 0.6 : 1
            let flying = card.phase == .flying && !calm && tray.width > 1
            let fallen = card.phase == .fallen
            let x = flying ? tray.midX : home.x
            let y = flying ? tray.midY : home.y - (shown && card.phase == .lifted && !calm ? 10 : 0)
            let scale: CGFloat = flying ? max(0.05, 24 / max(size.width, size.height)) : !shown ? rest * 0.94 : fallen ? rest * 0.92 : rest
            // The flight is seen all the way into the tray; Reduce Motion fades in place; a failure fades, greyed.
            let opacity: Double = !shown || fallen || (calm && card.phase == .flying) ? 0 : 1
            let lift = Animation.spring(response: 0.38, dampingFraction: 0.78)
            face(frame, size: size)
                .saturation(fallen ? 0 : 1)
                .scaleEffect(scale)
                .animation(flying ? .easeIn(duration: FilmLabExportShow.flight) : calm ? .easeOut(duration: 0.25) : lift, value: scale)
                .opacity(opacity)
                .animation(.easeOut(duration: fallen ? FilmLabExportShow.fall : 0.25), value: opacity)
                // Across slowly then quickly, and up a little before down: an arc into the tray.
                .offset(x: x - size.width / 2)
                .animation(.timingCurve(0.5, 0, 0.9, 0.65, duration: FilmLabExportShow.flight), value: x)
                .offset(y: y - size.height / 2)
                .animation(flying ? .timingCurve(0.4, -0.3, 0.75, 1, duration: FilmLabExportShow.flight) : lift, value: y)
                .onAppear { shown = true }
        }
    }

    private func face(_ frame: LibraryFrame, size: CGSize) -> some View {
        FrameView(frame: frame, pointSize: max(size.width, size.height), contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
            // The frame's own progress along the card's foot.
            .overlay(alignment: .bottomLeading) {
                if card.phase == .lifted {
                    Rectangle().fill(Theme.accent)
                        .frame(width: max(0, size.width * min(1, card.fraction)), height: 3)
                        .animation(.linear(duration: 0.12), value: card.fraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: 22, y: 12)
    }
}

// MARK: - the foot

/// The foot while a batch runs: the folder tray the cards land in, which picture of how many, its name, the bar.
struct FilmLabExportTray: View {
    private var run: MacExportRun { .shared }
    private var show: FilmLabExportShow { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                Image(systemName: "folder.fill")
                    .font(Theme.Font.ui(17, .medium))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.bounce.down, value: show.landed)
                    .frame(width: 38, height: 38)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if run.saved > 0 {
                            Text(verbatim: "\(run.saved)").font(Theme.Font.ui(10, .bold)).monospacedDigit()
                                .foregroundStyle(Theme.onSelection)
                                .padding(.horizontal, 4.5).frame(minWidth: 16, minHeight: 16)
                                .background(Theme.accent, in: Capsule())
                                .offset(x: 6, y: -6)
                                .contentTransition(.numericText())
                                .animation(.easeOut(duration: 0.2), value: run.saved)
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FilmLabExportStage.space)) } action: {
                        FilmLabExportStage.shared.tray = $0
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.stopping ? L("Stopping…") : run.isRunning ? L("Exporting \(run.countText)")
                         : run.saved == 1 ? L("1 photo exported") : L("\(run.saved) photos exported"))
                        .font(Theme.Font.ui(13, .semibold)).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1)
                    Text(run.current?.name ?? "")
                        .font(Theme.Font.ui(11.5)).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                Text(verbatim: "\(Int((run.fraction * 100).rounded())) %")
                    .font(Theme.Font.ui(12, .medium)).monospacedDigit().foregroundStyle(Theme.secondaryText)
            }
            // The batch's bar: the pictures ended and the share of the one under way.
            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.card)
                    Capsule().fill(Theme.accent)
                        .frame(width: max(4, bar.size.width * run.fraction))
                        .animation(.linear(duration: 0.15), value: run.fraction)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Exporting \(run.countText)"))
        .accessibilityValue("\(Int((run.fraction * 100).rounded())) %")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("filmlab.export.tray")
    }
}

/// The foot when a batch has ended: what was saved and where, or which pictures were not and why.
struct FilmLabExportDone: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var calm: Bool { reduceMotion || FilmLabExportFlight.calmCheck }
    private var run: MacExportRun { .shared }
    @State private var settled = false
    /// What came of the batch, kept as it was first shown: the line fades out after the run has been cleared.
    @State private var kept: Outcome?

    private struct Outcome {
        var saved: Int
        var problems: [MacExportRun.Line]
        var stopped: Bool
        var folder: URL?
    }

    var body: some View {
        let now = kept ?? Outcome(saved: run.saved, problems: run.problems, stopped: run.wasStopped, folder: run.folder)
        return content(now)
            .onAppear { if kept == nil { kept = now } }
    }

    private func content(_ o: Outcome) -> some View {
        let problems = o.problems
        let clean = problems.isEmpty && !o.stopped
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: clean ? "checkmark.circle.fill" : o.stopped && problems.isEmpty ? "stop.circle" : "exclamationmark.triangle.fill")
                    .font(Theme.Font.ui(22, .medium))
                    .foregroundStyle(clean ? Theme.labelGreen : problems.isEmpty ? Theme.secondaryText : Theme.danger)
                    // The check settles in; a problem is simply there.
                    .scaleEffect(clean && !calm && !settled ? 0.5 : 1)
                    .opacity(clean && !settled ? 0 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(o, clean: clean))
                        .font(Theme.Font.ui(13.5, .semibold)).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1)
                    if let folder = o.folder, o.saved > 0 {
                        Text(MacExportFolder.place(folder)).font(Theme.Font.ui(11.5)).foregroundStyle(Theme.dim)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 6)
                if let folder = o.folder, o.saved > 0 {
                    Button { UIApplication.shared.open(folder) } label: {
                        Text(L("Show in Finder")).font(Theme.Font.ui(12, .medium)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filmlab.export.reveal")
                }
            }
            ForEach(problems.prefix(4), id: \.id) { line in
                Text(line.name + Fmt.dot + L(shown: line.problem ?? ""))
                    .font(Theme.Font.ui(11.5)).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if problems.count > 4 {
                Text(L("and \(problems.count - 4) more")).font(Theme.Font.ui(11.5)).foregroundStyle(Theme.danger)
            }
        }
        .onAppear {
            withAnimation(calm ? .easeOut(duration: 0.2) : .spring(response: 0.36, dampingFraction: 0.6)) { settled = true }
        }
        // A clean batch's line goes by itself; one with something to read stays until the next export or a click.
        .task(id: clean) {
            guard clean else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, !run.isRunning else { return }
            withAnimation(.easeOut(duration: 0.25)) { run.reset() }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !clean { withAnimation(.easeOut(duration: 0.2)) { run.reset() } } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmlab.export.done")
    }

    private func title(_ o: Outcome, clean: Bool) -> String {
        let problems = o.problems.count
        if clean { return o.saved == 1 ? L("1 photo exported") : L("\(o.saved) photos exported") }
        if problems == 0 { return L("Stopped") + Fmt.dot + L("\(o.saved) saved") }
        return o.saved == 0 ? L("\(problems) not exported") : L("\(o.saved) saved") + Fmt.dot + L("\(problems) not exported")
    }
}
