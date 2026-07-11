import Testing
@testable import PixelArtGalleryKit

/// Tests for the pure offset-clamping helper (#0064) that bounds a display's
/// x/y send offsets so `offset + imageDimension <= displayDimension` — a
/// manual nudge during a send can never push the painted image off the
/// display's edge.
@Suite struct DisplayOffsetRangeTests {
    @Test func imageSmallerThanDisplayAllowsFullSlack() {
        let range = FlaschenTaschenDisplay.offsetRange(displayDimension: 45, imageDimension: 20)
        #expect(range == 0...25)
    }

    @Test func imageExactlyFillingDisplayCollapsesToZero() {
        let range = FlaschenTaschenDisplay.offsetRange(displayDimension: 45, imageDimension: 45)
        #expect(range == 0...0)
    }

    @Test func imageLargerThanDisplayCollapsesToZero() {
        let range = FlaschenTaschenDisplay.offsetRange(displayDimension: 32, imageDimension: 100)
        #expect(range == 0...0)
    }

    @Test func oneOffImageLeavesExactlyOneStepOfSlack() {
        let range = FlaschenTaschenDisplay.offsetRange(displayDimension: 45, imageDimension: 44)
        #expect(range == 0...1)
    }

    @Test func zeroDimensionsCollapseToZero() {
        let range = FlaschenTaschenDisplay.offsetRange(displayDimension: 0, imageDimension: 0)
        #expect(range == 0...0)
    }

    /// Exhaustive sweep: the range always starts at 0, and whenever the image
    /// fits (imageDimension <= displayDimension) every offset in the range
    /// keeps `offset + imageDimension <= displayDimension` — the containment
    /// invariant a manual nudge must never violate. When the image is already
    /// oversized the range collapses to `0...0` (checked separately above).
    @Test func invariantHoldsExhaustively() {
        for displayDimension in 1...16 {
            for imageDimension in 1...16 {
                let range = FlaschenTaschenDisplay.offsetRange(
                    displayDimension: displayDimension, imageDimension: imageDimension
                )
                #expect(range.lowerBound == 0)
                guard imageDimension <= displayDimension else {
                    #expect(range == 0...0)
                    continue
                }
                for offset in range {
                    #expect(offset + imageDimension <= displayDimension)
                }
            }
        }
    }
}
