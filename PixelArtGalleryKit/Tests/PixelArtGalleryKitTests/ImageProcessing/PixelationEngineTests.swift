import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PixelArtGalleryKit

final class PixelationEngineTests: XCTestCase {
    /// The engine should decode a known in-memory PNG and produce a grid of the
    /// requested target size whose pixels carry the source color — proving the
    /// variant pipeline yields real, non-empty pixel data (regression for #0004,
    /// where an empty `Data()` produced all-black variants).
    func testProcessProducesCorrectlySizedNonEmptyGrid() async throws {
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

        XCTAssertEqual(grid.width, targetWidth, "Grid width should match the requested target")
        XCTAssertEqual(grid.height, targetHeight, "Grid height should match the requested target")
        XCTAssertEqual(grid.colors.count, targetHeight, "Grid should have one row per target row")
        XCTAssertEqual(grid.colors.first?.count, targetWidth, "Each row should have target-width pixels")

        // RGBA8888 buffer must be the exact expected length and not all zero.
        let rgba = grid.toRGBA8888()
        XCTAssertEqual(rgba.count, targetWidth * targetHeight * 4, "RGBA buffer should be width*height*4 bytes")
        XCTAssertTrue(rgba.contains { $0 != 0 }, "A real source image should not yield an all-zero (black/empty) grid")

        // The dominant channel of a solid-red source should be red.
        let sample = grid.color(x: targetWidth / 2, y: targetHeight / 2)
        XCTAssertGreaterThan(sample.red, sample.green, "Red source should produce red-dominant pixels")
        XCTAssertGreaterThan(sample.red, sample.blue, "Red source should produce red-dominant pixels")
    }

    /// Downsampling must AVERAGE the source region for each output cell, not
    /// pick a single nearest-neighbor pixel. A 2x2 black/white checkerboard
    /// collapsed to a single cell should yield mid-gray (~128). Nearest-neighbor
    /// (`interpolationQuality = .none`) would instead return one corner pixel —
    /// pure black (0) or pure white (255) — so a mid-gray result proves the
    /// engine area-averages as the PRD requires.
    func testDownsampleAveragesSourceRegionToMidGray() async throws {
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
        XCTAssertEqual(Int(pixel.red), midGray, accuracy: tolerance, "Averaged red should be mid-gray, not a single sampled pixel")
        XCTAssertEqual(Int(pixel.green), midGray, accuracy: tolerance, "Averaged green should be mid-gray, not a single sampled pixel")
        XCTAssertEqual(Int(pixel.blue), midGray, accuracy: tolerance, "Averaged blue should be mid-gray, not a single sampled pixel")
        // Explicitly reject the nearest-neighbor outcomes (pure black or white).
        XCTAssertGreaterThan(Int(pixel.red), 40, "Nearest-neighbor would have returned pure black (0)")
        XCTAssertLessThan(Int(pixel.red), 215, "Nearest-neighbor would have returned pure white (255)")
    }

    func testProcessRejectsInvalidDimensions() async {
        let engine = PixelationEngine()
        let pngData = try? Self.makePNGData(width: 4, height: 4, red: 0, green: 1, blue: 0)
        do {
            _ = try await engine.process(imageData: pngData ?? Data(), targetWidth: 0, targetHeight: 4)
            XCTFail("Expected invalidTargetDimensions to be thrown")
        } catch let error as PixelationError {
            XCTAssertEqual(error, .invalidTargetDimensions(width: 0, height: 4))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Generate a solid-color PNG of the given size, platform-independently.
    private static func makePNGData(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
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
        let image = try XCTUnwrap(context.makeImage())

        let mutableData = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "Failed to encode PNG")
        return mutableData as Data
    }

    /// Generate a 2x2 black/white checkerboard PNG. Two cells are black and two
    /// are white, so the area-average of the whole image is mid-gray.
    private static func makeCheckerboardPNGData() throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
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
        let image = try XCTUnwrap(context.makeImage())

        let mutableData = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "Failed to encode checkerboard PNG")
        return mutableData as Data
    }
}
