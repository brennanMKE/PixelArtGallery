import Foundation

/// Errors thrown while converting to/from raw pixel buffers.
nonisolated public enum PixelGridError: Error, Equatable {
    /// The supplied data length does not match `width * height * 4` bytes.
    case invalidDataSize(expected: Int, actual: Int)
    /// The supplied dimensions are not positive.
    case invalidDimensions(width: Int, height: Int)
}

/// A 2D grid of `PixelColor` values backed by a row-major layout.
///
/// `colors[y][x]` addresses the pixel at column `x`, row `y`.
nonisolated public struct PixelGrid: Equatable, Sendable {
    /// Grid width in pixels.
    public let width: Int
    /// Grid height in pixels.
    public let height: Int
    /// Row-major rows of pixels: `colors[y][x]`.
    public private(set) var colors: [[PixelColor]]

    /// Number of bytes per pixel in the RGBA8888 layout.
    private static let bytesPerPixel = 4

    /// Create a grid filled with a single color (opaque black by default).
    public init(width: Int, height: Int, fill: PixelColor = .black) {
        self.width = max(0, width)
        self.height = max(0, height)
        let row = Array(repeating: fill, count: self.width)
        self.colors = Array(repeating: row, count: self.height)
    }

    /// Create a grid from existing rows.
    /// - Note: Each row must have `width` entries and there must be `height` rows.
    public init(width: Int, height: Int, colors: [[PixelColor]]) {
        self.width = width
        self.height = height
        self.colors = colors
    }

    /// The color at the given coordinate, or `.black` if out of bounds.
    public func color(x: Int, y: Int) -> PixelColor {
        guard y >= 0, y < colors.count, x >= 0, x < colors[y].count else {
            return .black
        }
        return colors[y][x]
    }

    /// Set the color at the given coordinate (no-op if out of bounds).
    public mutating func setColor(_ color: PixelColor, x: Int, y: Int) {
        guard y >= 0, y < colors.count, x >= 0, x < colors[y].count else { return }
        colors[y][x] = color
    }

    /// Flatten the grid into an RGBA8888 byte buffer in row-major order.
    public func toRGBA8888() -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * Self.bytesPerPixel)
        for row in colors {
            for pixel in row {
                bytes.append(pixel.red)
                bytes.append(pixel.green)
                bytes.append(pixel.blue)
                bytes.append(pixel.alpha)
            }
        }
        return Data(bytes)
    }

    /// Build a grid from an RGBA8888 byte buffer in row-major order.
    /// - Throws: `PixelGridError` if the dimensions or data length are invalid.
    public static func fromRGBA8888(_ data: Data, width: Int, height: Int) throws -> PixelGrid {
        guard width > 0, height > 0 else {
            throw PixelGridError.invalidDimensions(width: width, height: height)
        }
        let expected = width * height * bytesPerPixel
        guard data.count == expected else {
            throw PixelGridError.invalidDataSize(expected: expected, actual: data.count)
        }

        let buffer = [UInt8](data)
        var rows = [[PixelColor]]()
        rows.reserveCapacity(height)
        for y in 0..<height {
            var row = [PixelColor]()
            row.reserveCapacity(width)
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
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
        return PixelGrid(width: width, height: height, colors: rows)
    }
}
