//  FilmLabPersonalizeSignature.swift — a small pointer pad. Width follows speed, not pressure; the pad and the
//  transparent PNG draw the same captured strokes. The PNG goes through the ordinary watermark library.

import SwiftUI
import UIKit

struct FilmLabSignatureSheet: View {
    let use: @MainActor (Data) async -> String?
    @Environment(\.dismiss) private var dismiss
    private struct Dot { var point: CGPoint; var width: CGFloat }
    @State private var strokes: [[Dot]] = []
    @State private var stroke: [Dot] = []
    @State private var lastTime: TimeInterval?
    @State private var saving = false
    @State private var note: String?
    private let pad = CGSize(width: 460, height: 200)

    var body: some View {
        if #available(iOS 18.0, macCatalyst 18.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Signature")).font(Theme.Font.ui(18, .semibold)).foregroundStyle(Theme.text)
            Canvas { context, _ in
                context.withCGContext { Self.draw(strokes + (stroke.isEmpty ? [] : [stroke]), in: $0) }
            }
            .frame(maxWidth: .infinity).frame(height: pad.height)
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard !saving else { return }
                let p = CGPoint(x: min(max(value.location.x, 6), pad.width - 6),
                                y: min(max(value.location.y, 6), pad.height - 6))
                let now = value.time.timeIntervalSinceReferenceDate
                var width: CGFloat = 3.2
                if let previous = stroke.last, let time = lastTime {
                    let distance = hypot(p.x - previous.point.x, p.y - previous.point.y)
                    guard distance >= 0.4 else { return }
                    let speed = distance / max(0.005, now - time)
                    let target = 3.2 * (1.3 - 0.6 * min(1, speed / 600)) // ±30%, slower is thicker.
                    width = previous.width * 0.8 + target * 0.2
                }
                stroke.append(Dot(point: p, width: width)); lastTime = now
            }.onEnded { _ in
                if !stroke.isEmpty { strokes.append(stroke) }
                stroke = []; lastTime = nil
            })
            .accessibilityLabel(L("Signature"))
            .accessibilityIdentifier("filmlab.personalize.signature.pad")
            if let note {
                Text(note).font(Theme.Font.ui(12)).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button(L("Clear")) { strokes = []; stroke = []; lastTime = nil; note = nil }
                    .buttonStyle(FilmLabPanelButtonStyle()).disabled(saving)
                Spacer()
                Button(L("Cancel")) { dismiss() }
                    .buttonStyle(FilmLabPanelButtonStyle()).keyboardShortcut(.cancelAction).disabled(saving)
                Button(L("Use")) {
                    guard let data = png() else { return }
                    saving = true
                    Task { @MainActor in
                        note = await use(data)
                        saving = false
                        if note == nil { dismiss() }
                    }
                }
                .buttonStyle(FilmLabPanelButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
                .disabled(saving || strokes.isEmpty || !stroke.isEmpty)
            }
        }
        .frame(width: pad.width).fixedSize(horizontal: false, vertical: true)
        .padding(24).background(Theme.background)
        .interactiveDismissDisabled(saving)
        .onAppear { seedCheckStrokes() }
    }

    private func seedCheckStrokes() {
        guard FilmLabPersonalizeCheck.signatureDemo, FilmLabPersonalizeCheck.consume(.demo) else { return }
        let lines: [[CGPoint]] = [
            [CGPoint(x: 60, y: 125), CGPoint(x: 85, y: 58), CGPoint(x: 108, y: 130),
             CGPoint(x: 81, y: 102), CGPoint(x: 132, y: 92), CGPoint(x: 154, y: 120),
             CGPoint(x: 177, y: 85), CGPoint(x: 169, y: 128), CGPoint(x: 206, y: 100)],
            [CGPoint(x: 210, y: 123), CGPoint(x: 244, y: 61), CGPoint(x: 227, y: 122),
             CGPoint(x: 264, y: 91), CGPoint(x: 284, y: 125), CGPoint(x: 310, y: 86),
             CGPoint(x: 303, y: 128), CGPoint(x: 346, y: 105), CGPoint(x: 392, y: 116)],
            [CGPoint(x: 96, y: 155), CGPoint(x: 180, y: 147), CGPoint(x: 278, y: 145), CGPoint(x: 407, y: 137)]
        ]
        strokes = lines.map { line in
            line.enumerated().map { Dot(point: $0.element, width: $0.offset % 3 == 0 ? 3.6 : 2.4) }
        }
    }

    /// Midpoints are the quadratic endpoints; each captured point is their control. Adjacent tangents agree,
    /// rounding the sampled corners. Both the live pad and PNG call this exact pass, with round caps/joins.
    private static func draw(_ strokes: [[Dot]], in ctx: CGContext) {
        ctx.setStrokeColor(UIColor.white.cgColor); ctx.setFillColor(UIColor.white.cgColor)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.first, let last = stroke.last else { continue }
            ctx.fillEllipse(in: CGRect(x: first.point.x - first.width / 2, y: first.point.y - first.width / 2,
                                      width: first.width, height: first.width))
            var start = first.point, width = first.width
            for i in 1..<stroke.count {
                let previous = stroke[i - 1], dot = stroke[i]
                let end = CGPoint(x: (previous.point.x + dot.point.x) / 2, y: (previous.point.y + dot.point.y) / 2)
                let nextWidth = (previous.width + dot.width) / 2
                ctx.setLineWidth((width + nextWidth) / 2)
                ctx.move(to: start); ctx.addQuadCurve(to: end, control: previous.point); ctx.strokePath()
                start = end; width = nextWidth
            }
            ctx.setLineWidth((width + last.width) / 2)
            ctx.move(to: start); ctx.addQuadCurve(to: last.point, control: last.point); ctx.strokePath()
        }
    }

    private func png() -> Data? {
        var bounds = CGRect.null
        for dot in strokes.joined() {
            // Include the widest adjacent segment's round cap, then leave breathing room around the ink.
            bounds = bounds.union(CGRect(x: dot.point.x - 3, y: dot.point.y - 3, width: 6, height: 6))
        }
        guard !bounds.isNull else { return nil }
        let crop = bounds.insetBy(dx: -12, dy: -12).integral
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2; format.opaque = false; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: crop.size, format: format).pngData { renderer in
            renderer.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
            Self.draw(strokes, in: renderer.cgContext)
        }
    }
}
