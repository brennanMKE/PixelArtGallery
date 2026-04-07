import Foundation
import SwiftData

/// Represents an imported image in the gallery with its metadata and variants.
/// Each GalleryItem stores the original image reference and maintains a collection of pixelated variants
/// created from that original.
@Model
final class GalleryItem {
    /// Unique identifier for this gallery item
    @Attribute(.unique) public var id: UUID

    /// The original image data as stored in persistent storage
    /// Strategy: Store as file reference in Application Support directory to minimize database size
    var originalImagePath: String

    /// Friendly name of the imported image (typically the filename)
    var originalName: String

    /// Original image dimensions for reference
    var originalWidth: Int
    var originalHeight: Int

    /// Timestamp when this image was imported into the gallery
    var importedDate: Date

    /// Array of variants created from this original image
    /// Relationship: Cascade delete—removing a GalleryItem removes all its variants
    @Relationship(deleteRule: .cascade, inverse: \Variant.galleryItem) var variants: [Variant] = []

    /// Initialize a new gallery item
    /// - Parameters:
    ///   - originalImagePath: File path to stored image
    ///   - originalName: User-friendly name of the image
    ///   - originalWidth: Width of original image
    ///   - originalHeight: Height of original image
    ///   - importedDate: Timestamp of import (defaults to now)
    init(
        originalImagePath: String,
        originalName: String,
        originalWidth: Int,
        originalHeight: Int,
        importedDate: Date = Date()
    ) {
        self.id = UUID()
        self.originalImagePath = originalImagePath
        self.originalName = originalName
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.importedDate = importedDate
        self.variants = []
    }
}
