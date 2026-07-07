import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PixelArtGalleryKit

@Suite struct PixelationEngineTests {
    /// The engine should decode a known in-memory PNG and produce a grid of the
    /// requested target size whose pixels carry the source color — proving the
    /// variant pipeline yields real, non-empty pixel data (regression for #0004,
    /// where an empty `Data()` produced all-black variants).
    @Test func processProducesCorrectlySizedNonEmptyGrid() async throws {
        let targetWidth = 8
        let targetHeight = 6
        // Solid red source so we can assert the grid is genuinely non-empty.
        let pngData = try Self.makePNGData(width: 32, height: 24, red: 1, green: 0, blue: 0)

        let engine = PixelationEngine()
        let grid = try await engine.process(
            imageData: pngData,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )

        #expect(grid.width == targetWidth, "Grid width should match the requested target")
        #expect(grid.height == targetHeight, "Grid height should match the requested target")
        #expect(grid.colors.count == targetHeight, "Grid should have one row per target row")
        #expect(grid.colors.first?.count == targetWidth, "Each row should have target-width pixels")

        // RGBA8888 buffer must be the exact expected length and not all zero.
        let rgba = grid.toRGBA8888()
        #expect(rgba.count == targetWidth * targetHeight * 4, "RGBA buffer should be width*height*4 bytes")
        #expect(rgba.contains { $0 != 0 }, "A real source image should not yield an all-zero (black/empty) grid")

        // The dominant channel of a solid-red source should be red.
        let sample = grid.color(x: targetWidth / 2, y: targetHeight / 2)
        #expect(sample.red > sample.green, "Red source should produce red-dominant pixels")
        #expect(sample.red > sample.blue, "Red source should produce red-dominant pixels")
    }

    /// Downsampling must AVERAGE the source region for each output cell, not
    /// pick a single nearest-neighbor pixel. A 2x2 black/white checkerboard
    /// collapsed to a single cell should yield mid-gray (~128). Nearest-neighbor
    /// (`interpolationQuality = .none`) would instead return one corner pixel —
    /// pure black (0) or pure white (255) — so a mid-gray result proves the
    /// engine area-averages as the PRD requires.
    @Test func downsampleAveragesSourceRegionToMidGray() async throws {
        // 2x2 checkerboard: black / white on top row, white / black on bottom.
        let checkerboard = try Self.makeCheckerboardPNGData()

        let engine = PixelationEngine()
        let grid = try await engine.process(
            imageData: checkerboard,
            targetWidth: 1,
            targetHeight: 1
        )

        let pixel = grid.color(x: 0, y: 0)
        // Average of two black (0) and two white (255) pixels is 127.5 → ~128.
        // Allow tolerance for rounding / color-space conversion.
        let midGray = 128
        let tolerance = 24
        #expect(abs(Int(pixel.red) - midGray) <= tolerance, "Averaged red should be mid-gray, not a single sampled pixel")
        #expect(abs(Int(pixel.green) - midGray) <= tolerance, "Averaged green should be mid-gray, not a single sampled pixel")
        #expect(abs(Int(pixel.blue) - midGray) <= tolerance, "Averaged blue should be mid-gray, not a single sampled pixel")
        // Explicitly reject the nearest-neighbor outcomes (pure black or white).
        #expect(Int(pixel.red) > 40, "Nearest-neighbor would have returned pure black (0)")
        #expect(Int(pixel.red) < 215, "Nearest-neighbor would have returned pure white (255)")
    }

    /// The engine must apply EXIF orientation before downsampling (regression for
    /// #0048, where portrait photos came out rotated). The same base pixels are
    /// encoded twice — once as orientation `up` (1) and once as `down` (3, a 180°
    /// rotation). After processing, the `down` grid must equal the `up` grid
    /// rotated 180°; if orientation were ignored, the two grids would be identical.
    @Test func processAppliesExifOrientation() async throws {
        // Asymmetric marker: top-left quadrant red, remainder black.
        let side = 8
        let base = try Self.makeQuadrantMarkerImage(side: side)
        let upData = try Self.encode(base, orientation: 1)      // .up — no rotation
        let downData = try Self.encode(base, orientation: 3)    // .down — 180°

        let engine = PixelationEngine()
        let up = try await engine.process(imageData: upData, targetWidth: side, targetHeight: side)
        let down = try await engine.process(imageData: downData, targetWidth: side, targetHeight: side)

        // Sanity: the upright marker really is in the top-left.
        #expect(up.color(x: 0, y: 0).red > up.color(x: 0, y: 0).blue,
                "Upright marker should be red in the top-left")
        #expect(up.color(x: 0, y: 0).red > up.color(x: side - 1, y: side - 1).red,
                "Upright marker should be brighter red in the top-left than bottom-right")

        // The 180°-tagged image, once oriented, must match the up grid rotated 180°.
        for y in 0..<side {
            for x in 0..<side {
                let expected = up.color(x: side - 1 - x, y: side - 1 - y)
                let actual = down.color(x: x, y: y)
                #expect(abs(Int(actual.red) - Int(expected.red)) <= 4,
                        "Oriented pixel (\(x),\(y)) red should match the 180°-rotated upright pixel")
            }
        }

        // Guard against a false pass where orientation was silently ignored:
        // the marker must NOT be in the top-left of the down grid.
        #expect(down.color(x: 0, y: 0).red < down.color(x: side - 1, y: side - 1).red,
                "Orientation was ignored — marker stayed in the top-left of the rotated image")
    }

    @Test func processRejectsInvalidDimensions() async throws {
        let engine = PixelationEngine()
        let pngData = try? Self.makePNGData(width: 4, height: 4, red: 0, green: 1, blue: 0)
        await #expect(throws: PixelationError.invalidTargetDimensions(width: 0, height: 4)) {
            _ = try await engine.process(imageData: pngData ?? Data(), targetWidth: 0, targetHeight: 4)
        }
    }

    /// A square image with the top-left quadrant red and the rest black — an
    /// asymmetric marker that makes rotation observable.
    private static func makeQuadrantMarkerImage(side: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        // CGContext origin is bottom-left, so the top-left quadrant is high y.
        let half = side / 2
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: half, width: half, height: half))
        return try #require(context.makeImage())
    }

    /// Encode a CGImage to lossless TIFF carrying the given EXIF orientation value
    /// (1 = up, 3 = 180°, 6 = 90° CW, …). TIFF is used so orientation round-trips
    /// without the color loss a JPEG re-encode would introduce.
    private static func encode(_ image: CGImage, orientation: Int) throws -> Data {
        let mutableData = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            mutableData, UTType.tiff.identifier as CFString, 1, nil
        ))
        let properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination), "Failed to encode oriented TIFF")
        return mutableData as Data
    }

    /// Generate a solid-color PNG of the given size, platform-independently.
    private static func makePNGData(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let mutableData = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), "Failed to encode PNG")
        return mutableData as Data
    }

    /// Generate a 2x2 black/white checkerboard PNG. Two cells are black and two
    /// are white, so the area-average of the whole image is mid-gray.
    private static func makeCheckerboardPNGData() throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        // (0,0) black, (1,0) white, (0,1) white, (1,1) black.
        context.setFillColor(black)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(white)
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        context.setFillColor(white)
        context.fill(CGRect(x: 0, y: 1, width: 1, height: 1))
        context.setFillColor(black)
        context.fill(CGRect(x: 1, y: 1, width: 1, height: 1))
        let image = try #require(context.makeImage())

        let mutableData = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), "Failed to encode checkerboard PNG")
        return mutableData as Data
    }
}
