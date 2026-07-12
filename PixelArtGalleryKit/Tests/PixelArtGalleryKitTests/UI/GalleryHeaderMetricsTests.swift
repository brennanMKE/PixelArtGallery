import CoreGraphics
import Testing
@testable import PixelArtGalleryKit

/// Tests for the pure, `nonisolated` interpolation math behind the gallery's
/// collapsing header (#0072) — linear, clamped, monotonic in scroll offset.
@Suite struct GalleryHeaderMetricsTests {
    @Test func atRestIsFullyExpanded() {
        #expect(GalleryHeaderMetrics.height(forScrollOffset: 0) == GalleryHeaderMetrics.expandedHeight)
        #expect(GalleryHeaderMetrics.titleSize(forScrollOffset: 0) == GalleryHeaderMetrics.expandedTitleSize)
        #expect(GalleryHeaderMetrics.progress(forScrollOffset: 0) == 0)
    }

    @Test func rubberBandingPastTheTopClampsToExpanded() {
        #expect(GalleryHeaderMetrics.height(forScrollOffset: -50) == GalleryHeaderMetrics.expandedHeight)
        #expect(GalleryHeaderMetrics.titleSize(forScrollOffset: -50) == GalleryHeaderMetrics.expandedTitleSize)
        #expect(GalleryHeaderMetrics.progress(forScrollOffset: -50) == 0)
    }

    @Test func atCollapseRangeIsFullyCompact() {
        let offset = GalleryHeaderMetrics.collapseRange
        #expect(GalleryHeaderMetrics.height(forScrollOffset: offset) == GalleryHeaderMetrics.compactHeight)
        #expect(GalleryHeaderMetrics.titleSize(forScrollOffset: offset) == GalleryHeaderMetrics.compactTitleSize)
        #expect(GalleryHeaderMetrics.progress(forScrollOffset: offset) == 1)
    }

    @Test func beyondCollapseRangeStaysClampedCompact() {
        #expect(GalleryHeaderMetrics.height(forScrollOffset: 500) == GalleryHeaderMetrics.compactHeight)
        #expect(GalleryHeaderMetrics.titleSize(forScrollOffset: 500) == GalleryHeaderMetrics.compactTitleSize)
        #expect(GalleryHeaderMetrics.progress(forScrollOffset: 500) == 1)
    }

    @Test func midpointInterpolatesLinearly() {
        let offset = GalleryHeaderMetrics.collapseRange / 2 // 36
        #expect(GalleryHeaderMetrics.progress(forScrollOffset: offset) == 0.5)
        #expect(GalleryHeaderMetrics.height(forScrollOffset: offset) == 92) // (128 + 56) / 2
        #expect(GalleryHeaderMetrics.titleSize(forScrollOffset: offset) == 25.5) // (34 + 17) / 2
    }

    @Test func heightAndTitleSizeStayMonotonicNonIncreasingAndInBounds() {
        var previousHeight = GalleryHeaderMetrics.height(forScrollOffset: -20)
        var previousTitleSize = GalleryHeaderMetrics.titleSize(forScrollOffset: -20)

        for offsetTenths in stride(from: -200, through: 1200, by: 1) {
            let offset = CGFloat(offsetTenths) / 10 // -20...120 in 0.1 steps
            let height = GalleryHeaderMetrics.height(forScrollOffset: offset)
            let titleSize = GalleryHeaderMetrics.titleSize(forScrollOffset: offset)

            #expect(height <= previousHeight)
            #expect(titleSize <= previousTitleSize)
            #expect(height >= GalleryHeaderMetrics.compactHeight && height <= GalleryHeaderMetrics.expandedHeight)
            #expect(titleSize >= GalleryHeaderMetrics.compactTitleSize && titleSize <= GalleryHeaderMetrics.expandedTitleSize)

            previousHeight = height
            previousTitleSize = titleSize
        }
    }
}
