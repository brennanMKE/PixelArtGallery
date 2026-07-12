import CoreGraphics

/// Pure interpolation math for the gallery's collapsing header (#0072): given
/// how far the content has scrolled, how tall the header should be and how
/// large its title should render. A pure, `nonisolated` helper — like
/// ``PixelWallpaperStyle`` — so it stays cheaply testable off the main actor
/// even though the package default-isolates to `@MainActor`.
nonisolated enum GalleryHeaderMetrics {
    /// The header's height at rest — matches the original fixed banner (#0070).
    static let expandedHeight: CGFloat = 128
    /// The pinned header's height once fully collapsed.
    static let compactHeight: CGFloat = 56
    /// The title's point size at rest (`.largeTitle`-equivalent).
    static let expandedTitleSize: CGFloat = 34
    /// The title's point size once fully collapsed (`.headline`-sized).
    static let compactTitleSize: CGFloat = 17

    /// Scroll distance over which the header collapses from expanded to compact.
    static var collapseRange: CGFloat { expandedHeight - compactHeight } // 72

    /// `0` at rest (or rubber-banding past the top) → `1` once fully collapsed.
    /// Clamped at both ends so callers never see out-of-range values.
    static func progress(forScrollOffset offset: CGFloat) -> CGFloat {
        min(max(offset / collapseRange, 0), 1)
    }

    /// The header's current height for the given scroll offset — linearly
    /// interpolated between ``expandedHeight`` and ``compactHeight``, clamped
    /// and monotonically non-increasing as the offset grows.
    static func height(forScrollOffset offset: CGFloat) -> CGFloat {
        expandedHeight - (expandedHeight - compactHeight) * progress(forScrollOffset: offset)
    }

    /// The title's current point size for the given scroll offset — linearly
    /// interpolated between ``expandedTitleSize`` and ``compactTitleSize``.
    static func titleSize(forScrollOffset offset: CGFloat) -> CGFloat {
        expandedTitleSize - (expandedTitleSize - compactTitleSize) * progress(forScrollOffset: offset)
    }
}
