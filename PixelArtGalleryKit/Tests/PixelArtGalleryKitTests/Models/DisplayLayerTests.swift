import Testing
@testable import PixelArtGalleryKit

/// Layer (FT z-offset) rules for a display (#0047): default 5, valid range 1…15,
/// and never 0.
@MainActor
@Suite struct DisplayLayerTests {
    @Test func defaultLayerIsFive() {
        #expect(FlaschenTaschenDisplay.defaultLayer == 5)
    }

    @Test func layerRangeIsOneThroughFifteen() {
        #expect(FlaschenTaschenDisplay.layerRange.lowerBound == 1)
        #expect(FlaschenTaschenDisplay.layerRange.upperBound == 15)
        #expect(!FlaschenTaschenDisplay.layerRange.contains(0), "Layer 0 is reserved and must never be valid")
    }

    @Test(arguments: [
        (0, 1),    // never 0 — clamps up to the minimum
        (-3, 1),
        (1, 1),
        (5, 5),
        (15, 15),
        (16, 15),  // above range clamps down to the maximum
        (999, 15),
    ])
    func clampedLayerKeepsValuesInRange(input: Int, expected: Int) {
        #expect(FlaschenTaschenDisplay.clampedLayer(input) == expected)
    }

    @Test func initDefaultsToDefaultLayer() {
        let display = FlaschenTaschenDisplay(
            host: "ft.local", port: 1337, displayName: "FT", displayWidth: 45, displayHeight: 35
        )
        #expect(display.layer == FlaschenTaschenDisplay.defaultLayer)
    }

    @Test func initClampsOutOfRangeLayer() {
        let tooLow = FlaschenTaschenDisplay(
            host: "ft.local", port: 1337, displayName: "FT", displayWidth: 45, displayHeight: 35, layer: 0
        )
        #expect(tooLow.layer == 1, "Layer 0 must be clamped to the 1…15 minimum")

        let tooHigh = FlaschenTaschenDisplay(
            host: "ft.local", port: 1337, displayName: "FT", displayWidth: 45, displayHeight: 35, layer: 42
        )
        #expect(tooHigh.layer == 15)
    }

    @Test func builtInDefaultDisplayUsesDefaultLayer() {
        #expect(FlaschenTaschenDisplay.makeDefault().layer == FlaschenTaschenDisplay.defaultLayer)
    }
}

/// Default x/y paint offset rules for a display (#0056): inline `0` default
/// for migration safety, and clamping to non-negative.
@MainActor
@Suite struct DisplayOffsetTests {
    @Test func initDefaultsOffsetsToZero() {
        let display = FlaschenTaschenDisplay(
            host: "ft.local", port: 1337, displayName: "FT", displayWidth: 45, displayHeight: 35
        )
        #expect(display.offsetX == 0)
        #expect(display.offsetY == 0, "Pre-existing records (and new ones without explicit offsets) must default to the un-offset origin")
    }

    @Test func initHonorsExplicitOffsets() {
        let display = FlaschenTaschenDisplay(
            host: "ft.local", port: 1337, displayName: "FT", displayWidth: 45, displayHeight: 35,
            offsetX: 10, offsetY: 20
        )
        #expect(display.offsetX == 10)
        #expect(display.offsetY == 20)
    }

    @Test(arguments: [
        (0, 0),
        (5, 5),
        (-1, 0),   // negative clamps up to 0
        (-100, 0),
    ])
    func clampedOffsetKeepsValuesNonNegative(input: Int, expected: Int) {
        #expect(FlaschenTaschenDisplay.clampedOffset(input) == expected)
    }

    @Test func initClampsNegativeOffsets() {
        let display = FlaschenTaschenDisplay(
            host: "ft.local", port: 1337, displayName: "FT", displayWidth: 45, displayHeight: 35,
            offsetX: -5, offsetY: -9
        )
        #expect(display.offsetX == 0)
        #expect(display.offsetY == 0)
    }

    @Test func builtInDefaultDisplayUsesZeroOffsets() {
        let display = FlaschenTaschenDisplay.makeDefault()
        #expect(display.offsetX == 0)
        #expect(display.offsetY == 0)
    }
}
