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
}
