import Testing
import SwiftUI
@testable import PixelArtGalleryKit

/// Tests for the `PixelColor` <-> SwiftUI `Color` bridge (#0076).
@MainActor
@Suite struct PixelColorBridgeTests {
    /// The clamping unit-range initializer quantizes correctly at known
    /// boundary values.
    @Test func unitRangeInitializerQuantizes() {
        let black = PixelColor(red01: 0, green01: 0, blue01: 0, opacity01: 0)
        #expect(black.red == 0)
        #expect(black.green == 0)
        #expect(black.blue == 0)
        #expect(black.alpha == 0)

        let white = PixelColor(red01: 1, green01: 1, blue01: 1, opacity01: 1)
        #expect(white.red == 255)
        #expect(white.green == 255)
        #expect(white.blue == 255)
        #expect(white.alpha == 255)

        let mid = PixelColor(red01: 0.5, green01: 0.5, blue01: 0.5, opacity01: 0.5)
        #expect(mid.red == 128)
        #expect(mid.green == 128)
        #expect(mid.blue == 128)
        #expect(mid.alpha == 128)
    }

    /// Out-of-range components (extended-sRGB can produce these) are clamped
    /// rather than wrapping or crashing.
    @Test func unitRangeInitializerClampsOutOfRangeInputs() {
        let clampedLow = PixelColor(red01: -0.1, green01: -5, blue01: 0, opacity01: 1)
        #expect(clampedLow.red == 0)
        #expect(clampedLow.green == 0)

        let clampedHigh = PixelColor(red01: 1.2, green01: 10, blue01: 1, opacity01: 1)
        #expect(clampedHigh.red == 255)
        #expect(clampedHigh.green == 255)
    }

    /// A known `Color` resolves to the expected RGBA `PixelColor` via the
    /// `Color.Resolved` bridge.
    @Test func resolvedBridgeMatchesKnownColor() {
        let color = Color(red: 1, green: 0, blue: 0)
        let resolved = color.resolve(in: EnvironmentValues())
        let pixel = PixelColor(resolved: resolved)

        #expect(pixel.red == 255)
        #expect(pixel.green == 0)
        #expect(pixel.blue == 0)
        #expect(pixel.alpha == 255)
    }

    /// `PixelColor.swiftUIColor` resolved back matches the original components.
    @Test func swiftUIColorRoundTripsBackToPixelColor() {
        let original = PixelColor(red: 12, green: 200, blue: 64, alpha: 255)
        let resolved = original.swiftUIColor.resolve(in: EnvironmentValues())
        let roundTripped = PixelColor(resolved: resolved)

        #expect(roundTripped == original)
    }
}
