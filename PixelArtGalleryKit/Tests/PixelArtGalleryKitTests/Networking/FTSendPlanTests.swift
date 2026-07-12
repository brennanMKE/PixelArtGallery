import Testing
import Foundation
@testable import PixelArtGalleryKit

/// Tests for ``FTSendPlan/make(preview:host:port:layer:displayOffsetX:displayOffsetY:)``,
/// the pure assembly of send parameters for a transient ``FittedPreview``
/// (#0067). Locks in the send-offset convention: the final paint offset is
/// the preview's centering offset **plus** the display's stored default
/// offset (per #0066's `FittedPreview.offsetX`/`offsetY` doc comment), and
/// the layer is the display's stored layer, clamped.
@Suite struct FTSendPlanTests {
    private func preview(
        offsetX: Int = 6, offsetY: Int = 3, width: Int = 32, height: Int = 24
    ) -> FittedPreview {
        FittedPreview(
            itemID: UUID(),
            displayID: UUID(),
            width: width,
            height: height,
            pixelGridData: Data(repeating: 0xAB, count: width * height * 4),
            offsetX: offsetX,
            offsetY: offsetY
        )
    }

    // MARK: - Payload

    @Test func payloadCarriesThePreviewsFitDimensionsAndGridVerbatim() {
        let source = preview(width: 32, height: 24)
        let plan = FTSendPlan.make(
            preview: source, host: "ft.local", port: 1337,
            layer: 5, displayOffsetX: 0, displayOffsetY: 0
        )

        #expect(plan.payload.width == 32)
        #expect(plan.payload.height == 24)
        #expect(plan.payload.pixelGridData == source.pixelGridData)
        #expect(plan.payload.host == "ft.local")
        #expect(plan.payload.port == 1337)
        #expect(plan.payload.scaleFactor == 1.0, "A FittedPreview is always native scale")
    }

    // MARK: - Offset: centering + stored, additive

    @Test func offsetIsThePreviewsCenteringOffsetWhenTheDisplayHasNoStoredOffset() {
        let source = preview(offsetX: 6, offsetY: 3)
        let plan = FTSendPlan.make(
            preview: source, host: "ft.local", port: 1337,
            layer: 5, displayOffsetX: 0, displayOffsetY: 0
        )

        // With a zero stored default (the common case), the fitted image
        // still lands exactly centered.
        #expect(plan.offset.x == 6)
        #expect(plan.offset.y == 3)
    }

    @Test func offsetAddsTheDisplaysStoredOffsetToTheCenteringOffset() {
        let source = preview(offsetX: 6, offsetY: 3)
        let plan = FTSendPlan.make(
            preview: source, host: "ft.local", port: 1337,
            layer: 5, displayOffsetX: 10, displayOffsetY: 20
        )

        #expect(plan.offset.x == 16, "6 (centering) + 10 (stored) = 16")
        #expect(plan.offset.y == 23, "3 (centering) + 20 (stored) = 23")
    }

    @Test func negativeStoredOffsetIsClampedToZeroBeforeSumming() {
        let source = preview(offsetX: 6, offsetY: 3)
        let plan = FTSendPlan.make(
            preview: source, host: "ft.local", port: 1337,
            layer: 5, displayOffsetX: -100, displayOffsetY: -50
        )

        #expect(plan.offset.x == 6, "A negative stored offset clamps to 0, leaving just the centering offset")
        #expect(plan.offset.y == 3)
    }

    // MARK: - Layer clamping

    @Test func layerIsCarriedThroughUnchangedWhenAlreadyInRange() {
        let plan = FTSendPlan.make(
            preview: preview(), host: "ft.local", port: 1337,
            layer: 9, displayOffsetX: 0, displayOffsetY: 0
        )
        #expect(plan.offset.z == 9)
    }

    @Test func outOfRangeLayerIsClampedIntoOneThroughFifteen() {
        let tooHigh = FTSendPlan.make(
            preview: preview(), host: "ft.local", port: 1337,
            layer: 99, displayOffsetX: 0, displayOffsetY: 0
        )
        #expect(tooHigh.offset.z == FlaschenTaschenDisplay.layerRange.upperBound)

        let tooLow = FTSendPlan.make(
            preview: preview(), host: "ft.local", port: 1337,
            layer: 0, displayOffsetX: 0, displayOffsetY: 0
        )
        #expect(tooLow.offset.z == FlaschenTaschenDisplay.layerRange.lowerBound)
    }
}
