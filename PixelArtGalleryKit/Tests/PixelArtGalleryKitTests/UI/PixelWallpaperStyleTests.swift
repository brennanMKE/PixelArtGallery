import SwiftUI
import Testing
@testable import PixelArtGalleryKit

/// Tests for the pure, `nonisolated` palette/opacity selector that scopes the
/// gallery banner's vibrancy without disturbing `BackgroundPixelsView`'s
/// existing subtle default (#0070).
@Suite struct PixelWallpaperStyleTests {
    @Test func vibrantUsesFullStrengthPaletteInLightMode() {
        #expect(PixelWallpaperStyle.vibrant.palette(isDark: false) == Color.pixelColors)
    }

    @Test func vibrantUsesFullStrengthPaletteInDarkMode() {
        #expect(PixelWallpaperStyle.vibrant.palette(isDark: true) == Color.pixelColors)
    }

    @Test func vibrantDefaultOpacityIsFullyOpaque() {
        #expect(PixelWallpaperStyle.vibrant.defaultOpacity == 1.0)
    }

    @Test func subtleUsesLighterTintsInLightMode() {
        #expect(PixelWallpaperStyle.subtle.palette(isDark: false) == Color.lighterPixelColors)
    }

    @Test func subtleUsesDarkerTintsInDarkMode() {
        #expect(PixelWallpaperStyle.subtle.palette(isDark: true) == Color.darkerPixelColors)
    }

    @Test func subtleDefaultOpacityMatchesTheOriginalWallpaper() {
        #expect(PixelWallpaperStyle.subtle.defaultOpacity == 0.5)
    }
}
