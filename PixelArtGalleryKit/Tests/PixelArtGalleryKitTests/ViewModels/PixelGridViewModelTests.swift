import Testing
import Foundation
import CoreGraphics
@testable import PixelArtGalleryKit

@MainActor
@Suite struct PixelGridViewModelTests {
    /// A square grid in a square container fits exactly: cell = container / gridSize,
    /// centered (origin zero), so points map straight to cells.
    @Test func gridCoordinateFitsAndMapsPoints() {
        let vm = PixelGridViewModel(gridWidth: 32, gridHeight: 32)
        let container = CGSize(width: 320, height: 320) // 10pt per cell at fit.
        #expect(abs(vm.cellSize(in: container) - 10) <= 0.001)
        #expect(vm.gridCoordinate(at: CGPoint(x: 0, y: 0), in: container).map { $0 == (0, 0) } ?? false)
        #expect(vm.gridCoordinate(at: CGPoint(x: 15, y: 25), in: container).map { $0 == (1, 2) } ?? false)
        #expect(vm.gridCoordinate(at: CGPoint(x: 9.9, y: 9.9), in: container).map { $0 == (0, 0) } ?? false)
        #expect(vm.gridCoordinate(at: CGPoint(x: 10, y: 10), in: container).map { $0 == (1, 1) } ?? false)
    }

    /// A non-square grid keeps its aspect ratio: it fits the limiting axis and is
    /// centered on the other, so the whole image is always visible.
    @Test func nonSquareGridFitsWithLetterboxing() {
        let vm = PixelGridViewModel(gridWidth: 45, gridHeight: 35)
        let container = CGSize(width: 450, height: 450)
        // Width is the limiting axis: 450/45 = 10pt per cell; content = 450×350.
        #expect(abs(vm.cellSize(in: container) - 10) <= 0.001)
        let content = vm.contentSize(in: container)
        #expect(abs(content.width - 450) <= 0.001)
        #expect(abs(content.height - 350) <= 0.001)
        // Vertically centered: origin.y = (450 - 350)/2 = 50.
        #expect(abs(vm.origin(in: container).y - 50) <= 0.001)
        #expect(abs(vm.origin(in: container).x - 0) <= 0.001)
    }

    /// Zoom scales the cell size; at fit (1.0) panning is disabled and content centered.
    @Test func zoomClampsAndControlsPan() {
        let vm = PixelGridViewModel(gridWidth: 10, gridHeight: 10)
        #expect(vm.isFitToView)
        vm.zoomOut() // can't go below fit
        #expect(abs(vm.zoomLevel - vm.minZoom) <= 0.001)

        vm.zoomIn()
        #expect(vm.zoomLevel > 1.0)
        #expect(!vm.isFitToView)

        vm.setZoom(1000) // clamps to max
        #expect(abs(vm.zoomLevel - vm.maxZoom) <= 0.001)

        vm.reset()
        #expect(abs(vm.zoomLevel - 1.0) <= 0.001)
        #expect(vm.panOffset == .zero)
    }

    /// Points outside the grid map to nil.
    @Test func gridCoordinateOutOfBoundsReturnsNil() {
        let vm = PixelGridViewModel(gridWidth: 4, gridHeight: 4)
        let container = CGSize(width: 80, height: 80) // 20pt per cell.
        #expect(vm.gridCoordinate(at: CGPoint(x: -1, y: 5), in: container) == nil)
        #expect(vm.gridCoordinate(at: CGPoint(x: 5, y: -1), in: container) == nil)
        #expect(vm.gridCoordinate(at: CGPoint(x: 80, y: 0), in: container) == nil) // start of cell 4
        #expect(vm.gridCoordinate(at: CGPoint(x: 0, y: 80), in: container) == nil)
    }

    /// selectPixel(at:) selects an in-bounds pixel and clears for out-of-bounds.
    @Test func selectPixelAtPoint() {
        let vm = PixelGridViewModel(gridWidth: 8, gridHeight: 8)
        let container = CGSize(width: 80, height: 80) // 10pt per cell.
        vm.selectPixel(at: CGPoint(x: 15, y: 25), in: container) // -> (1, 2)
        #expect(vm.selectedPixel?.x == 1)
        #expect(vm.selectedPixel?.y == 2)

        vm.selectPixel(at: CGPoint(x: -5, y: -5), in: container) // out of bounds -> cleared
        #expect(vm.selectedPixel == nil)
    }

    // MARK: - Paint mutation (#0076)

    /// setPixel changes exactly one index and marks the grid dirty.
    @Test func setPixelChangesExactlyThatPixelAndMarksDirty() {
        let data = (0..<9).map { PixelColor(red: UInt8($0), green: 0, blue: 0) }
        let vm = PixelGridViewModel(gridWidth: 3, gridHeight: 3, pixelData: data)
        #expect(!vm.hasUnsavedEdits)

        let newColor = PixelColor(red: 200, green: 100, blue: 50)
        vm.setPixel(x: 1, y: 1, color: newColor) // index 4

        #expect(vm.hasUnsavedEdits)
        for (index, original) in data.enumerated() {
            if index == 4 {
                #expect(vm.pixelData[index] == newColor)
            } else {
                #expect(vm.pixelData[index] == original, "Only the painted pixel should change")
            }
        }
    }

