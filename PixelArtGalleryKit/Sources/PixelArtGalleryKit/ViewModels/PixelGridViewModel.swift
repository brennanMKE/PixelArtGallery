import Foundation
import SwiftUI
import Observation

/// View model for pixel grid rendering, fit-to-view zoom, panning, and selection.
///
/// Zoom is expressed relative to "size to fit": `zoomLevel == 1.0` fits the whole
/// grid inside the container at the correct aspect ratio; larger values zoom in and
/// enable panning. All layout math is derived from the container size passed in by
/// the view (via `GeometryReader`), so the model stays testable.
@Observable
final class PixelGridViewModel {
    /// 1.0 == size-to-fit; > 1.0 zooms in.
    var zoomLevel: Double = 1.0
    /// User pan offset (only meaningful when zoomed in; clamped to content bounds).
    var panOffset: CGSize = .zero
    var selectedPixel: (x: Int, y: Int)?
    var gridWidth: Int
    var gridHeight: Int
    var pixelData: [PixelColor] = []

    /// True once the working copy (``pixelData``) diverges from the last
    /// saved/loaded state (#0076). Cleared by the view after a successful Save.
    var hasUnsavedEdits = false

    /// Quick-pick swatches for the paint UI (#0076), captured once from the
    /// variant's colors at load time — deliberately NOT recomputed as the
    /// user paints, so the row stays stable during an edit session.
    let swatchColors: [PixelColor]

    let minZoom: Double = 1.0
    let maxZoom: Double = 40.0

    init(gridWidth: Int = 32, gridHeight: Int = 32, pixelData: [PixelColor] = []) {
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
        self.pixelData = pixelData
        self.swatchColors = Self.dominantColors(in: pixelData, max: 10)
    }

    /// Initialize from a Variant's pixel grid data.
    init(variant: Variant) throws {
        self.gridWidth = variant.targetWidth
        self.gridHeight = variant.targetHeight
        let grid = try PixelGrid.fromRGBA8888(variant.pixelGridData, width: variant.targetWidth, height: variant.targetHeight)
        let flattened = grid.colors.flatMap { $0 }
        self.pixelData = flattened
        self.swatchColors = Self.dominantColors(in: flattened, max: 10)
    }

    /// True when the grid is shown fully (no zoom-in), i.e. panning is disabled.
    var isFitToView: Bool { zoomLevel <= minZoom + 0.0001 }

    // MARK: - Zoom

    func zoomIn() { setZoom(zoomLevel * 1.5) }
    func zoomOut() { setZoom(zoomLevel / 1.5) }

    func setZoom(_ newValue: Double) {
        zoomLevel = min(max(newValue, minZoom), maxZoom)
        if isFitToView { panOffset = .zero }
    }

    /// Return to size-to-fit and recenter.
    func reset() {
        zoomLevel = 1.0
        panOffset = .zero
    }

    // MARK: - Selection

    func selectPixel(x: Int, y: Int) { selectedPixel = (x, y) }
    func clearSelection() { selectedPixel = nil }

    /// Get the color at a specific pixel coordinate.
    func pixelColor(x: Int, y: Int) -> PixelColor {
        guard x >= 0, x < gridWidth, y >= 0, y < gridHeight else { return .black }
        let index = y * gridWidth + x
        guard index >= 0, index < pixelData.count else { return .black }
        return pixelData[index]
    }

    // MARK: - Editing (#0076)

    /// Set one pixel in the in-memory working copy. No-op (and no dirty flag)
    /// when out of bounds or when the color is unchanged.
    func setPixel(x: Int, y: Int, color: PixelColor) {
        guard x >= 0, x < gridWidth, y >= 0, y < gridHeight else { return }
        let index = y * gridWidth + x
        guard index >= 0, index < pixelData.count, pixelData[index] != color else { return }
        pixelData[index] = color
        hasUnsavedEdits = true
    }

    /// Encode the working copy back to RGBA8888 bytes for persistence.
    func encodedPixelGridData() -> Data {
        var rows = [[PixelColor]]()
        rows.reserveCapacity(gridHeight)
        for y in 0..<gridHeight {
            let start = y * gridWidth
            let end = min(start + gridWidth, pixelData.count)
            guard start < end else {
                rows.append([])
                continue
            }
            rows.append(Array(pixelData[start..<end]))
        }
        return PixelGrid(width: gridWidth, height: gridHeight, colors: rows).toRGBA8888()
    }

