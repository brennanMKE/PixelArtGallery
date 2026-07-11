import Testing
@testable import PixelArtGalleryKit

/// Tests for the pure aspect-fit + centering math (#0062), the foundation for
/// the display-first flow (#0061). Covers landscape/portrait sources, exact
/// aspect matches, the small-source "contain, scale up" policy, degenerate
/// inputs, and an exhaustive sweep proving the `offset + fit <= display`
/// invariant holds for every small integer combination.
@Suite struct AspectFitTests {
    @Test func landscapeIntoSquare() {
        let placement = AspectFit.fit(sourceWidth: 200, sourceHeight: 100, displayWidth: 64, displayHeight: 64)
        #expect(placement == AspectFit.Placement(width: 64, height: 32, offsetX: 0, offsetY: 16))
    }

    @Test func portraitIntoWide() {
        let placement = AspectFit.fit(sourceWidth: 100, sourceHeight: 200, displayWidth: 64, displayHeight: 32)
        #expect(placement == AspectFit.Placement(width: 16, height: 32, offsetX: 24, offsetY: 0))
    }

    @Test func exactAspectMatch() {
        let samesize = AspectFit.fit(sourceWidth: 128, sourceHeight: 64, displayWidth: 128, displayHeight: 64)
        #expect(samesize == AspectFit.Placement(width: 128, height: 64, offsetX: 0, offsetY: 0))

        let scaled = AspectFit.fit(sourceWidth: 64, sourceHeight: 32, displayWidth: 128, displayHeight: 64)
        #expect(scaled == AspectFit.Placement(width: 128, height: 64, offsetX: 0, offsetY: 0))
    }

    /// Small-source policy: a source smaller than the display is enlarged
    /// ("contain, scale up") rather than left at its native size. This also
    /// doubles as an asymmetric-rounding case: 45 * 5 / 10 = 22.5 floors to
    /// 22, and the resulting offset (35 - 22) / 2 = 6 still satisfies the
    /// containment invariant (6 + 22 <= 35).
    @Test func smallerSourceScalesUp() {
        let placement = AspectFit.fit(sourceWidth: 10, sourceHeight: 5, displayWidth: 45, displayHeight: 35)
        #expect(placement == AspectFit.Placement(width: 45, height: 22, offsetX: 0, offsetY: 6))
        #expect(placement.offsetY + placement.height <= 35)
    }

    @Test func oneByOneDisplay() {
        let placement = AspectFit.fit(sourceWidth: 200, sourceHeight: 37, displayWidth: 1, displayHeight: 1)
        #expect(placement == AspectFit.Placement(width: 1, height: 1, offsetX: 0, offsetY: 0))
    }

    /// An extreme aspect ratio would floor the bound axis to 0; the `max(1, …)`
    /// clamp keeps it at 1 while the invariant still holds.
    @Test func extremeAspectClampsToOne() {
        let placement = AspectFit.fit(sourceWidth: 100, sourceHeight: 1, displayWidth: 10, displayHeight: 10)
        #expect(placement == AspectFit.Placement(width: 10, height: 1, offsetX: 0, offsetY: 4))
    }

    /// Zero/negative source or display dimensions must not crash — every
    /// input is clamped to >= 1 before any math runs.
    @Test func degenerateInputsAreClamped() {
        let zeroSource = AspectFit.fit(sourceWidth: 0, sourceHeight: 0, displayWidth: 32, displayHeight: 32)
        #expect(zeroSource.width >= 1 && zeroSource.height >= 1)
        #expect(zeroSource.offsetX >= 0 && zeroSource.offsetY >= 0)
        #expect(zeroSource.offsetX + zeroSource.width <= 32)
        #expect(zeroSource.offsetY + zeroSource.height <= 32)

        let zeroAndNegativeDisplay = AspectFit.fit(sourceWidth: 100, sourceHeight: 50, displayWidth: 0, displayHeight: -3)
        #expect(zeroAndNegativeDisplay.width >= 1 && zeroAndNegativeDisplay.height >= 1)
        #expect(zeroAndNegativeDisplay.offsetX >= 0 && zeroAndNegativeDisplay.offsetY >= 0)
        #expect(zeroAndNegativeDisplay.offsetX + zeroAndNegativeDisplay.width <= 1)
        #expect(zeroAndNegativeDisplay.offsetY + zeroAndNegativeDisplay.height <= 1)
    }

    /// Exhaustive sweep over small source/display combinations: for every
    /// pairing, the fit dims must be >= 1, offsets >= 0, containment must
    /// hold (`offset + fit <= display`), and the fit must be tight against at
    /// least one axis of the display (it's a "contain" fit, not shrunk below
    /// what's necessary). This is the explicit rounding proof the issue asks for.
    @Test func invariantHoldsExhaustively() {
        for srcW in 1...16 {
            for srcH in 1...16 {
                for dispW in 1...16 {
                    for dispH in 1...16 {
                        let placement = AspectFit.fit(
                            sourceWidth: srcW, sourceHeight: srcH,
                            displayWidth: dispW, displayHeight: dispH
                        )
                        #expect(placement.width >= 1)
                        #expect(placement.height >= 1)
                        #expect(placement.offsetX >= 0)
                        #expect(placement.offsetY >= 0)
                        #expect(placement.offsetX + placement.width <= dispW)
                        #expect(placement.offsetY + placement.height <= dispH)
                        #expect(placement.width == dispW || placement.height == dispH)
                    }
                }
            }
        }
    }

    // MARK: - centeringOffset

    @Test func centeringOffsetMatchesFitOffsets() {
        let offset = AspectFit.centeringOffset(imageWidth: 64, imageHeight: 32, displayWidth: 64, displayHeight: 64)
        #expect(offset.x == 0)
        #expect(offset.y == 16)
    }

    @Test func centeringOffsetClampsOversizedImageToZero() {
        // An image already larger than the display (never produced by `fit`,
        // but a manually-chosen size might) must not yield a negative offset.
        let offset = AspectFit.centeringOffset(imageWidth: 100, imageHeight: 100, displayWidth: 32, displayHeight: 32)
        #expect(offset.x == 0)
        #expect(offset.y == 0)
    }
}