    /// Out-of-bounds and same-color setPixel calls are no-ops and never dirty the grid.
    @Test func setPixelIsNoOpOutOfBoundsOrUnchanged() {
        let data = (0..<9).map { PixelColor(red: UInt8($0), green: 0, blue: 0) }
        let vm = PixelGridViewModel(gridWidth: 3, gridHeight: 3, pixelData: data)

        vm.setPixel(x: -1, y: 0, color: .white)
        #expect(!vm.hasUnsavedEdits, "Out-of-bounds x should be a no-op")
        vm.setPixel(x: 0, y: 3, color: .white)
        #expect(!vm.hasUnsavedEdits, "Out-of-bounds y should be a no-op")

        let existing = vm.pixelColor(x: 0, y: 0)
        vm.setPixel(x: 0, y: 0, color: existing)
        #expect(!vm.hasUnsavedEdits, "Setting the same color should be a no-op")
        #expect(vm.pixelData == data, "Nothing should have changed")
    }

    /// encodedPixelGridData round-trips through PixelGrid.fromRGBA8888 and
    /// places the painted pixel's bytes at the correct row-major offset.
    @Test func encodedPixelGridDataRoundTrips() throws {
        var data = Array(repeating: PixelColor.black, count: 4) // 2x2
        let vm = PixelGridViewModel(gridWidth: 2, gridHeight: 2, pixelData: data)

        let painted = PixelColor(red: 10, green: 20, blue: 30, alpha: 255)
        vm.setPixel(x: 1, y: 0, color: painted) // index 1

        let encoded = vm.encodedPixelGridData()
        #expect(encoded.count == 2 * 2 * 4)

        let decoded = try PixelGrid.fromRGBA8888(encoded, width: 2, height: 2)
        #expect(decoded.color(x: 1, y: 0) == painted)
        #expect(decoded.color(x: 0, y: 0) == .black)
        #expect(decoded.color(x: 0, y: 1) == .black)
        #expect(decoded.color(x: 1, y: 1) == .black)

        data[1] = painted
        #expect(vm.pixelData == data)
    }

    // MARK: - Dominant colors (#0076)

    /// Known frequencies return the top-N distinct colors, most-frequent
    /// first, capped at `max`, ties broken by first appearance.
    @Test func dominantColorsOrdersByFrequencyThenFirstAppearance() {
        let red = PixelColor(red: 255, green: 0, blue: 0)
        let green = PixelColor(red: 0, green: 255, blue: 0)
        let blue = PixelColor(red: 0, green: 0, blue: 255)
        let yellow = PixelColor(red: 255, green: 255, blue: 0)

        // red: 3, green: 3 (tied, but green appears first), blue: 2, yellow: 1
        let pixels = [green, red, red, green, blue, red, green, blue, yellow]

        let top2 = PixelGridViewModel.dominantColors(in: pixels, max: 2)
        #expect(top2 == [green, red], "Ties break by first appearance; green appears before red")

        let top10 = PixelGridViewModel.dominantColors(in: pixels, max: 10)
        #expect(top10 == [green, red, blue, yellow], "Capped at distinct color count when max exceeds it")

        #expect(PixelGridViewModel.dominantColors(in: [], max: 5).isEmpty)
    }

    // MARK: - Replace All (#0076)

    /// replacingColor swaps every exact match and leaves everything else untouched.
    @Test func replacingColorSwapsExactMatchesOnly() {
        let a = PixelColor(red: 1, green: 1, blue: 1)
        let b = PixelColor(red: 2, green: 2, blue: 2)
        let c = PixelColor(red: 3, green: 3, blue: 3)
        let pixels = [a, b, a, c, a]

        let replaced = PixelGridViewModel.replacingColor(in: pixels, from: a, to: b)
        #expect(replaced == [b, b, b, c, b])

        // A from-color absent from the grid is a no-op.
        let absentColor = PixelColor(red: 9, green: 9, blue: 9)
        let unchanged = PixelGridViewModel.replacingColor(in: pixels, from: absentColor, to: b)
        #expect(unchanged == pixels)
    }

    /// replaceAll(of:with:) mutates the working copy and only dirties when
    /// something actually changed.
    @Test func replaceAllMutatesAndDirtiesOnlyWhenChanged() {
        let a = PixelColor(red: 1, green: 1, blue: 1)
        let b = PixelColor(red: 2, green: 2, blue: 2)
        let absentColor = PixelColor(red: 9, green: 9, blue: 9)
        let pixels = [a, b, a]

        let vm = PixelGridViewModel(gridWidth: 3, gridHeight: 1, pixelData: pixels)
        vm.replaceAll(of: absentColor, with: b)
        #expect(!vm.hasUnsavedEdits, "No matches should not dirty the grid")
        #expect(vm.pixelData == pixels)

        vm.replaceAll(of: a, with: a)
        #expect(!vm.hasUnsavedEdits, "from == to should not dirty the grid")

        vm.replaceAll(of: a, with: b)
        #expect(vm.hasUnsavedEdits, "An actual replacement should dirty the grid")
        #expect(vm.pixelData == [b, b, b])
    }
}
