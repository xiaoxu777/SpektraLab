#!/usr/bin/swift
// Finder positions and this artwork share a 660 × 420 point, top-left coordinate system.
// Give each bitmap its logical size so cathidpicheck recognises the 2x representation.
import AppKit
import CoreGraphics

let canvas = NSSize(width: 660, height: 420)

func colour(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func centredText(_ text: String, y: CGFloat, font: NSFont,
                 colour: NSColor, tracking: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: colour, .kern: tracking
    ]
    let string = text as NSString
    let size = string.size(withAttributes: attributes)
    string.draw(at: NSPoint(x: (canvas.width - size.width) / 2, y: y),
                withAttributes: attributes)
}

func render(to path: String, scale: Int) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil, width: 660 * scale, height: 420 * scale, bitsPerComponent: 8,
        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "FilmLabBackground", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot allocate background bitmap"])
    }
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.translateBy(x: 0, y: canvas.height)
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

    let ground = CGGradient(colorsSpace: space,
                            colors: [colour(0x131416).cgColor, colour(0x1B1C1F).cgColor] as CFArray,
                            locations: [0, 1])!
    context.drawLinearGradient(ground, start: .zero,
                               end: CGPoint(x: 0, y: 420), options: [])
    let glow = CGGradient(colorsSpace: space,
                          colors: [colour(0xE8A33D, alpha: 0.13).cgColor,
                                   colour(0xE8A33D, alpha: 0).cgColor] as CFArray,
                          locations: [0, 1])!
    let appCentre = CGPoint(x: 180, y: 215)
    context.drawRadialGradient(glow, startCenter: appCentre, startRadius: 0,
                               endCenter: appCentre, endRadius: 145, options: [])

    let system = NSFont.systemFont(ofSize: 48, weight: .semibold)
    let rounded = system.fontDescriptor.withDesign(.rounded)
        .flatMap { NSFont(descriptor: $0, size: 48) } ?? system
    centredText("FilmLab", y: 55, font: rounded, colour: colour(0xECEAE4), tracking: -1.2)
    context.setStrokeColor(colour(0xECEAE4, alpha: 0.24).cgColor)
    context.setLineWidth(0.5)
    context.move(to: CGPoint(x: 306, y: 125))
    context.addLine(to: CGPoint(x: 354, y: 125))
    context.strokePath()

    // Leave room around both 112-point Finder icons; only the arrow occupies the gap.
    context.setStrokeColor(colour(0xE8A33D, alpha: 0.85).cgColor)
    context.setLineWidth(1.4)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 266, y: 215))
    context.addLine(to: CGPoint(x: 394, y: 215))
    context.move(to: CGPoint(x: 387, y: 209))
    context.addLine(to: CGPoint(x: 394, y: 215))
    context.addLine(to: CGPoint(x: 387, y: 221))
    context.strokePath()
    centredText("拖到 Applications 安装", y: 244,
                font: .systemFont(ofSize: 11), colour: colour(0x999A9D))
    // Finder draws the two names in near-black over a picture, whatever the appearance: a light plate under each
    // keeps them readable on this dark ground (names measured at y 288, centred under the icons at x 180 and 480).
    context.setFillColor(colour(0xECEAE4, alpha: 0.92).cgColor)
    for (centre, width) in [(CGFloat(180), CGFloat(72)), (CGFloat(480), CGFloat(102))] {
        let plate = CGRect(x: centre - width / 2, y: 278, width: width, height: 20)
        context.addPath(CGPath(roundedRect: plate, cornerWidth: 6, cornerHeight: 6, transform: nil))
    }
    context.fillPath()
    // Kept above y 370: a Finder that shows its tab bar has about 380 points of the 420 in view.
    centredText("ericxu", y: 344, font: .systemFont(ofSize: 11),
                colour: colour(0xECEAE4, alpha: 0.28), tracking: 2.8)

    guard let image = context.makeImage() else {
        throw NSError(domain: "FilmLabBackground", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot finish background bitmap"])
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    bitmap.size = canvas
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "FilmLabBackground", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot encode background PNG"])
    }
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
}

let arguments = CommandLine.arguments
guard (2...3).contains(arguments.count) else {
    fputs("Usage: swift filmlab_dmg_background.swift <out.png> [<out@2x.png>]\n", stderr)
    exit(1)
}
do {
    try render(to: arguments[1], scale: 1)
    if arguments.count == 3 { try render(to: arguments[2], scale: 2) }
} catch {
    fputs("FilmLab background: \(error.localizedDescription)\n", stderr)
    exit(1)
}
