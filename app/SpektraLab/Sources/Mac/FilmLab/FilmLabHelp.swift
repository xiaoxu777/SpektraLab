//  FilmLabHelp.swift — a small "?" beside a section's name, and what it opens.
//
//  The owner, 2026-11-25: "放大机是做什么的？我会有疑惑，最好在这个功能旁边加一个小问号，用一些小动画来演示这个功能的意义。"
//  `FilmLabHelpButton` is that question mark for any section: a title, one or two plain sentences, an optional line
//  for when the section does nothing, and a small drawing that moves (the section's own view, e.g.
//  `FilmLabEnlargerDemo`). It opens a popover beside the button and changes nothing. Only 放大机 has one so far.
//
//  A check's launch: `--filmlab-help <id>` opens the button with that id two and a half seconds after it appears.

import SwiftUI

struct FilmLabHelpButton<Demo: View>: View {
    /// Which help this is (`--filmlab-help <id>`, and the button's accessibility identifier).
    let id: String
    let title: String
    let text: String
    /// When the section does nothing, said last and smaller. Nil for none.
    var note: String? = nil
    @ViewBuilder var demo: () -> Demo

    @State private var shown = false
    @State private var hovering = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: shown ? "questionmark.circle.fill" : "questionmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(shown ? Theme.accent : hovering ? Theme.text : Theme.dim)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L("What is this?"))
        .accessibilityLabel(L("What is this?") + " " + title)
        .accessibilityIdentifier("filmlab.help." + id)
        .onAppear {
            guard FilmLabCheckArgs.value("--filmlab-help") == id, !FilmLabHelpCheck.opened else { return }
            FilmLabHelpCheck.opened = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { shown = true }
        }
        // Beside the button, over the picture (the arrow on the popover's leading edge).
        .popover(isPresented: $shown, arrowEdge: .leading) {
            FilmLabHelpPopover(title: title, text: text, note: note, demo: demo)
        }
    }
}

/// The card as a popover's content, at the Mac-point scale, and as large as the card is.
///
/// A popover on the Mac is a window sized by its content, and `interfaceScaled` is a reader, which has no size of its
/// own: left to it, the popover came up 79 points square with the card cut off inside (seen 2026-11-25). So the card's
/// height is measured where it is drawn, and the popover is given the card's size times the scale.
private struct FilmLabHelpPopover<Demo: View>: View {
    let title: String
    let text: String
    let note: String?
    @ViewBuilder var demo: () -> Demo
    /// The card's height in its own points, once drawn; a likely one until then.
    @State private var height: CGFloat = MacMetric.pt(340)

    var body: some View {
        let f = InterfaceScale.current(.macPoints)
        FilmLabHelpCard(title: title, text: text, note: note, demo: demo)
            .fixedSize(horizontal: true, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height = $0 }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .interfaceScaled(.macPoints)
            .frame(width: (FilmLabHelpCard<Demo>.width + 2 * FilmLabHelpCard<Demo>.inset) * f, height: height * f)
            .background(Theme.popover)
            .appColorScheme()
    }
}

/// `--filmlab-help` has opened its popover once this launch (the column is made again as the page changes).
@MainActor
private enum FilmLabHelpCheck {
    static var opened = false
}

/// The popover: the drawing, the title, the words.
struct FilmLabHelpCard<Demo: View>: View {
    let title: String
    let text: String
    var note: String? = nil
    @ViewBuilder var demo: () -> Demo

    static var width: CGFloat { MacMetric.pt(300) }
    static var inset: CGFloat { MacMetric.pt(14) }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMetric.pt(10)) {
            demo()
                .frame(width: Self.width, height: MacMetric.pt(188))
                .background(Theme.wall.opacity(0.45), in: RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: MacMetric.pt(8), style: .continuous))
                .accessibilityHidden(true)
            Text(title).font(MacMetric.font(13.5, .bold)).foregroundStyle(Theme.text)
            Text(text).font(MacMetric.font(12.5)).foregroundStyle(Theme.secondaryText)
                .lineSpacing(MacMetric.pt(3))
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note).font(MacMetric.font(11.5)).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .padding(Self.inset)
        .background(Theme.popover)
    }
}
