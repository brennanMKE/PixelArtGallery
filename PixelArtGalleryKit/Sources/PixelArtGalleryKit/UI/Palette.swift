import SwiftUI

/// The vibrant pixel-art palette shared with PixelArtConverter: four saturated
/// hues used for the animated background, the app accent, and the animated block.
/// `nonisolated` (the package default-isolates to `@MainActor`) so these pure
/// color constants stay reachable from `PixelWallpaperStyle.palette(isDark:)`,
/// which is itself `nonisolated` for testability off the main actor (#0070).
nonisolated extension Color {
    static let pixelColor1 = Color(red: 0.969, green: 0.725, blue: 0.0)   // F7B900 gold
    static let pixelColor2 = Color(red: 0.808, green: 0.024, blue: 0.659) // CE06A8 magenta
    static let pixelColor3 = Color(red: 0.035, green: 0.808, blue: 0.027) // 09CE07 green
    static let pixelColor4 = Color(red: 0.808, green: 0.047, blue: 0.020) // CE0C05 red

    static let pixelColors: [Color] = [pixelColor1, pixelColor2, pixelColor3, pixelColor4]

    /// The app's accent — the gold reads well against both light and dark.
    static let pixelAccent = pixelColor1

    /// Softer tints for the light-mode background wallpaper.
    static let lighterPixelColors: [Color] = [
        pixelColor1.lighter(), pixelColor2.lighter(), pixelColor3.lighter(), pixelColor4.lighter(),
    ]

    /// Deeper tints for the dark-mode background wallpaper.
    static let darkerPixelColors: [Color] = [
        pixelColor1.darker(), pixelColor2.darker(), pixelColor3.darker(), pixelColor4.darker(),
    ]

    func lighter() -> Color { Color.white.mix(with: self, by: 0.35) }
    func darker() -> Color { Color.black.mix(with: self, by: 0.35) }

    /// Plain system background that follows light/dark mode — the matte
    /// backdrop for content areas (behind the gallery grid/empty state),
    /// as opposed to the pixel wallpaper used in the banner (#0070).
    static var matteBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}
