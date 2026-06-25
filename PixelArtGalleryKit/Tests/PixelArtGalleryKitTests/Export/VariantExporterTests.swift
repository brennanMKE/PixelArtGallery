import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PixelArtGalleryKit

/// Device-free tests for `VariantExporter`: build a small known `Variant`, export it to a
/// temp dir for every format, and assert each file exists, is non-empty, and has the
/// expected structure (PNG decodes back to the scaled dimensions; PPM/JSON have the
/// expected header/shape). Regression for #0007, where export was entirely simulated.
final class VariantExporterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VariantExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
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

    func testExportPNGProducesNonEmptyFileWithCorrectDimensions() throws {
        let variant = makeVariant(scaleFactor: 1.0)
        let url = tempDir.appendingPathComponent("out.png")
        let exporter = VariantExporter()

        try exporter.export(variant, as: .png, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let size = try attributes(of: url)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0, "PNG file should be non-empty")

        let (w, h) = try Self.decodeImageDimensions(at: url)
        XCTAssertEqual(w, 4)
        XCTAssertEqual(h, 3)
    }

    func testExportPNGHonorsScaleFactor() throws {
        let variant = makeVariant(scaleFactor: 3.0)
        let url = tempDir.appendingPathComponent("scaled.png")
        try VariantExporter().export(variant, as: .png, to: url)

        let (w, h) = try Self.decodeImageDimensions(at: url)
        XCTAssertEqual(w, 12, "4 px * scaleFactor 3 = 12")
        XCTAssertEqual(h, 9, "3 px * scaleFactor 3 = 9")
    }

    // MARK: - HEIC

    func testExportHEICProducesNonEmptyFile() throws {
        // HEIC encoding support can vary by platform; skip gracefully if unavailable.
        let variant = makeVariant()
        let url = tempDir.appendingPathComponent("out.heic")
        do {
            try VariantExporter().export(variant, as: .heic, to: url)
        } catch ExportError.encodingFailed {
            throw XCTSkip("HEIC encoding not available on this host")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let size = try attributes(of: url)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)
        let (w, h) = try Self.decodeImageDimensions(at: url)
        XCTAssertEqual(w, 4)
        XCTAssertEqual(h, 3)
    }

    // MARK: - PPM

    func testExportPPMHasP6HeaderAndExpectedByteCount() throws {
        let variant = makeVariant()
        let url = tempDir.appendingPathComponent("out.ppm")
        try VariantExporter().export(variant, as: .ppm, to: url)

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0)

        // Header: "P6\n4 3\n255\n" then 4*3*3 = 36 binary bytes.
        let headerString = "P6\n4 3\n255\n"
        let headerBytes = Data(headerString.utf8)
        XCTAssertEqual(data.prefix(headerBytes.count), headerBytes, "Expected P6 header")
        XCTAssertEqual(data.count, headerBytes.count + 4 * 3 * 3, "Header + RGB triples")

        // First pixel (x=0, y=0) is r=0, g=0, b=128.
        let body = data.suffix(from: headerBytes.count)
        let firstByte = body.first
        XCTAssertEqual(firstByte, 0)
        XCTAssertEqual(Array(body.prefix(3)), [0, 0, 128])
    }

    // MARK: - JSON

    func testExportJSONHasExpectedMatrixStructure() throws {
        let variant = makeVariant()
        let url = tempDir.appendingPathComponent("out.json")
        try VariantExporter().export(variant, as: .json, to: url)

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0)

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let json = try XCTUnwrap(object)
        XCTAssertEqual(json["width"] as? Int, 4)
        XCTAssertEqual(json["height"] as? Int, 3)

        let pixels = try XCTUnwrap(json["pixels"] as? [[[Int]]])
        XCTAssertEqual(pixels.count, 3, "3 rows")
        XCTAssertEqual(pixels[0].count, 4, "4 columns")
        XCTAssertEqual(pixels[0][0], [0, 0, 128, 255], "row 0, col 0")
        XCTAssertEqual(pixels[2][3], [30, 20, 128, 255], "row 2, col 3 = x*10,y*10")
    }

    // MARK: - Error handling

    func testExportRejectsMismatchedPixelData() {
        let variant = Variant(targetWidth: 4, targetHeight: 4, pixelGridData: Data([1, 2, 3]))
        let url = tempDir.appendingPathComponent("bad.png")
        XCTAssertThrowsError(try VariantExporter().export(variant, as: .png, to: url)) { error in
            guard case ExportError.invalidPixelData = error else {
                return XCTFail("Expected invalidPixelData, got \(error)")
            }
        }
    }

    func testFormatNameParsingIsCaseInsensitive() {
        XCTAssertEqual(ExportFormat(name: "png"), .png)
        XCTAssertEqual(ExportFormat(name: "Json"), .json)
        XCTAssertNil(ExportFormat(name: "bmp"))
    }

    // MARK: - Helpers

    private static func decodeImageDimensions(at url: URL) throws -> (Int, Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), "Could not open image")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), "Could not decode image")
        return (image.width, image.height)
    }
}
