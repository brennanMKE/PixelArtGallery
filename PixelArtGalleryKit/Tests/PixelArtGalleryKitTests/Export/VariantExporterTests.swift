import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PixelArtGalleryKit

/// Device-free tests for `VariantExporter`: build a small known `Variant`, export it to a
/// temp dir for every format, and assert each file exists, is non-empty, and has the
/// expected structure (PNG decodes back to the scaled dimensions; PPM/JSON have the
/// expected header/shape). Regression for #0007, where export was entirely simulated.
@Suite final class VariantExporterTests {
    private let tempDir: URL

    init() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VariantExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Fixture

    /// A 4×3 grid where each pixel encodes its coordinate, so we can detect garbled output.
    private func makeVariant(width: Int = 4, height: Int = 3, scaleFactor: Double = 1.0) -> Variant {
        var grid = PixelGrid(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                grid.setColor(
                    PixelColor(red: UInt8(x * 10), green: UInt8(y * 10), blue: 128, alpha: 255),
                    x: x, y: y
                )
            }
        }
        return Variant(
            targetWidth: width,
            targetHeight: height,
            pixelGridData: grid.toRGBA8888(),
            scaleFactor: scaleFactor
        )
    }

    private func attributes(of url: URL) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: url.path)
    }

    // MARK: - PNG

    @Test func exportPNGProducesNonEmptyFileWithCorrectDimensions() throws {
        let variant = makeVariant(scaleFactor: 1.0)
        let url = tempDir.appendingPathComponent("out.png")
        let exporter = VariantExporter()

        try exporter.export(variant, as: .png, to: url)

        #expect(FileManager.default.fileExists(atPath: url.path))
        let size = try attributes(of: url)[.size] as? Int ?? 0
        #expect(size > 0, "PNG file should be non-empty")

        let (w, h) = try Self.decodeImageDimensions(at: url)
        #expect(w == 4)
        #expect(h == 3)
    }

    @Test func exportPNGHonorsScaleFactor() throws {
        let variant = makeVariant(scaleFactor: 3.0)
        let url = tempDir.appendingPathComponent("scaled.png")
        try VariantExporter().export(variant, as: .png, to: url)

        let (w, h) = try Self.decodeImageDimensions(at: url)
        #expect(w == 12, "4 px * scaleFactor 3 = 12")
        #expect(h == 9, "3 px * scaleFactor 3 = 9")
    }

    // MARK: - HEIC

    @Test func exportHEICProducesNonEmptyFile() throws {
        // HEIC encoding support can vary by platform; bail gracefully if unavailable.
        let variant = makeVariant()
        let url = tempDir.appendingPathComponent("out.heic")
        do {
            try VariantExporter().export(variant, as: .heic, to: url)
        } catch ExportError.encodingFailed {
            // HEIC encoding not available on this host — nothing to assert.
            return
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        let size = try attributes(of: url)[.size] as? Int ?? 0
        #expect(size > 0)
        let (w, h) = try Self.decodeImageDimensions(at: url)
        #expect(w == 4)
        #expect(h == 3)
    }

    // MARK: - PPM

    @Test func exportPPMHasP6HeaderAndExpectedByteCount() throws {
        let variant = makeVariant()
        let url = tempDir.appendingPathComponent("out.ppm")
        try VariantExporter().export(variant, as: .ppm, to: url)

        let data = try Data(contentsOf: url)
        #expect(data.count > 0)

        // Header: "P6\n4 3\n255\n" then 4*3*3 = 36 binary bytes.
        let headerString = "P6\n4 3\n255\n"
        let headerBytes = Data(headerString.utf8)
        #expect(data.prefix(headerBytes.count) == headerBytes, "Expected P6 header")
        #expect(data.count == headerBytes.count + 4 * 3 * 3, "Header + RGB triples")

        // First pixel (x=0, y=0) is r=0, g=0, b=128.
        let body = data.suffix(from: headerBytes.count)
        let firstByte = body.first
        #expect(firstByte == 0)
        #expect(Array(body.prefix(3)) == [0, 0, 128])
    }

    // MARK: - JSON

    @Test func exportJSONHasExpectedMatrixStructure() throws {
        let variant = makeVariant()
        let url = tempDir.appendingPathComponent("out.json")
        try VariantExporter().export(variant, as: .json, to: url)

        let data = try Data(contentsOf: url)
        #expect(data.count > 0)

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let json = try #require(object)
        #expect(json["width"] as? Int == 4)
        #expect(json["height"] as? Int == 3)

        let pixels = try #require(json["pixels"] as? [[[Int]]])
        #expect(pixels.count == 3, "3 rows")
        #expect(pixels[0].count == 4, "4 columns")
        #expect(pixels[0][0] == [0, 0, 128, 255], "row 0, col 0")
        #expect(pixels[2][3] == [30, 20, 128, 255], "row 2, col 3 = x*10,y*10")
    }

    // MARK: - Error handling

    @Test func exportRejectsMismatchedPixelData() {
        let variant = Variant(targetWidth: 4, targetHeight: 4, pixelGridData: Data([1, 2, 3]))
        let url = tempDir.appendingPathComponent("bad.png")
        #expect {
            try VariantExporter().export(variant, as: .png, to: url)
        } throws: { error in
            guard case ExportError.invalidPixelData = error else { return false }
            return true
        }
    }

    @Test func formatNameParsingIsCaseInsensitive() {
        #expect(ExportFormat(name: "png") == .png)
        #expect(ExportFormat(name: "Json") == .json)
        #expect(ExportFormat(name: "bmp") == nil)
    }

    // MARK: - Helpers

    private static func decodeImageDimensions(at url: URL) throws -> (Int, Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "Could not open image")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil), "Could not decode image")
        return (image.width, image.height)
    }
}
