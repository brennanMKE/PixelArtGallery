import XCTest
import CoreGraphics
@testable import PixelArtGalleryKit

@MainActor
final class PixelGridViewModelTests: XCTestCase {
    /// A square grid in a square container fits exactly: cell = container / gridSize,
    /// centered (origin zero), so points map straight to cells.
    func testGridCoordinateFitsAndMapsPoints() {
        let vm = PixelGridViewModel(gridWidth: 32, gridHeight: 32)
        let container = CGSize(width: 320, height: 320) // 10pt per cell at fit.
        XCTAssertEqual(vm.cellSize(in: container), 10, accuracy: 0.001)
        XCTAssertTrue(vm.gridCoordinate(at: CGPoint(x: 0, y: 0), in: container).map { $0 == (0, 0) } ?? false)
        XCTAssertTrue(vm.gridCoordinate(at: CGPoint(x: 15, y: 25), in: container).map { $0 == (1, 2) } ?? false)
        XCTAssertTrue(vm.gridCoordinate(at: CGPoint(x: 9.9, y: 9.9), in: container).map { $0 == (0, 0) } ?? false)
        XCTAssertTrue(vm.gridCoordinate(at: CGPoint(x: 10, y: 10), in: container).map { $0 == (1, 1) } ?? false)
    }

    /// A non-square grid keeps its aspect ratio: it fits the limiting axis and is
    /// centered on the other, so the whole image is always visible.
    func testNonSquareGridFitsWithLetterboxing() {
        let vm = PixelGridViewModel(gridWidth: 45, gridHeight: 35)
        let container = CGSize(width: 450, height: 450)
        // Width is the limiting axis: 450/45 = 10pt per cell; content = 450×350.
        XCTAssertEqual(vm.cellSize(in: container), 10, accuracy: 0.001)
        let content = vm.contentSize(in: container)
        XCTAssertEqual(content.width, 450, accuracy: 0.001)
        XCTAssertEqual(content.height, 350, accuracy: 0.001)
        // Vertically centered: origin.y = (450 - 350)/2 = 50.
        XCTAssertEqual(vm.origin(in: container).y, 50, accuracy: 0.001)
        XCTAssertEqual(vm.origin(in: container).x, 0, accuracy: 0.001)
    }

    /// Zoom scales the cell size; at fit (1.0) panning is disabled and content centered.
    func testZoomClampsAndControlsPan() {
        let vm = PixelGridViewModel(gridWidth: 10, gridHeight: 10)
        XCTAssertTrue(vm.isFitToView)
        vm.zoomOut() // can't go below fit
        XCTAssertEqual(vm.zoomLevel, vm.minZoom, accuracy: 0.001)

        vm.zoomIn()
        XCTAssertGreaterThan(vm.zoomLevel, 1.0)
        XCTAssertFalse(vm.isFitToView)

        vm.setZoom(1000) // clamps to max
        XCTAssertEqual(vm.zoomLevel, vm.maxZoom, accuracy: 0.001)

        vm.reset()
        XCTAssertEqual(vm.zoomLevel, 1.0, accuracy: 0.001)
        XCTAssertEqual(vm.panOffset, .zero)
    }

    /// Points outside the grid map to nil.
    func testGridCoordinateOutOfBoundsReturnsNil() {
        let vm = PixelGridViewModel(gridWidth: 4, gridHeight: 4)
        let container = CGSize(width: 80, height: 80) // 20pt per cell.
        XCTAssertNil(vm.gridCoordinate(at: CGPoint(x: -1, y: 5), in: container))
        XCTAssertNil(vm.gridCoordinate(at: CGPoint(x: 5, y: -1), in: container))
        XCTAssertNil(vm.gridCoordinate(at: CGPoint(x: 80, y: 0), in: container)) // start of cell 4
        XCTAssertNil(vm.gridCoordinate(at: CGPoint(x: 0, y: 80), in: container))
    }

    /// selectPixel(at:) selects an in-bounds pixel and clears for out-of-bounds.
    func testSelectPixelAtPoint() {
        let vm = PixelGridViewModel(gridWidth: 8, gridHeight: 8)
        let container = CGSize(width: 80, height: 80) // 10pt per cell.
        vm.selectPixel(at: CGPoint(x: 15, y: 25), in: container) // -> (1, 2)
        XCTAssertEqual(vm.selectedPixel?.x, 1)
        XCTAssertEqual(vm.selectedPixel?.y, 2)

        vm.selectPixel(at: CGPoint(x: -5, y: -5), in: container) // out of bounds -> cleared
        XCTAssertNil(vm.selectedPixel)
    }
}
