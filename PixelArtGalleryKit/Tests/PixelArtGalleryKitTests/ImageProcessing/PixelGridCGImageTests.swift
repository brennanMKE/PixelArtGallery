import Testing
import Foundation
import CoreGraphics
@testable import PixelArtGalleryKit

/// Tests for `PixelGrid.makeCGImage(scale:)` — the shared renderer behind both
/// `VariantExporter` (PNG/HEIC) and the on-screen `VariantThumbnailView`.
@Suite struct PixelGridCGImageTests {

    @Test func makeCGImageScalesDimensions() throws {
        // 2×1 grid → at scale 3 the raster is 6×3, nearest-neighbor.
        let data = Data([255, 0, 0, 255, /* red */ 0, 255, 0, 255 /* green */])
        let grid = try PixelGrid.fromRGBA8888(data, width: 2, height: 1)

        let image = try #require(grid.makeCGImage(scale: 3))
        #expect(image.width == 6)
        #expect(image.height == 3)

        let scale1 = try #require(grid.makeCGImage(scale: 1))
        #expect(scale1.width == 2)
        #expect(scale1.height == 1)
    }

    @Test func makeCGImagePreservesPixelColorsNearestNeighbor() throws {
        // Single row so a vertical flip in readback can't affect the assertions:
        // left half must stay red, right half green (no blending across the seam).
        let data = Data([255, 0, 0, 255, 0, 255, 0, 255])
        let grid = try PixelGrid.fromRGBA8888(data, width: 2, height: 1)
        let image = try #require(grid.makeCGImage(scale: 3))

        let pixels = try readBackRGBA(image)
        // x = 0 (far left) → red block.
        #expect(pixels[0] > 200)          // R
        #expect(pixels[1] < 55)           // G
        // x = 5 (far right) → green block. Offset = 5 * 4.
        #expect(pixels[5 * 4] < 55)       // R
        #expect(pixels[5 * 4 + 1] > 200)  // G
    }

    /// Draw a CGImage into a known RGBA8888 buffer and return the bytes (row-major).
    private func readBackRGBA(_ image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try #require(buffer.withUnsafeMutableBytes { raw in
            CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        })
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
