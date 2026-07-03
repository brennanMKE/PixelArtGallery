import CoreGraphics
import Foundation

/// Wrapper so a decoded/rendered `CGImage` (immutable once created) can cross an
/// actor boundary without a strict-concurrency warning.
nonisolated struct SendableCGImage: @unchecked Sendable {
    let cgImage: CGImage
}

nonisolated extension PixelGrid {
    /// Number of bytes per pixel in the RGBA8888 layout.
    private static var bytesPerPixel: Int { 4 }

    /// Render this grid to a `CGImage`, nearest-neighbor upscaling each pixel into a
    /// `scale × scale` block so the pixel art stays crisp. Returns `nil` if a CoreGraphics
    /// context can't be created.
    ///
    /// Shared by `VariantExporter` (PNG/HEIC encoding, honoring `scaleFactor`) and
    /// `VariantThumbnailView` (crisp on-screen previews).
    func makeCGImage(scale: Int = 1) -> CGImage? {
        let scale = max(1, scale)
        let outWidth = width * scale
        let outHeight = height * scale
        guard outWidth > 0, outHeight > 0 else { return nil }

        // Premultiplied RGBA8888 buffer: CoreGraphics supports premultipliedLast for an
        // 8-bit RGB context (straight alpha is not a supported context format), so
        // premultiply each channel by alpha.
        var pixels = [UInt8](repeating: 0, count: outWidth * outHeight * Self.bytesPerPixel)
        for y in 0..<outHeight {
            let srcY = y / scale
            for x in 0..<outWidth {
                let srcX = x / scale
                let color = self.color(x: srcX, y: srcY)
                let offset = (y * outWidth + x) * Self.bytesPerPixel
                let a = Int(color.alpha)
                pixels[offset] = UInt8(Int(color.red) * a / 255)
                pixels[offset + 1] = UInt8(Int(color.green) * a / 255)
                pixels[offset + 2] = UInt8(Int(color.blue) * a / 255)
                pixels[offset + 3] = color.alpha
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: outWidth,
                height: outHeight,
                bitsPerComponent: 8,
                bytesPerRow: outWidth * Self.bytesPerPixel,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return nil
            }
            return context.makeImage()
        }
    }
}
