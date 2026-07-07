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
