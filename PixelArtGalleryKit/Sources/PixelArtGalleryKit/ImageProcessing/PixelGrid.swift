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

    /// Convert an RGBA8888 buffer to grayscale: each `(r, g, b, a)` pixel
    /// becomes `(y, y, y, a)` where `y = round(0.299·r + 0.587·g + 0.114·b)` —
    /// the Rec.601 luminance formula used by ft-swift's `grayscale` demo
    /// (`Sources/grayscale/Grayscale.swift`), sent over the same P6 PPM wire
    /// format as an ordinary send. Alpha is preserved; black stays black
    /// (transparent on FT layers 1–15). Buffer length is unchanged.
    ///
    /// Rounding (not truncating) is a deliberate departure from ft-swift's
    /// truncating `UInt8(...)` cast (which would map pure green to 149) —
    /// this rounds to 150 per this feature's spec, and rounding is also what
    /// makes the transform idempotent: an already-gray pixel's weighted sum
    /// can land a hair under its own value in floating point, and truncating
    /// would drift it down by 1 on re-application, while rounding maps it
    /// back to exactly itself. Overflow past 255 is impossible since the
    /// coefficients sum to exactly 1.0 (white's sum is exactly 255.0).
    ///
    /// Operates directly on the raw buffer (no `PixelGrid` round-trip) for
    /// speed. Any trailing bytes shorter than a full pixel (shouldn't occur
    /// for a valid grid) are copied through unchanged. Empty `Data` returns
    /// empty `Data`.
    public static func grayscale(rgba8888 data: Data) -> Data {
        var bytes = [UInt8](data)
        var index = 0
        while index + Self.bytesPerPixel <= bytes.count {
            let r = Double(bytes[index])
            let g = Double(bytes[index + 1])
            let b = Double(bytes[index + 2])
            let y = UInt8((0.299 * r + 0.587 * g + 0.114 * b).rounded())
            bytes[index] = y
            bytes[index + 1] = y
            bytes[index + 2] = y
            // bytes[index + 3] (alpha) is left untouched.
            index += Self.bytesPerPixel
        }
        return Data(bytes)
    }
}
