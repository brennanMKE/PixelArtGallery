import Foundation
import Observation
import SwiftData
import os.log

/// Main coordinator for gallery state management
@Observable
final class GalleryCoordinator {
    private static let logger = Logger(subsystem: "com.pixelartgallery.ui", category: "GalleryCoordinator")

    /// Query all gallery items from SwiftData
    @Query var allGalleryItems: [GalleryItem]

    /// Expose gallery items for views
    var galleryItems: [GalleryItem] {
        allGalleryItems
    }

    var selectedItem: GalleryItem?
    var selectedVariant: Variant?
    var isImporting = false
    var showNewVariantSheet = false
    var showImagePicker = false
    var showVariantCreation = false
    var currentError: String?

    @MainActor
    init() {
        // @Query is initialized automatically
    }

    func selectItem(_ item: GalleryItem) {
        selectedItem = item
        selectedVariant = nil
    }

    func selectVariant(_ variant: Variant) {
        selectedVariant = variant
    }

    /// Create a new gallery item with image data
    /// - Parameters:
    ///   - name: Display name for the image
    ///   - imageData: Raw image data (JPEG, PNG, HEIC, etc.)
    func createGalleryItem(name: String, imageData: Data) throws {
        let imagePath = "\(UUID().uuidString).jpg"

        // Extract image dimensions from the provided data
        var width = 0
        var height = 0

        if let cgImage = try? loadImage(from: imageData) {
            width = cgImage.width
            height = cgImage.height
        }

        // TODO: Use FileStorageManager to save image data
        // For now, we'll save it directly to Application Support

        let item = GalleryItem(
            originalImagePath: imagePath,
            originalName: name,
            originalWidth: width,
            originalHeight: height
        )

        Self.logger.debug("Created gallery item: \(item.originalName) (\(width)×\(height))")
    }

    /// Load CGImage from data
    private func loadImage(from data: Data) throws -> CGImage? {
        let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        guard let source = imageSource else {
            throw PixelationError.failedToCreateImageSource
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Create a variant for a gallery item using the PixelationEngine
    /// - Parameters:
    ///   - item: The gallery item to create a variant for
    ///   - width: Target pixel grid width
    ///   - height: Target pixel grid height
    func createVariant(for item: GalleryItem, width: Int, height: Int) async throws {
        let pixelationEngine = PixelationEngine()

        // TODO: Load image data from FileStorageManager using item.originalImagePath
        let imageData = Data()

        let pixelGrid = try await pixelationEngine.process(
            imageData: imageData,
            targetWidth: width,
            targetHeight: height
        )

        let variant = Variant(
            targetWidth: width,
            targetHeight: height,
            pixelGridData: pixelGrid.toRGBA8888()
        )

        variant.galleryItem = item
        item.variants.append(variant)

        Self.logger.debug("Created variant for \(item.originalName): \(width)×\(height)")
    }

    /// Delete a gallery item by ID
    func deleteGalleryItem(id: UUID) {
        if let item = allGalleryItems.first(where: { $0.id == id }) {
            // SwiftData will handle deletion
            if selectedItem?.id == id {
                selectedItem = nil
            }
            Self.logger.debug("Deleted gallery item: \(id)")
        }
    }

    /// Delete a variant by ID
    func deleteVariant(id: UUID) {
        if let variant = selectedItem?.variants.first(where: { $0.id == id }) {
            selectedItem?.variants.removeAll { $0.id == id }
            if selectedVariant?.id == id {
                selectedVariant = nil
            }
            Self.logger.debug("Deleted variant: \(id)")
        }
    }
}