    /// Top-`max` distinct colors by frequency, most-frequent first.
    /// Ties break deterministically by first appearance in `pixels`.
    static func dominantColors(in pixels: [PixelColor], max: Int) -> [PixelColor] {
        guard max > 0, !pixels.isEmpty else { return [] }

        var counts: [PixelColor: Int] = [:]
        var firstIndex: [PixelColor: Int] = [:]
        for (index, color) in pixels.enumerated() {
            counts[color, default: 0] += 1
            if firstIndex[color] == nil {
                firstIndex[color] = index
            }
        }

        let ordered = counts.keys.sorted { lhs, rhs in
            let lhsCount = counts[lhs] ?? 0
            let rhsCount = counts[rhs] ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return (firstIndex[lhs] ?? 0) < (firstIndex[rhs] ?? 0)
        }

        return Array(ordered.prefix(max))
    }

    /// Every exact-RGBA match of `from` becomes `to`; all other pixels untouched.
    static func replacingColor(in pixels: [PixelColor], from: PixelColor, to: PixelColor) -> [PixelColor] {
        pixels.map { $0 == from ? to : $0 }
    }

    /// Apply Replace All to the working copy; sets the dirty flag only when
    /// at least one pixel actually changed (from == to or no matches → no-op).
    func replaceAll(of from: PixelColor, with to: PixelColor) {
        guard from != to else { return }
        let replaced = Self.replacingColor(in: pixelData, from: from, to: to)
        guard replaced != pixelData else { return }
        pixelData = replaced
        hasUnsavedEdits = true
    }

    // MARK: - Layout (all derived from the container size)

    /// Points-per-pixel that fits the whole grid inside `container`, preserving aspect ratio.
    func fitScale(in container: CGSize) -> CGFloat {
        guard gridWidth > 0, gridHeight > 0, container.width > 0, container.height > 0 else { return 0 }
        return min(container.width / CGFloat(gridWidth), container.height / CGFloat(gridHeight))
    }

    /// Side length of one cell at the current zoom.
    func cellSize(in container: CGSize) -> CGFloat {
        fitScale(in: container) * zoomLevel
    }

    /// Total rendered content size at the current zoom.
    func contentSize(in container: CGSize) -> CGSize {
        let cell = cellSize(in: container)
        return CGSize(width: cell * CGFloat(gridWidth), height: cell * CGFloat(gridHeight))
    }

    /// Pan clamped so the content can't be dragged past its own edges. When the
    /// content is smaller than the container on an axis, it stays centered there.
    func clampedPan(in container: CGSize) -> CGSize {
        let content = contentSize(in: container)
        let maxX = max(0, (content.width - container.width) / 2)
        let maxY = max(0, (content.height - container.height) / 2)
        return CGSize(
            width: min(max(panOffset.width, -maxX), maxX),
            height: min(max(panOffset.height, -maxY), maxY)
        )
    }

    /// Top-left origin of the grid in container space: centered, plus clamped pan.
    func origin(in container: CGSize) -> CGPoint {
        let content = contentSize(in: container)
        let pan = clampedPan(in: container)
        return CGPoint(
            x: (container.width - content.width) / 2 + pan.width,
            y: (container.height - content.height) / 2 + pan.height
        )
    }

    /// Map a point in container space to grid coordinates, or nil if outside the grid.
    func gridCoordinate(at point: CGPoint, in container: CGSize) -> (x: Int, y: Int)? {
        let cell = cellSize(in: container)
        guard cell > 0 else { return nil }
        let origin = origin(in: container)
        let x = Int(floor((point.x - origin.x) / cell))
        let y = Int(floor((point.y - origin.y) / cell))
        guard x >= 0, x < gridWidth, y >= 0, y < gridHeight else { return nil }
        return (x, y)
    }

    /// Select the pixel under a container-space point, or clear if outside the grid.
    func selectPixel(at point: CGPoint, in container: CGSize) {
        if let coord = gridCoordinate(at: point, in: container) {
            selectPixel(x: coord.x, y: coord.y)
        } else {
            clearSelection()
        }
    }
}
