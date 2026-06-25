import Foundation
import SwiftUI
import Observation

/// View model for pixel grid rendering and zoom control
@Observable
final class PixelGridViewModel {
    var zoomLevel: Double = 1.0
    var selectedPixel: (x: Int, y: Int)?
    var gridWidth: Int
    var gridHeight: Int
    var pixelData: [PixelColor] = []

    let minZoom: Double = 0.5
    let maxZoom: Double = 10.0
    let pixelSize: Double = 20.0

    init(gridWidth: Int = 32, gridHeight: Int = 32, pixelData: [PixelColor] = []) {
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.pixelData = pixelData
    }

    /// Initialize from a Variant's pixel grid data
    init(variant: Variant) throws {
        self.gridWidth = variant.targetWidth
        self.gridHeight = variant.targetHeight

        // Convert RGBA8888 data to PixelColor array
        let grid = try PixelGrid.fromRGBA8888(variant.pixelGridData, width: variant.targetWidth, height: variant.targetHeight)
        self.pixelData = grid.colors.flatMap { $0 }
    }

    func zoomIn() {
        zoomLevel = min(zoomLevel * 1.2, maxZoom)
    }

    func zoomOut() {
        zoomLevel = max(zoomLevel / 1.2, minZoom)
    }

    func resetZoom() {
        zoomLevel = 1.0
    }

    func selectPixel(x: Int, y: Int) {
        selectedPixel = (x, y)
    }

    /// Map a point in the Canvas's coordinate space to grid coordinates,
    /// accounting for the current zoom level. Returns nil if the point falls
    /// outside the grid bounds.
    func gridCoordinate(at point: CGPoint) -> (x: Int, y: Int)? {
        let cellSize = pixelSize * zoomLevel
        guard cellSize > 0, point.x >= 0, point.y >= 0 else { return nil }
        let x = Int(point.x / cellSize)
        let y = Int(point.y / cellSize)
        guard x >= 0, x < gridWidth, y >= 0, y < gridHeight else { return nil }
        return (x, y)
    }

    /// Select the pixel under a Canvas-space point. Clears the selection when
    /// the point lies outside the grid.
    func selectPixel(at point: CGPoint) {
        if let coord = gridCoordinate(at: point) {
            selectPixel(x: coord.x, y: coord.y)
        } else {
            clearSelection()
        }
    }

    func clearSelection() {
        selectedPixel = nil
    }

    /// Get the color at a specific pixel coordinate
    func pixelColor(x: Int, y: Int) -> PixelColor {
        guard x >= 0, x < gridWidth, y >= 0, y < gridHeight else {
            return .black
        }
        let index = y * gridWidth + x
        guard index >= 0, index < pixelData.count else {
            return .black
        }
        return pixelData[index]
    }

    var displaySize: CGSize {
        CGSize(
            width: CGFloat(gridWidth) * pixelSize * zoomLevel,
            height: CGFloat(gridHeight) * pixelSize * zoomLevel
        )
    }
}
