import CoreGraphics
import Foundation
import ImageIO

/// Errors thrown while pixelating source imagery.
nonisolated public enum PixelationError: Error, Equatable {
    /// The supplied image data could not be decoded.
    case failedToCreateImageSource
    /// A decoded image could not be obtained from the source.
    case failedToDecodeImage
    /// A drawing context could not be created for the target dimensions.
    case failedToCreateContext
    /// The requested target dimensions are invalid (must be positive).
    case invalidTargetDimensions(width: Int, height: Int)
}

/// Downsamples a source image into a fixed-size `PixelGrid` of RGBA colors.
///
/// The engine draws the source image into a target-sized RGBA8888 bitmap and
/// reads the resulting pixels back out, producing one `PixelColor` per cell.
nonisolated public struct PixelationEngine: Sendable {
    public init() {}

    /// Produce a pixelated grid from encoded image data.
    /// - Parameters:
    ///   - imageData: Encoded image bytes (PNG, JPEG, HEIC, …).
    ///   - targetWidth: Width of the resulting pixel grid.
    ///   - targetHeight: Height of the resulting pixel grid.
    /// - Returns: A `PixelGrid` sized `targetWidth × targetHeight`.
    public func process(imageData: Data, targetWidth: Int, targetHeight: Int) async throws -> PixelGrid {
        guard targetWidth > 0, targetHeight > 0 else {
            AppLog.imageProcessor.error("Invalid target dimensions \(targetWidth)×\(targetHeight)")
            throw PixelationError.invalidTargetDimensions(width: targetWidth, height: targetHeight)
        }

        AppLog.imageProcessor.debug("Pixelating \(imageData.count) bytes -> \(targetWidth)×\(targetHeight)")

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            AppLog.imageProcessor.error("Failed to create image source from \(imageData.count) bytes")
            throw PixelationError.failedToCreateImageSource
        }
        // Decode with the image's EXIF orientation applied so photos shot in
        // portrait (or any non-default orientation) are pixelated upright.
        // `CGImageSourceCreateImageAtIndex` returns the raw pixel buffer and
        // ignores `kCGImagePropertyOrientation`; the thumbnail path below honors
        // it (`…WithTransform`) and works on both iOS and macOS without UIKit.
        guard let cgImage = Self.uprightImage(from: source)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            AppLog.imageProcessor.error("Failed to decode image from source")
            throw PixelationError.failedToDecodeImage
        }

        let grid = try pixelate(cgImage, targetWidth: targetWidth, targetHeight: targetHeight)
        AppLog.imageProcessor.info("Pixelated \(cgImage.width)×\(cgImage.height) source into \(targetWidth)×\(targetHeight) grid")
        return grid
    }

    /// Decode the primary image with its EXIF orientation baked into the pixels,
    /// yielding an upright `CGImage`.
    ///
    /// ImageIO's thumbnail generator applies `kCGImagePropertyOrientation` when
    /// `kCGImageSourceCreateThumbnailWithTransform` is set, which the plain
    /// `CGImageSourceCreateImageAtIndex` decode does not. The max pixel size is
    /// pinned to the source's largest dimension so no resolution is lost before
    /// the downsample step (the value only caps the output, it never upscales).
    /// Returns `nil` if the source has no usable dimensions or ImageIO declines
    /// to produce a thumbnail, letting the caller fall back to a raw decode.
    static func uprightImage(from source: CGImageSource) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let maxDimension = max(pixelWidth, pixelHeight)
        guard maxDimension > 0 else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Downsample a decoded `CGImage` into a `PixelGrid`.
    public func pixelate(_ image: CGImage, targetWidth: Int, targetHeight: Int) throws -> PixelGrid {
        guard targetWidth > 0, targetHeight > 0 else {
            throw PixelationError.invalidTargetDimensions(width: targetWidth, height: targetHeight)
        }

        let bytesPerPixel = 4
        let bytesPerRow = targetWidth * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        var buffer = [UInt8](repeating: 0, count: targetHeight * bytesPerRow)
        guard let context = buffer.withUnsafeMutableBytes({ raw -> CGContext? in
            CGContext(
                data: raw.baseAddress,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        }) else {
            AppLog.imageProcessor.error("Failed to create drawing context for \(targetWidth)×\(targetHeight)")
            throw PixelationError.failedToCreateContext
        }

        // High-quality interpolation makes Core Graphics area-average the source
        // pixels that fall under each destination cell when downscaling, rather
        // than sampling a single nearest pixel. This matches the PRD's bilinear-
        // with-light-blur requirement (per the PixelArtConverter reference): each
        // output cell reflects the true average color of its source region, which
        // is critical for color accuracy on the FT displays. Anti-aliasing is left
        // enabled so partially-covered edge cells blend correctly.
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        var rows = [[PixelColor]]()
        rows.reserveCapacity(targetHeight)
        for y in 0..<targetHeight {
            var row = [PixelColor]()
            row.reserveCapacity(targetWidth)
            for x in 0..<targetWidth {
                let offset = y * bytesPerRow + x * bytesPerPixel
                row.append(
                    PixelColor(
                        red: buffer[offset],
                        green: buffer[offset + 1],
                        blue: buffer[offset + 2],
                        alpha: buffer[offset + 3]
                    )
                )
            }
            rows.append(row)
        }

        return PixelGrid(width: targetWidth, height: targetHeight, colors: rows)
    }
}
