import SwiftUI

/// Bridges between `PixelColor` (SwiftUI-free, RGBA8888) and SwiftUI's
/// `Color`/`Color.Resolved` (#0076). Kept in the UI folder — `PixelColor`
/// itself stays SwiftUI-free for the `ImageProcessing` layer.
extension PixelColor {
    /// Build from unit-range sRGB components, clamping to 0...1 and
    /// rounding to the nearest 8-bit value.
    ///
    /// `Color.Resolved` components are extended-sRGB and can fall outside
    /// 0...1 (e.g. wide-gamut colors), so this clamps before quantizing.
    init(red01: Double, green01: Double, blue01: Double, opacity01: Double) {
        func quantize(_ value: Double) -> UInt8 {
            let clamped = min(max(value, 0.0), 1.0)
            return UInt8((clamped * 255.0).rounded())
        }
        self.init(
            red: quantize(red01),
            green: quantize(green01),
            blue: quantize(blue01),
            alpha: quantize(opacity01)
        )
    }

    /// Build from a resolved SwiftUI `Color` (obtained via
    /// `color.resolve(in: environment)`), forwarding into the clamping
    /// unit-range initializer above.
    init(resolved: Color.Resolved) {
        self.init(
            red01: Double(resolved.red),
            green01: Double(resolved.green),
            blue01: Double(resolved.blue),
            opacity01: Double(resolved.opacity)
        )
    }

    /// The SwiftUI `Color` equivalent of this pixel, used to render the grid,
    /// seed the color picker, and draw swatches.
    var swiftUIColor: Color {
        Color(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: Double(alpha) / 255.0
        )
    }
}
