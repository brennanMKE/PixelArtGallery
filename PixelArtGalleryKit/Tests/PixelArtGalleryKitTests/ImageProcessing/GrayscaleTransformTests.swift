import Testing
@testable import PixelArtGalleryKit
import Foundation

/// Tests for ``PixelGrid/grayscale(rgba8888:)`` (#0077) — the Rec.601
/// luminance transform applied to an RGBA8888 buffer before a grayscale send.
/// Expected values are precomputed per the issue's table: `y = round(0.299·r
/// + 0.587·g + 0.114·b)`, alpha preserved.
@Suite struct GrayscaleTransformTests {
    private func pixel(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> Data {
        Data([r, g, b, a])
    }

    // MARK: - Known single-pixel conversions

    @Test func pureRedConvertsTo76() {
        let input = pixel(255, 0, 0, 255)
        let output = PixelGrid.grayscale(rgba8888: input)
        #expect(Array(output) == [76, 76, 76, 255])
    }

    @Test func pureGreenConvertsTo150RoundedUp() {
        // 0.587 * 255 = 149.685 -> rounds up to 150 (ft-swift's truncation
        // would give 149; this implementation rounds per spec).
        let input = pixel(0, 255, 0, 255)
        let output = PixelGrid.grayscale(rgba8888: input)
        #expect(Array(output) == [150, 150, 150, 255])
    }

    @Test func pureBlueConvertsTo29() {
        let input = pixel(0, 0, 255, 255)
        let output = PixelGrid.grayscale(rgba8888: input)
        #expect(Array(output) == [29, 29, 29, 255])
    }

    @Test func whiteConvertsTo255() {
        let input = pixel(255, 255, 255, 255)
        let output = PixelGrid.grayscale(rgba8888: input)
        #expect(Array(output) == [255, 255, 255, 255])
    }

    @Test func blackStaysBlack() {
        let input = pixel(0, 0, 0, 255)
        let output = PixelGrid.grayscale(rgba8888: input)
        #expect(Array(output) == [0, 0, 0, 255])
    }

    @Test func midColorConvertsTo124() {
        // 0.299*200 + 0.587*100 + 0.114*50 = 59.8 + 58.7 + 5.7 = 124.2 -> 124
        let input = pixel(200, 100, 50, 128)
        let output = PixelGrid.grayscale(rgba8888: input)
        #expect(Array(output) == [124, 124, 124, 128])
    }

    @Test func transparentBlackStaysTransparentBlack() {
        let input = pixel(0, 0, 0, 0)
        let output = PixelGrid.grayscale(rgba8888: input)
        #expect(Array(output) == [0, 0, 0, 0])
    }

    // MARK: - Multi-pixel buffer

    @Test func multiPixelBufferPreservesLengthAndPerPixelValues() {
        var input = Data()
        input.append(pixel(255, 0, 0, 255))    // red
        input.append(pixel(0, 255, 0, 255))    // green
        input.append(pixel(0, 0, 255, 255))    // blue
        input.append(pixel(255, 255, 255, 255)) // white
        input.append(pixel(0, 0, 0, 255))       // black
        input.append(pixel(200, 100, 50, 128))  // mid
        input.append(pixel(0, 0, 0, 0))         // transparent black

        let output = PixelGrid.grayscale(rgba8888: input)

        #expect(output.count == input.count)
        #expect(output.count == 28)

        let expected: [[UInt8]] = [
            [76, 76, 76, 255],
            [150, 150, 150, 255],
            [29, 29, 29, 255],
            [255, 255, 255, 255],
            [0, 0, 0, 255],
            [124, 124, 124, 128],
            [0, 0, 0, 0],
        ]
        let bytes = Array(output)
        for (index, pixel) in expected.enumerated() {
            let offset = index * 4
            #expect(Array(bytes[offset..<(offset + 4)]) == pixel)
        }
    }

    // MARK: - Alpha preservation

    @Test func alphaPreservedAcrossVariedValues() {
        for alpha: UInt8 in [0, 128, 255] {
            let input = pixel(200, 100, 50, alpha)
            let output = PixelGrid.grayscale(rgba8888: input)
            #expect(output.last == alpha)
        }
    }

    // MARK: - Idempotence

    @Test func idempotentOnMixedBuffer() {
        var input = Data()
        input.append(pixel(255, 0, 0, 255))
        input.append(pixel(200, 100, 50, 128))
        input.append(pixel(0, 0, 0, 0))

        let once = PixelGrid.grayscale(rgba8888: input)
        let twice = PixelGrid.grayscale(rgba8888: once)
        #expect(once == twice)
    }

    @Test func idempotentOnAlreadyGrayPixel() {
        let gray = pixel(76, 76, 76, 255)
        let output = PixelGrid.grayscale(rgba8888: gray)
        #expect(Array(output) == [76, 76, 76, 255])
    }

    // MARK: - Empty buffer

    @Test func emptyDataReturnsEmptyData() {
        let output = PixelGrid.grayscale(rgba8888: Data())
        #expect(output.isEmpty)
    }
}
