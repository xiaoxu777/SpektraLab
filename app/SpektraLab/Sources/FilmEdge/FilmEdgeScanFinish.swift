//  FilmEdgeScanFinish.swift — one scan finish over the engine's encoded ProPhoto pixels.
//
//  Run before the destination transform, Edit's pass and the finished watermarks, including before
//  a full render is kept. The image is deliberately untagged inside CI: the toe's 0.12 and the
//  glow source's 0.55…0.85 are encoded working-space values, not scene-linear exposures. CI
//  must not silently linearise one destination differently from another. No film data is changed.

import CoreGraphics
import CoreImage
import Foundation
#if SPK_ENGINE
import Metal
#endif

final class FilmEdgeScanFinish {
    enum Failure: Error { case kernelUnavailable, imageUnavailable, allocationFailed }

    /// One context for the host's serial render queue; never one per frame or per filter.
    static let shared = FilmEdgeScanFinish()
    private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(),
                                              .cacheIntermediates: false])

    /// The single implementation for every size and destination. Both blurs and both noise scales
    /// are fractions of the actual canvas, so their relative size stays fixed across render tiers.
    func apply(to image: CIImage, settings: FilmEdgeScan, seed: Int) throws -> CIImage {
        guard settings != .clean else { return image }
        let extent = image.extent
        let longEdge = max(extent.width, extent.height)
        guard longEdge > 0, !extent.isInfinite, !extent.isNull else { return image }
        guard let highlights = Self.highlights, let finish = Self.finish else { throw Failure.kernelUnavailable }
        guard let bright = highlights.apply(extent: extent, arguments: [image]) else { throw Failure.imageUnavailable }
        let bloom = bright.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: longEdge / 320])
            .cropped(to: extent)
        let look = settings.look
        let softened = look.softnessDivisor > 0
            ? image.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: longEdge / look.softnessDivisor])
                .cropped(to: extent)
            : image
        // Separate small integer parts avoid losing every low bit of a 31-bit seed in CI's float.
        let bits = UInt32(truncatingIfNeeded: seed)
        guard let result = finish.apply(extent: extent, arguments: [image, softened, bloom,
            CIVector(x: extent.minX, y: extent.minY), longEdge / 2600, longEdge / 6,
            Double(bits & 0xffff), Double(bits >> 16), look.lift, look.noise, look.glow]) else {
            throw Failure.imageUnavailable
        }
        return result
    }

    private static let highlights = CIColorKernel(source: """
    kernel vec4 scanHighlights(__sample p) {
        float y = dot(p.rgb, vec3(0.28804, 0.71187, 0.00009));
        // Pink edge print lies below white perforations: both must be glow sources.
        return vec4(p.rgb * smoothstep(0.55, 0.85, y), p.a);
    }
    """)

    private static let finish = CIColorKernel(source: """
    kernel vec4 scanFinish(__sample p, __sample soft, __sample bloom, vec2 origin, float cell, float broadCell,
                          float seedLo, float seedHi, float lift, float noise, float glow) {
        float y = dot(p.rgb, vec3(0.28804, 0.71187, 0.00009));
        float softY = dot(soft.rgb, vec3(0.28804, 0.71187, 0.00009));
        float soften = 1.0 - smoothstep(0.25, 0.55, softY);
        // Include the bright side of a hole's edge, but not its flat white interior.
        soften = max(soften, step(0.9, y) * (1.0 - step(0.85, softY)));
        vec3 rgb = mix(p.rgb, soft.rgb, soften);

        float dark = 1.0 - smoothstep(0.0, 0.12, y);
        vec2 at = destCoord() - origin;
        vec2 q = floor(at / max(cell, 0.0001));
        float seed = seedLo * 0.013 + seedHi * 0.071;
        float n = fract(sin(dot(q, vec2(12.9898, 78.233)) + seed) * 43758.5453) - 0.5;

        // Smooth value noise from four corners: very broad variation, without another image/filter.
        vec2 uv = at / max(broadCell, 0.0001);
        vec2 i = floor(uv), f = fract(uv);
        f = f * f * (3.0 - 2.0 * f);
        vec4 corners = fract(sin(vec4(dot(i, vec2(12.9898, 78.233)),
            dot(i + vec2(1.0, 0.0), vec2(12.9898, 78.233)),
            dot(i + vec2(0.0, 1.0), vec2(12.9898, 78.233)),
            dot(i + vec2(1.0, 1.0), vec2(12.9898, 78.233))) + seed + 17.345) * 43758.5453);
        float broad = mix(mix(corners.x, corners.y, f.x), mix(corners.z, corners.w, f.x), f.y);
        float variedLift = lift * (1.0 + 0.3 * (2.0 * broad - 1.0));
        rgb += variedLift * dark * vec3(1.0, 0.99, 0.97) + vec3(noise * dark * n);
        rgb += bloom.rgb * vec3(1.0, 0.93, 0.82) * glow * (1.0 - smoothstep(0.0, 0.5, y));
        return vec4(clamp(rgb, 0.0, 1.0), p.a);
    }
    """)

    #if SPK_ENGINE
    /// A new working-space result, before any destination, watermark or full-render cache. The
    /// engine's shared result is never mutated: its negative/checkpoint and a second destination
    /// cannot accidentally acquire the finish. The shared buffer also backs the returned texture.
    func apply(to pixels: RenderedPixels, settings: FilmEdgeScan, seed: Int) throws -> RenderedPixels {
        guard settings != .clean else { return pixels }
        let w = pixels.size.width, h = pixels.size.height, device = pixels.texture.device
        guard w > 0, h > 0 else { return pixels }
        // Read and write the same bitmap convention, including the padded row pitch. A texture →
        // bitmap bridge otherwise risks changing the image's vertical origin. No copy of the input;
        // the incoming result owns its memory until this synchronous render task has completed.
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pixels.rgba16),
                        count: pixels.rowStridePixels * h * 8, deallocator: .none)
        let image = CIImage(bitmapData: data, bytesPerRow: pixels.rowStridePixels * 8,
                            size: CGSize(width: w, height: h), format: .RGBA16, colorSpace: nil)
        let result = try apply(to: image, settings: settings, seed: seed)
        let alignment = max(1, device.minimumLinearTextureAlignment(for: .rgba16Unorm))
        let rowBytes = (w * 8 + alignment - 1) / alignment * alignment
        guard rowBytes * h <= device.maxBufferLength,
              let buffer = device.makeBuffer(length: rowBytes * h, options: .storageModeShared) else {
            throw Failure.allocationFailed
        }
        let destination = CIRenderDestination(bitmapData: buffer.contents(), width: w, height: h,
                                               bytesPerRow: rowBytes, format: .RGBA16)
        destination.colorSpace = nil
        // A task reports a GPU/render failure: a failed finish must fail this job, not quietly
        // write a black export from an untouched output buffer.
        let task = try context.startTask(toRender: result, to: destination)
        _ = try task.waitUntilCompleted()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Unorm, width: w, height: h, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        guard let texture = buffer.makeTexture(descriptor: descriptor, offset: 0, bytesPerRow: rowBytes) else {
            throw Failure.allocationFailed
        }
        var made = RenderedPixels(texture: texture, rgba16: UnsafePointer(buffer.contents().assumingMemoryBound(to: UInt16.self)),
                                  size: pixels.size, rowStridePixels: rowBytes / 8)
        made.keep = buffer
        made.filmGeometry = pixels.filmGeometry
        made.hdrCurve = pixels.hdrCurve
        return made
    }
    #endif
}
