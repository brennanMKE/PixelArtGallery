import Foundation
import SwiftData

/// Represents a pixelated variant of a gallery item.
/// Each variant stores the downsampled pixel grid data at specific target dimensions,
/// along with metadata about creation, export format, and association with FT displays.
@Model
final class Variant {
    /// Unique identifier for this variant
    @Attribute(.unique) public var id: UUID

    /// Reference back to the parent GalleryItem
    var galleryItem: GalleryItem?

    /// Target width of the pixelated grid (in pixels)
    var targetWidth: Int

    /// Target height of the pixelated grid (in pixels)
    var targetHeight: Int

    /// The pixelated image data as a 2D grid of RGB colors
    /// Format: RGBA8888 flattened array (targetWidth * targetHeight * 4 bytes)
    var pixelGridData: Data

    /// Timestamp when this variant was created
    var createdDate: Date

    /// Last export format used (PNG, HEIC, PPM, JSON)
    var exportFormat: String? = nil

    /// Optional reference to an associated FT display (if created for a specific display)
    var associatedDisplayId: UUID? = nil

    /// Display/export scale factor (1.0 = native, 2.0 = doubled, 0.5 = halved)
    var scaleFactor: Double = 1.0

    /// Initialize a new variant
    /// - Parameters:
    ///   - targetWidth: Target width in pixels
    ///   - targetHeight: Target height in pixels
    ///   - pixelGridData: RGBA8888 flattened pixel data
    ///   - createdDate: Timestamp of creation (defaults to now)
    ///   - exportFormat: Optional last-used export format
    ///   - associatedDisplayId: Optional FT display ID this was created for
    ///   - scaleFactor: Pixel scale factor for display/export
    init(
        targetWidth: Int,
        targetHeight: Int,
        pixelGridData: Data,
        createdDate: Date = Date(),
        exportFormat: String? = nil,
        associatedDisplayId: UUID? = nil,
        scaleFactor: Double = 1.0
    ) {
        self.id = UUID()
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
        self.pixelGridData = pixelGridData
        self.createdDate = createdDate
        self.exportFormat = exportFormat
        self.associatedDisplayId = associatedDisplayId
        self.scaleFactor = scaleFactor
    }
}
