import XCTest
import CoreGraphics
@testable import PixelArtGalleryKit

@MainActor
final class PixelGridViewModelTests: XCTestCase {
    /// A point inside the grid maps to the cell whose origin contains it,
    /// at the default zoom level (1.0).
    func testGridCoordinateAtDefaultZoom() {
        let vm = PixelGridViewModel(gridWidth: 32, gridHeight: 32)
        // pixelSize == 20, zoom == 1.0 -> 20pt per cell.
        XCTAssertTrue(vm.gridCoordinate(at: CGPoint(x: 0, y: 0)).map { $0 == (0, 0) } ?? false)
        XCTAssertTrue(vm.gridCoordinate(at: CGPoint(x: 25, y: 45)).map { $0 == (1, 2) } ?? false)
        XCTAssertTrue(vm.gridCoordinate(at: CGPoint(x: 19.9, y: 19.9)).map { $0 == (0, 0) } ?? false)
        XCTAssertTrue(vm.gridCoordinate(at: CGPoint(x: 20, y: 20)).map { $0 == (1, 1) } ?? false)
    }

    /// Zoom scales the per-cell size, so the same point lands in a different cell.
    func testGridCoordinateRespectsZoom() {
        let vm = PixelGridViewModel(gridWidth: 32, gridHeight: 32)
        vm.zoomLevel = 2.0
        // 40pt per cell now.
        XCTAssertTrue(vm.gridCoordinate(at: CGPoint(x: 50, y: 90)).map { $0 == (1, 2) } ?? false)
        XCTAssertTrue(vm.gridCoordinate(at: CGPoint(x: 39, y: 39)).map { $0 == (0, 0) } ?? false)
    }

    /// Points outside the grid bounds (negative or past the edge) map to nil.
    func testGridCoordinateOutOfBoundsReturnsNil() {
        let vm = PixelGridViewModel(gridWidth: 4, gridHeight: 4)
        XCTAssertNil(vm.gridCoordinate(at: CGPoint(x: -1, y: 5)))
        XCTAssertNil(vm.gridCoordinate(at: CGPoint(x: 5, y: -1)))
        // 4 cells * 20pt = 80pt; x=80 is the start of cell index 4, out of range.
        XCTAssertNil(vm.gridCoordinate(at: CGPoint(x: 80, y: 0)))
        XCTAssertNil(vm.gridCoordinate(at: CGPoint(x: 0, y: 80)))
    }

    /// selectPixel(at:) selects an in-bounds pixel and clears for out-of-bounds.
    func testSelectPixelAtPoint() {
        let vm = PixelGridViewModel(gridWidth: 8, gridHeight: 8)
        vm.selectPixel(at: CGPoint(x: 25, y: 45)) // -> (1, 2)
        XCTAssertEqual(vm.selectedPixel?.x, 1)
        XCTAssertEqual(vm.selectedPixel?.y, 2)

        vm.selectPixel(at: CGPoint(x: -5, y: -5)) // out of bounds -> cleared
        XCTAssertNil(vm.selectedPixel)
    }
}
