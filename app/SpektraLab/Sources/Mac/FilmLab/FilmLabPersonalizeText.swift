//  FilmLabPersonalizeText.swift — text recipes and the one handwriting rasteriser. A recipe is editing metadata;
//  its PNG remains the source of truth for every viewer and exporter, even when a font later goes missing.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FilmLabTextStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case print, hand
    var label: String { self == .print ? L("Print", as: "watermark text style") : L("Handwritten") }
}

struct FilmLabTextRecipe: Codable, Equatable, Sendable {
    var text: String
    var style: FilmLabTextStyle
    var postScriptName: String?
}

enum FilmLabHandwriting {
    struct Face: Identifiable, Sendable {
        let id: String                    // Persist the PostScript name, never its translated label.
        let labelKey: String
        let joined: Bool
        var label: String { L(shown: labelKey) }
    }

    static let faces: [Face] = [
        Face(id: "HannotateSC-W5", labelKey: "Hannotate", joined: false),
        Face(id: "HanziPenSC-W3", labelKey: "HanziPen", joined: false),
        Face(id: "STXingkaiSC-Light", labelKey: "Xingkai", joined: false),
        Face(id: "DFWaWaSC-W5", labelKey: "Wawati", joined: false),
        Face(id: "SnellRoundhand", labelKey: "Snell Roundhand", joined: true),
        Face(id: "BradleyHandITCTT-Bold", labelKey: "Bradley Hand", joined: false),
        Face(id: "SavoyeLetPlain", labelKey: "Savoye", joined: true)
    ]

    /// CoreText silently substitutes Helvetica for an unavailable name. A matching identity AND full UTF-16
    /// coverage are required: otherwise a Latin script would advertise a Chinese sample drawn by another font.
    static func font(_ face: Face, text: String, points: CGFloat) -> CTFont? {
        let font = CTFontCreateWithName(face.id as CFString, points, nil)
        guard CTFontCopyPostScriptName(font) as String == face.id else { return nil }
        let chars = Array(text.utf16)
        guard !chars.isEmpty else { return font }
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        let covers = chars.withUnsafeBufferPointer { c in
            glyphs.withUnsafeMutableBufferPointer { g in
                CTFontGetGlyphsForCharacters(font, c.baseAddress!, g.baseAddress!, chars.count)
            }
        }
        return covers ? font : nil
    }

    static func available(for text: String) -> [Face] { faces.filter { font($0, text: text, points: 24) != nil } }

