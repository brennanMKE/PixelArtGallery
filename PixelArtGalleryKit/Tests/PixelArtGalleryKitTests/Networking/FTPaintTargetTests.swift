import Testing
@testable import PixelArtGalleryKit

/// Tests for the pure layer/offset comparison that decides whether the
/// continuous-send loop must clear an old target before painting a new one
/// (#0057). This is exactly the decision the loop makes each frame once
/// layer/x/y become live-editable during a send — factored out here so it's
/// testable without the SwiftUI view or a real network client.
@Suite struct FTPaintTargetTests {
    private func target(layer: Int, offsetX: Int, offsetY: Int) -> FTPaintTarget {
        FTPaintTarget(
            host: "ft.local", port: 1337, width: 32, height: 32, scaleFactor: 1.0,
            layer: layer, offsetX: offsetX, offsetY: offsetY
        )
    }

    // MARK: - requiresClear

    @Test func noClearWhenLayerAndOffsetUnchanged() {
        let previous = target(layer: 5, offsetX: 3, offsetY: 4)
        #expect(!previous.requiresClear(beforePaintingLayer: 5, offsetX: 3, offsetY: 4),
                "Repainting the same layer/offset every frame must not trigger a clear")
    }

    @Test func clearRequiredWhenLayerChanges() {
        let previous = target(layer: 5, offsetX: 3, offsetY: 4)
        #expect(previous.requiresClear(beforePaintingLayer: 6, offsetX: 3, offsetY: 4),
                "Switching layer mid-send must strand the old layer without a clear")
    }

    @Test func clearRequiredWhenOffsetXChanges() {
        let previous = target(layer: 5, offsetX: 3, offsetY: 4)
        #expect(previous.requiresClear(beforePaintingLayer: 5, offsetX: 10, offsetY: 4))
    }

    @Test func clearRequiredWhenOffsetYChanges() {
        let previous = target(layer: 5, offsetX: 3, offsetY: 4)
        #expect(previous.requiresClear(beforePaintingLayer: 5, offsetX: 3, offsetY: 20))
    }

    @Test func clearRequiredWhenBothLayerAndOffsetChange() {
        let previous = target(layer: 5, offsetX: 3, offsetY: 4)
        #expect(previous.requiresClear(beforePaintingLayer: 9, offsetX: 0, offsetY: 0))
    }

    // MARK: - painted

    @Test func paintedUpdatesLayerAndOffsetOnly() {
        let previous = target(layer: 5, offsetX: 3, offsetY: 4)
        let next = previous.painted(layer: 9, offsetX: 12, offsetY: 1)

        #expect(next.layer == 9)
        #expect(next.offsetX == 12)
        #expect(next.offsetY == 1)
        #expect(next.host == previous.host, "Endpoint must be carried over unchanged")
        #expect(next.port == previous.port)
        #expect(next.width == previous.width, "Geometry must be carried over unchanged")
        #expect(next.height == previous.height)
        #expect(next.scaleFactor == previous.scaleFactor)
    }

    // MARK: - Simulated per-frame decision (mirrors the send loop in VariantDetailView)

    /// Walks a sequence of (layer, x, y) frames the way the continuous-send
    /// loop does, recording which frames triggered a clear of the *previous*
    /// target before painting. Confirms a layer/offset change produces a
    /// clear-then-paint, and an unchanged frame paints with no clear.
    @Test func sequenceOfFramesClearsOnlyOnChange() {
        var painted: FTPaintTarget?
        var clearedTargets: [FTPaintTarget] = []

        let frames: [(layer: Int, offsetX: Int, offsetY: Int)] = [
            (5, 0, 0),   // first frame: nothing painted yet, no clear
            (5, 0, 0),   // unchanged: no clear
            (7, 0, 0),   // layer switch: clear old layer 5 @ (0,0)
            (7, 2, 3),   // offset switch: clear old layer 7 @ (0,0)
            (7, 2, 3),   // unchanged: no clear
        ]

        for frame in frames {
            if let previous = painted,
               previous.requiresClear(beforePaintingLayer: frame.layer, offsetX: frame.offsetX, offsetY: frame.offsetY) {
                clearedTargets.append(previous)
            }
            painted = target(layer: frame.layer, offsetX: frame.offsetX, offsetY: frame.offsetY)
        }

        #expect(clearedTargets.count == 2, "Only the two changed frames should trigger a clear")
        #expect(clearedTargets[0].layer == 5 && clearedTargets[0].offsetX == 0 && clearedTargets[0].offsetY == 0,
                "Must clear the old layer before painting the new one")
        #expect(clearedTargets[1].layer == 7 && clearedTargets[1].offsetX == 0 && clearedTargets[1].offsetY == 0,
                "Must clear the old offset before painting the new one")
        #expect(painted?.layer == 7 && painted?.offsetX == 2 && painted?.offsetY == 3,
                "The last-painted target must reflect the final frame")
    }
}
