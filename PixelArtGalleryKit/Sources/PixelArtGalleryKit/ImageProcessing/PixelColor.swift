import Foundation

/// A single pixel's color expressed as 8-bit RGBA channels.
nonisolated public struct PixelColor: Equatable, Hashable, Sendable {
    /// Red channel (0–255)
    public var red: UInt8
    /// Green channel (0–255)
    public var green: UInt8
    /// Blue channel (0–255)
    public var blue: UInt8
    /// Alpha channel (0–255, 255 = fully opaque)
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Opaque black.
    public static let black = PixelColor(red: 0, green: 0, blue: 0, alpha: 255)

    /// Opaque white.
    public static let white = PixelColor(red: 255, green: 255, blue: 255, alpha: 255)

    /// Fully transparent.
    public static let clear = PixelColor(red: 0, green: 0, blue: 0, alpha: 0)
}