    private static func line(_ words: String, font: CTFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: words, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ]))
    }

    /// Full line shaping comes first. Glyphs sharing a composed-character cluster keep one transform; ligatures
    /// retain CoreText's glyph and advance. Connected scripts retain every join and get only a whole-line tilt.
    private static func outline(_ words: String, face: Face, points: CGFloat, seed: UUID) -> CGPath? {
        guard let font = font(face, text: words, points: points) else { return nil }
        let shaped = line(words, font: font)
        let result = CGMutablePath(), source = words as NSString
        var random = Random(seed)
        for run in CTLineGetGlyphRuns(shaped) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            var start = 0
            while start < count {
                func cluster(_ index: Int) -> Int {
                    let i = indices[index]
                    return i >= 0 && i < source.length ? source.rangeOfComposedCharacterSequence(at: i).location : i
                }
                let key = cluster(start)
                var end = start + 1
                while end < count, cluster(end) == key { end += 1 }
                let path = CGMutablePath()
                for i in start..<end {
                    if let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                        path.addPath(glyph, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
                    }
                }
                let origin = positions[start]
                let dy = face.joined ? 0 : random.signed() * points * 0.03
                let angle = face.joined ? 0 : random.signed() * 1.2 * .pi / 180
                let scale = face.joined ? 1 : 1 + random.signed() * 0.02
                let transform = CGAffineTransform(translationX: origin.x, y: origin.y + dy)
                    .rotated(by: angle).scaledBy(x: scale, y: scale).translatedBy(x: -origin.x, y: -origin.y)
                result.addPath(path, transform: transform)
                start = end
            }
        }
        if face.joined {
            let tilted = CGMutablePath()
            tilted.addPath(result, transform: CGAffineTransform(rotationAngle: random.signed() * 0.8 * .pi / 180))
            return tilted
        }
        return result
    }

    /// The printed path starts at 180 points, scale 1, and shrinks at 7000 px. Use that same density and budget;
    /// real (already jittered) outline bounds also include swashes, descenders and the whole-line tilt.
    static func image(_ words: String, face: Face, seed: UUID, points: CGFloat = 180,
                      maxWidth: CGFloat = 7000, maxHeight: CGFloat = 8000) -> CGImage? {
        var points = points
        for _ in 0..<12 {
            guard let path = outline(words, face: face, points: points, seed: seed) else { return nil }
            let bounds = path.boundingBoxOfPath
            guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
            let pad = max(4, (points * 0.18).rounded())
            let w = Int(ceil(bounds.width + pad * 2)), h = Int(ceil(bounds.height + pad * 2))
            if CGFloat(w) > maxWidth || CGFloat(h) > maxHeight { points *= 0.7; continue }
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  let bytes = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
            ctx.translateBy(x: pad - bounds.minX, y: pad - bounds.minY)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.addPath(path); ctx.fillPath()
            let salt = Random(seed).state
            for y in 0..<h {
                for x in 0..<w {
                    let i = y * ctx.bytesPerRow + x * 4
                    guard bytes[i + 3] > 0 else { continue }
                    // Noise lives in em coordinates, so changing raster density does not change the ink pattern.
                    let u = (CGFloat(x) + bounds.minX - pad) / points
                    let v = (CGFloat(y) - bounds.maxY - pad) / points
                    let low = smoothNoise(u * 1.5, v * 1.5, salt: salt)
                    let fine = noise(Int(floor(u * 180)), Int(floor(v * 180)), salt: salt ^ 0xa0761d6478bd642f) - 0.5
                    let ink = min(1, max(0.82, 0.82 + 0.18 * low + 0.02 * fine))
                    let alpha = UInt8((Double(bytes[i + 3]) * ink).rounded())
                    // White premultiplied RGBA: texture is alpha, surviving WatermarkFill's colour replacement.
                    bytes[i] = alpha; bytes[i + 1] = alpha; bytes[i + 2] = alpha; bytes[i + 3] = alpha
                }
            }
            return ctx.makeImage()
        }
        return nil
    }

    static func png(_ words: String, face: Face, seed: UUID) -> Data? {
        guard let image = image(String(words.prefix(80)), face: face, seed: seed) else { return nil }
        let data = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(writer, image, nil)
        return CGImageDestinationFinalize(writer) ? data as Data : nil
    }

    /// Keep the entire line, scaling down from 24 pt to fit its real outline (including swashes and tilt).
    /// Images do not have Text's minimumScaleFactor: fitting here also keeps their tops/bottoms inside the tile.
    static func sample(_ words: String, face: Face, seed: UUID, width: CGFloat) -> CGImage? {
        guard let path = outline(words, face: face, points: 24, seed: seed) else { return nil }
        let bounds = path.boundingBoxOfPath
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        let fit = min(1, max(1, width - 10) / bounds.width, 58 / bounds.height)
        return image(words, face: face, seed: seed, points: 24 * fit, maxWidth: width, maxHeight: 68)
    }

    /// UUID bytes -> FNV-1a -> SplitMix64. No process-randomised Hasher, global RNG, time or display scale.
    struct Random {
        var state: UInt64
        init(_ id: UUID) {
            var bytes = id.uuid
            state = withUnsafeBytes(of: &bytes) { $0.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 } }
        }
        mutating func signed() -> CGFloat {
            state &+= 0x9e3779b97f4a7c15
            return CGFloat(Double(mix(state) >> 11) / 9007199254740992.0 * 2 - 1)
        }
    }
    private static func mix(_ n: UInt64) -> UInt64 {
        var z = n
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    private static func noise(_ x: Int, _ y: Int, salt: UInt64) -> Double {
        let n = salt ^ (UInt64(bitPattern: Int64(x)) &* 0x9e3779b97f4a7c15) ^ (UInt64(bitPattern: Int64(y)) &* 0xd1b54a32d192ed03)
        return Double(mix(n) >> 11) / 9007199254740992.0
    }
    private static func smoothNoise(_ x: CGFloat, _ y: CGFloat, salt: UInt64) -> Double {
        let ix = Int(floor(x)), iy = Int(floor(y))
        let fx = Double(x - floor(x)), fy = Double(y - floor(y))
        let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
        let a = noise(ix, iy, salt: salt) * (1 - u) + noise(ix + 1, iy, salt: salt) * u
        let b = noise(ix, iy + 1, salt: salt) * (1 - u) + noise(ix + 1, iy + 1, salt: salt) * u
        return a * (1 - v) + b * v
    }
}
