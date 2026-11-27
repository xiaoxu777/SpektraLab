//  FilmLabExportSizeEstimate.swift — 普通版's approximate file sizes, without encoding or reading a file.

import Foundation

enum FilmLabExportSizeEstimate {
    // JPEG calibrated 2026-11-27 from real exports of two grainy film renderings (1.5–51 MP).
    // Downscaling smooths grain, so bits per pixel grow with resolution. Tune the calibration here;
    // content, grain and metadata vary, so the interface always says "about".
    private enum Calibration {
        static let jpegBaseBPP = 2.75
        static let jpegReferenceMP = 5.0
        static let jpegBPPPerDoubling = 0.58
        static let jpeg: [(quality: Int, factor: Double)] = [(1, 0.15), (80, 0.65), (85, 0.8), (90, 1), (100, 3.7)]
        static let heifRatio = 0.55
        static let lossless8BPP = 3.0 * 0.6 * 8
        static let tiff16BPP = 6.0 * 8
        static let headerBytes = 16_384
    }

    /// A formula only. TIFF in ExportRecipe is always 16-bit; PNG is 8-bit. The colour profile's small overhead
    /// is covered by the header, rather than pretending to predict compression from a colour space.
    static func estimatedBytes(outputPixels: Int, format: ExportRecipe.Format, quality: Int) -> Int {
        guard outputPixels > 0 else { return 0 }
        let bpp: Double
        switch format {
        case .jpeg, .heif:
            let q = quality.clamped(to: 1...100)
            let upper = Calibration.jpeg.firstIndex { $0.quality >= q } ?? (Calibration.jpeg.count - 1)
            let hi = Calibration.jpeg[upper], lo = Calibration.jpeg[max(0, upper - 1)]
            let t = hi.quality == lo.quality ? 0 : Double(q - lo.quality) / Double(hi.quality - lo.quality)
            let megapixels = Double(outputPixels) / 1_000_000
            let at90 = Calibration.jpegBaseBPP
                + Calibration.jpegBPPPerDoubling * max(0, log2(megapixels / Calibration.jpegReferenceMP))
            bpp = at90 * (lo.factor + t * (hi.factor - lo.factor)) * (format == .heif ? Calibration.heifRatio : 1)
        case .png: bpp = Calibration.lossless8BPP
        case .tiff: bpp = Calibration.tiff16BPP
        }
        return Int((Double(outputPixels) * bpp / 8).rounded()) + Calibration.headerBytes
    }

    /// Decimal file units. Round at the displayed precision, including the transition from 9.95 to 10 MB.
    static func sizeText(_ bytes: Int) -> String {
        if bytes < 1_000_000 {
            return "\(max(10, Int((Double(bytes) / 10_000).rounded()) * 10)) KB"
        }
        let mb = Double(bytes) / 1_000_000
        if (mb * 10).rounded() < 100 {
            return String(format: "%.1f MB", locale: Locale(identifier: "en_US_POSIX"), mb)
        }
        return "\(Int(mb.rounded())) MB"
    }

    /// The same IDs the footer's button exports. Unknown dimensions suppress the estimate for the whole batch,
    /// rather than presenting a partial total. Each frame gets its own crop, rotation, cap and optional border sheet.
    @MainActor
    static func summary(_ recipe: ExportRecipe, frameIDs: [LibraryFrame.ID], model: AppServices,
                        borderFits: ClosedRange<Double>?) -> String {
        guard !frameIDs.isEmpty else { return recipe.format.title }
        var total = 0
        for id in frameIDs {
            guard let frame = model.library.frame(id), var size = outputSize(frame, recipe: recipe, model: model) else {
                return recipe.format.title
            }
            if let borderFits, let layout = FilmLabExportPurposeBorder.layout(width: size.width, height: size.height,
                                                                            fits: borderFits, size: recipe.size) {
                size = layout.sheet
            }
            total += estimatedBytes(outputPixels: size.width * size.height, format: recipe.format, quality: recipe.quality)
        }
        let size = sizeText(total)
        let estimate = frameIDs.count > 1 ? L("\(frameIDs.count) photos, about \(size)") : L("about \(size)")
        return recipe.format.title + Fmt.dot + estimate
    }

    /// ExportService.prepared's geometry inputs, passed to the export's own pure planner. Do not call
    /// ExportService.outputSize here: preparing its source URL also probes the disk. No decode or source URL is
    /// needed to plan pixels. Film layout and the purpose's sheet are the same arithmetic the export uses.
    @MainActor
    private static func outputSize(_ frame: LibraryFrame, recipe: ExportRecipe, model: AppServices) -> PixelSize? {
        let fromPreview = !frame.original.isAvailable
        let source = fromPreview ? frame.previewSize : frame.originalSize
        guard source.width > 0, source.height > 0 else { return nil }
        let edit = frame.edit
        let formatMM = frame.isPair ? edit.params.filmFormatMM
            : edit.wireFilmFormatMM(photo: frame.originalSize, cropIsFrame: model.settings.cropRemapsFrame)
        var ask = ExportPlan.Ask(source: source, photo: edit.geometry, filmFormatMM: formatMM,
                                 size: fromPreview ? .preview : recipe.size,
                                 capMegapixels: DevicePolicy.current.developCapMegapixels)
        if !frame.isPair { ask.printCrop = edit.printCrop }
        let film = model.exportFilm(frame)
        ask.film = film?.ask
        return ExportPlan.make(ask, canvas: { film?.canvas($0) }).output
    }
}
