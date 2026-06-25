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
            throw PixelationError.invalidTargetDimensions(width: targetWidth, height: targetHeight)
        }

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw PixelationError.failedToCreateImageSource
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PixelationError.failedToDecodeImage
        }

        return try pixelate(cgImage, targetWidth: targetWidth, targetHeight: targetHeight)
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
            throw PixelationError.failedToCreateContext
        }

        // Nearest-neighbor sampling keeps hard pixel edges rather than blurring.
        context.interpolationQuality = .none
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
