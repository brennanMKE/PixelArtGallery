import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Errors thrown while exporting a `Variant` to a file format.
nonisolated public enum ExportError: Error, Equatable {
    /// The variant's `pixelGridData` did not match `targetWidth * targetHeight * 4` bytes.
    case invalidPixelData(expected: Int, actual: Int)
    /// The variant dimensions were not positive.
    case invalidDimensions(width: Int, height: Int)
    /// A CoreGraphics image could not be constructed from the pixel data.
    case imageCreationFailed
    /// ImageIO could not create a destination or encode the image for the format.
    case encodingFailed(format: String)
    /// Serializing the JSON color matrix failed.
    case serializationFailed
    /// Writing the encoded bytes to the destination URL failed.
    case writeFailed(underlying: String)
}

/// The output formats a `Variant` can be exported to.
nonisolated public enum ExportFormat: String, CaseIterable, Sendable {
    case png = "PNG"
    case heic = "HEIC"
    case ppm = "PPM"
    case json = "JSON"

    /// The lowercased file extension for this format.
    public var fileExtension: String { rawValue.lowercased() }

    /// Parse a format from a case-insensitive name (e.g. "png", "PNG").
    public init?(name: String) {
        self.init(rawValue: name.uppercased())
    }
}

/// Converts a `Variant`'s RGBA8888 pixel data into a concrete file format and writes it.
///
/// Fully platform-agnostic: PNG/HEIC are encoded with CoreGraphics/ImageIO, PPM is a raw P6
/// portable pixmap, and JSON is a row-major color matrix of `[r, g, b, a]` integers.
/// PNG and HEIC honor the variant's `scaleFactor` by nearest-neighbor upscaling so that each
/// source pixel becomes a `scaleFactor × scaleFactor` block in the encoded raster.
nonisolated public struct VariantExporter: Sendable {
    private static let bytesPerPixel = 4

    public init() {}

    /// Encode `variant` as `format` and return the resulting file bytes.
    ///
    /// - Note: `Variant` is a SwiftData `@Model` (main-actor bound), so this reads its plain
    ///   fields up front and delegates to `data(width:height:pixelGridData:scaleFactor:format:)`,
    ///   which is free to run off the main actor.
    public func data(for variant: Variant, format: ExportFormat) throws -> Data {
        try data(
            width: variant.targetWidth,
            height: variant.targetHeight,
            pixelGridData: variant.pixelGridData,
            scaleFactor: variant.scaleFactor,
            format: format
        )
    }

    /// Encode raw RGBA8888 pixel data as `format` and return the resulting file bytes.
    ///
    /// Operates purely on value types, so it can be called from any actor / a detached task.
    public func data(
        width: Int,
        height: Int,
        pixelGridData: Data,
        scaleFactor: Double,
        format: ExportFormat
    ) throws -> Data {
        guard width > 0, height > 0 else {
            AppLog.export.error("Export rejected: invalid dimensions \(width)×\(height)")
            throw ExportError.invalidDimensions(width: width, height: height)
        }
        let expected = width * height * Self.bytesPerPixel
        guard pixelGridData.count == expected else {
            AppLog.export.error("Export rejected: pixel data size mismatch (expected \(expected), got \(pixelGridData.count))")
            throw ExportError.invalidPixelData(expected: expected, actual: pixelGridData.count)
        }

        AppLog.export.debug("Encoding \(width)×\(height) variant as \(format.rawValue, privacy: .public)")

        let grid = try PixelGrid.fromRGBA8888(pixelGridData, width: width, height: height)

        switch format {
        case .png:
            return try encodeRaster(grid: grid, scaleFactor: scaleFactor, utType: UTType.png, format: format)
        case .heic:
            return try encodeRaster(grid: grid, scaleFactor: scaleFactor, utType: UTType.heic, format: format)
        case .ppm:
            return encodePPM(grid: grid)
        case .json:
            return try encodeJSON(grid: grid)
        }
    }

    /// Encode `variant` as `format` and write it to `url`.
    public func export(_ variant: Variant, as format: ExportFormat, to url: URL) throws {
        let bytes = try data(for: variant, format: format)
        do {
            try bytes.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(underlying: error.localizedDescription)
        }
    }

    /// Encode raw RGBA8888 pixel fields as `format` and write to `url`.
    ///
    /// Value-typed entry point usable from a detached task (avoids passing a `@Model`).
    public func export(
        width: Int,
        height: Int,
        pixelGridData: Data,
        scaleFactor: Double,
        as format: ExportFormat,
        to url: URL
    ) throws {
        let bytes = try data(
            width: width,
            height: height,
            pixelGridData: pixelGridData,
            scaleFactor: scaleFactor,
            format: format
        )
        do {
            try bytes.write(to: url, options: .atomic)
            AppLog.export.info("Exported \(format.rawValue, privacy: .public) (\(bytes.count) bytes) to \(url.lastPathComponent, privacy: .public)")
        } catch {
            AppLog.export.error("Failed to write \(format.rawValue, privacy: .public) to \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw ExportError.writeFailed(underlying: error.localizedDescription)
        }
    }

    /// Convenience overload accepting a case-insensitive format name (e.g. "PNG").
    public func export(_ variant: Variant, formatName: String, to url: URL) throws {
        guard let format = ExportFormat(name: formatName) else {
            throw ExportError.encodingFailed(format: formatName)
        }
        try export(variant, as: format, to: url)
    }

    // MARK: - Raster (PNG / HEIC)

    private func encodeRaster(grid: PixelGrid, scaleFactor: Double, utType: UTType, format: ExportFormat) throws -> Data {
        // Nearest-neighbor upscale each pixel into a scaleFactor×scaleFactor block, so the
        // exported raster preserves hard pixel edges. Shared with the on-screen thumbnails.
        let scale = max(1, Int(scaleFactor.rounded()))
        guard let image = grid.makeCGImage(scale: scale) else {
            throw ExportError.imageCreationFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            utType.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportError.encodingFailed(format: format.rawValue)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.encodingFailed(format: format.rawValue)
        }
        return output as Data
    }

    // MARK: - PPM (P6)

    /// Raw P6 portable pixmap: ASCII header `P6\n<width> <height>\n255\n` followed by
    /// binary RGB triples (alpha is dropped, as PPM has no alpha channel).
    private func encodePPM(grid: PixelGrid) -> Data {
        var data = Data()
        let header = "P6\n\(grid.width) \(grid.height)\n255\n"
        data.append(Data(header.utf8))
        data.reserveCapacity(data.count + grid.width * grid.height * 3)
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let color = grid.color(x: x, y: y)
                data.append(color.red)
                data.append(color.green)
                data.append(color.blue)
            }
        }
        return data
    }

    // MARK: - JSON color matrix

    /// JSON color matrix: `{ "width", "height", "pixels": [[ [r,g,b,a], ... ], ... ] }`
    /// where `pixels` is row-major (`pixels[y][x]`).
    private func encodeJSON(grid: PixelGrid) throws -> Data {
        var rows = [[[Int]]]()
        rows.reserveCapacity(grid.height)
        for y in 0..<grid.height {
            var row = [[Int]]()
            row.reserveCapacity(grid.width)
            for x in 0..<grid.width {
                let color = grid.color(x: x, y: y)
                row.append([Int(color.red), Int(color.green), Int(color.blue), Int(color.alpha)])
            }
            rows.append(row)
        }
        let payload: [String: Any] = [
            "width": grid.width,
            "height": grid.height,
            "pixels": rows,
        ]
        do {
            return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw ExportError.serializationFailed
        }
    }
}
