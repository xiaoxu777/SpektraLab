//  FilmLabExportPreviewMotion.swift — one cached photograph, from the canvas into the post and back.
//
//  Geometry is captured at the endpoints. During the move only the picture's uniform scale/offset, the window's
//  scale/offset and opacity change. In particular the picture is never stretched to match a platform's crop.

import SwiftUI
import UIKit

enum FilmLabExportPreviewMotion {
    static let slow: Double = CommandLine.arguments.contains("--filmlab-motion-slow") ? 4 : 1
    static let calmCheck = CommandLine.arguments.contains("--filmlab-reduce-motion")
    static let duration: Double = 0.35 * slow
    static let fade: Double = 0.2 * slow
    static var move: Animation { .easeOut(duration: duration) }
    static var crossfade: Animation { .easeInOut(duration: fade) }

    // DevelopCanvas.fitSize(in:), including its Mac-point inset and rounding. This overlay is in that canvas's
    // own scene points, before the shell's interface scale. Export opens at fit; no viewport is created here.
    static func viewerRect(in whole: CGSize, aspect: CGFloat) -> CGRect {
        let inset = (12 * 10 / 9 / InterfaceScale.padTarget).rounded()
        let area = CGSize(width: max(whole.width - inset * 2, 1), height: max(whole.height - inset * 2, 1))
        let a = max(aspect, 0.0001)
        let size = area.width / max(area.height, 1) > a
            ? CGSize(width: (area.height * a).rounded(), height: area.height)
            : CGSize(width: area.width, height: (area.width / a).rounded())
        return CGRect(x: (whole.width - size.width) / 2, y: (whole.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

/// Also the identity of the screen's opacity transition. The hardware is outside this identity.
struct FilmLabExportPreviewChoice: Equatable {
    var kind: FilmLabExportPurpose.Kind
    var second: Bool
    var dark: Bool
    var border: Bool
    var id: String { "\(kind.rawValue)-\(second)-\(dark)-\(border)" }
    var purpose: FilmLabExportPurpose { FilmLabExportPurpose(kind: kind) }
}

struct FilmLabExportPreviewPhotoAnchor {
    let bounds: Anchor<CGRect>
    let radius: CGFloat
    let bottomRadius: CGFloat
}

struct FilmLabExportPreviewPhotoKey: PreferenceKey {
    static var defaultValue: FilmLabExportPreviewPhotoAnchor? { nil }
    static func reduce(value: inout FilmLabExportPreviewPhotoAnchor?, nextValue: () -> FilmLabExportPreviewPhotoAnchor?) {
        value = nextValue() ?? value
    }
}

/// Resolved inside the unscaled feed. Neither the phone's animated offset nor its scale can feed back into this.
struct FilmLabExportPreviewSlot: Equatable {
    let choice: String
    let rect: CGRect
    let radius: CGFloat
    let bottomRadius: CGFloat
}

/// An existing decoded image only. Unlike FramePicture/Layer2Picture this view has no task, decode or display-size
/// request. The same frozen pixels are used in the post during the move, so handing off cannot change rendition.
struct FilmLabExportPreviewPixels: View {
    let image: UIImage
    let crop: Geometry?
    let baseSize: CGSize

    var body: some View {
        if let crop {
            GeometryPicture(geometry: crop, imageSize: baseSize) { _ in picture }
        } else {
            picture
        }
    }

    private var picture: some View { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) }
}

struct FilmLabExportPreviewFlight {
    let pixels: FilmLabExportPreviewPixels
    let area: CGSize
    let start: CGRect
    let end: CGRect
    let endPictureScale: CGFloat
    let radius: CGFloat
    let bottomRadius: CGFloat

    init(pixels: FilmLabExportPreviewPixels, area: CGSize, start: CGRect, end: CGRect,
         shot: FilmLabPurposeShot, radius: CGFloat, bottomRadius: CGFloat) {
        self.pixels = pixels; self.area = area; self.start = start; self.end = end
        let file = end.width / max(end.height, 1) > shot.fileAspect
            ? CGSize(width: end.width, height: end.width / shot.fileAspect)
            : CGSize(width: end.height * shot.fileAspect, height: end.height)
        let pictureWidth = min(file.width, file.height * shot.aspect)
        endPictureScale = pictureWidth / max(start.width, 1)
        self.radius = radius; self.bottomRadius = bottomRadius
    }
}

/// A fixed-size plane and a separately transformed crop window. Crop/sheet changes therefore preserve the photo's
/// aspect, including when a square tile is the endpoint. The square part of the mask fades away to the post's corners.
struct FilmLabExportPreviewMovingPhoto: View {
    let flight: FilmLabExportPreviewFlight
    let progress: CGFloat

    var body: some View {
        let f = flight
        let x = f.start.midX + (f.end.midX - f.start.midX) * progress - f.area.width / 2
        let y = f.start.midY + (f.end.midY - f.start.midY) * progress - f.area.height / 2
        let sx = f.start.width / max(f.end.width, 1)
        let sy = f.start.height / max(f.end.height, 1)
        ZStack {
            Color.white
            f.pixels
                .frame(width: f.start.width, height: f.start.height)
                .scaleEffect(1 + (f.endPictureScale - 1) * progress)
                .offset(x: x, y: y)
        }
        .frame(width: f.area.width, height: f.area.height)
        .mask {
            ZStack {
                UnevenRoundedRectangle(topLeadingRadius: f.radius, bottomLeadingRadius: f.bottomRadius,
                                       bottomTrailingRadius: f.bottomRadius, topTrailingRadius: f.radius,
                                       style: .continuous)
                Rectangle().opacity(1 - progress)
            }
            .frame(width: f.end.width, height: f.end.height)
            .scaleEffect(x: sx + (1 - sx) * progress, y: sy + (1 - sy) * progress)
            .offset(x: x, y: y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(FilmLabExportPreviewMotion.move, value: progress)
    }
}
