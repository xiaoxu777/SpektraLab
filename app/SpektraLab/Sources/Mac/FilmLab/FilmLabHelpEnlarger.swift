//  FilmLabHelpEnlarger.swift — what 放大机 is, drawn: a lamp, the negative under it, its light falling on the paper.
//
//  The drawing in 放大机's "?" (`FilmLabHelpButton`, `EnlargerGroup`). The enlarger is the darkroom's second exposure:
//  light through the developed negative onto the paper, which becomes the print. Its sliders are that exposure's —
//  亮度 is how much light the paper gets (a lighter or darker print of the same negative), 黄 and 品红 are the head's
//  filters (the print's colour cast), 预闪 a little plain light on the paper first (`EnlargerGroup.swift`).
//
//  The loop is four seconds: for two a 亮度 slider goes right and left and the print goes lighter and darker with it,
//  for two a 黄 · 品红 slider does and the print goes cooler and warmer. Both are sines of the clock, so the loop has no
//  seam and keeps no state. Reduce Motion (or `--filmlab-reduce-motion`): the still picture, both sliders at rest.

import SwiftUI

struct FilmLabEnlargerDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var still: Bool { reduce || FilmLabModeMotion.calmCheck }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { clock in
            let t = still ? 0 : clock.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4)
            drawing(State(seconds: t, still: still))
        }
    }

    /// Where the loop is: the two sliders (−1…1) and how much each is the one being moved (0…1).
    private struct State {
        var light = 0.0, cast = 0.0
        var lightOn = 0.6, castOn = 0.6

        init(seconds t: Double, still: Bool) {
            guard !still else { return }
            let first = t < 2
            let u = (first ? t : t - 2) / 2
            let swing = sin(u * 2 * .pi)
            // Up to full strength a little after the slider starts, and down before it hands over.
            let on = min(max(sin(u * .pi) * 3, 0), 1)
            light = first ? swing : 0
            cast = first ? 0 : swing
            lightOn = first ? on : 0
            castOn = first ? 0 : on
        }
    }

    private func drawing(_ s: State) -> some View {
        // Laid out on a 300 × 188 sheet of Mac points.
        let k = MacMetric.pt(100) / 100
        let cx: CGFloat = 78
        return ZStack(alignment: .topLeading) {
            // The lamp and its light down to the negative.
            Cone(top: 18, bottom: 44).fill(light(s, from: 0.5, to: 0.28))
                .frame(width: 44 * k, height: 12 * k).position(x: cx * k, y: 26 * k)
            RoundedRectangle(cornerRadius: 4 * k, style: .continuous).fill(Color(hex: 0x3F4147))
                .frame(width: 46 * k, height: 14 * k).position(x: cx * k, y: 13 * k)
            Capsule().fill(Color(hex: 0xFFE2A8)).frame(width: 22 * k, height: 4 * k)
                .shadow(color: Theme.accent.opacity(0.9), radius: 5 * k)
                .position(x: cx * k, y: 19 * k)
            // The negative: the picture the other way round, on its orange base.
            RoundedRectangle(cornerRadius: 2 * k, style: .continuous).fill(Color(hex: 0x4A2B14))
                .frame(width: 52 * k, height: 34 * k).position(x: cx * k, y: 49 * k)
            FilmLabDemoScene().colorInvert().colorMultiply(Color(hex: 0xF2A766))
                .frame(width: 42 * k, height: 28 * k).position(x: cx * k, y: 49 * k)
            // Its light, spreading down to the paper.
            Cone(top: 42, bottom: 120).fill(light(s, from: 0.36, to: 0.1))
                .frame(width: 120 * k, height: 34 * k).position(x: cx * k, y: 83 * k)
            // The paper, and the print on it.
            RoundedRectangle(cornerRadius: 2 * k, style: .continuous).fill(Color(hex: 0xF1EEE7))
                .frame(width: 128 * k, height: 84 * k).position(x: cx * k, y: 142 * k)
            FilmLabDemoScene()
                .brightness(s.light * 0.17)
                .colorMultiply(Self.cast(s.cast))
                .frame(width: 118 * k, height: 74 * k).position(x: cx * k, y: 142 * k)

            label(L("Lamp"), k).position(x: (cx + 23 + 14) * k, y: 13 * k)
            label(L("Negative", as: "enlarger help"), k).position(x: (cx + 26 + 18) * k, y: 49 * k)
            label(L("Paper"), k).position(x: (cx + 64 + 18) * k, y: 176 * k)

            // The two sliders the loop moves.
            VStack(alignment: .leading, spacing: 16 * k) {
                slider(L("Brightness"), value: s.light, on: s.lightOn, tint: nil, k)
                slider(L("Yellow") + " · " + L("Magenta"), value: s.cast, on: s.castOn,
                       tint: (Color(hex: 0xE3C25A), Color(hex: 0x5F86C9)), k)
            }
            .frame(width: 104 * k, alignment: .leading)
            .position(x: 236 * k, y: 80 * k)
        }
        .frame(width: 300 * k, height: 188 * k, alignment: .topLeading)
    }

    /// The beam's fill: brighter with 亮度, and faintly the colour the print is taking.
    private func light(_ s: State, from top: Double, to bottom: Double) -> LinearGradient {
        let strength = 0.72 + 0.28 * s.light
        let colour = Self.cast(s.cast * 0.8, base: (1.0, 0.93, 0.80))
        return LinearGradient(colors: [colour.opacity(top * strength), colour.opacity(bottom * strength)],
                              startPoint: .top, endPoint: .bottom)
    }

    /// What the filters do to the print: towards −1 warmer (yellow), towards +1 cooler (blue), as the app's 黄 slider.
    private static func cast(_ c: Double, base: (Double, Double, Double) = (1, 1, 1)) -> Color {
        let warm = max(-c, 0), cool = max(c, 0)
        return Color(.sRGB, red: base.0 * (1 - 0.20 * cool), green: base.1 * (1 - 0.05 * warm - 0.08 * cool),
                     blue: base.2 * (1 - 0.26 * warm), opacity: 1)
    }

    private func label(_ text: String, _ k: CGFloat) -> some View {
        Text(text).font(MacMetric.font(10.5)).foregroundStyle(Theme.dim).fixedSize()
    }

    private func slider(_ name: String, value: Double, on: Double, tint: (Color, Color)?, _ k: CGFloat) -> some View {
        let width = 104 * k, knob = 11 * k
        let x = (width - knob) / 2 * CGFloat(value)
        return VStack(alignment: .leading, spacing: 7 * k) {
            Text(name).font(MacMetric.font(11, .medium)).foregroundStyle(Theme.text).fixedSize()
            ZStack {
                if let tint {
                    Capsule().fill(LinearGradient(colors: [tint.0, tint.1], startPoint: .leading, endPoint: .trailing))
                        .frame(width: width, height: 3 * k)
                } else {
                    Capsule().fill(Color(hex: 0x4A4C52)).frame(width: width, height: 3 * k)
                    // From the rest in the middle out to the knob, as the app's sliders fill.
                    Capsule().fill(Theme.accent).frame(width: abs(x), height: 3 * k).offset(x: x / 2)
                }
                Circle().fill(Color.white).frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.45), radius: 1.5 * k, y: 0.5 * k)
                    .offset(x: x)
            }
            .frame(width: width, height: knob)
        }
        .opacity(0.38 + 0.62 * on)
    }

    /// The beam between two widths, as wide as its frame at the wider.
    private struct Cone: Shape {
        let top: CGFloat, bottom: CGFloat
        func path(in r: CGRect) -> Path {
            let wide = max(top, bottom, 1)
            let a = r.width * top / wide, b = r.width * bottom / wide
            var p = Path()
            p.move(to: CGPoint(x: r.midX - a / 2, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX + a / 2, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX + b / 2, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX - b / 2, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }
}

/// The small landscape the help drawings print: a sky, a low sun, two ridges. Any size.
struct FilmLabDemoScene: View {
    var body: some View {
        GeometryReader { room in
            let w = room.size.width, h = room.size.height
            ZStack {
                LinearGradient(colors: [Color(hex: 0xEAC9A2), Color(hex: 0xC2B6AB), Color(hex: 0x93A5B1)],
                               startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(hex: 0xF6D6A8)).frame(width: h * 0.34, height: h * 0.34)
                    .position(x: w * 0.68, y: h * 0.36)
                Ridge(left: 0.60, peak: 0.44, right: 0.66).fill(Color(hex: 0x7391A6))
                Ridge(left: 0.86, peak: 0.70, right: 0.76).fill(Color(hex: 0x495B6B))
            }
            .frame(width: w, height: h)
            .clipped()
        }
    }

    /// A ridge across the frame: its height at the left edge, at its crest a third in, and at the right edge (0 top … 1 bottom).
    private struct Ridge: Shape {
        let left: CGFloat, peak: CGFloat, right: CGFloat
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * left))
            p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.55, y: r.minY + r.height * (peak + right) / 2),
                           control: CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * (peak - 0.08)))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * right),
                           control: CGPoint(x: r.minX + r.width * 0.8, y: r.minY + r.height * (right - 0.1)))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }
}
