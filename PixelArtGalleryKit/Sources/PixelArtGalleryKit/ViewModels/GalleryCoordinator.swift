import CoreGraphics
import Foundation
import ImageIO
import Observation
import SwiftData
import os.log

/// Errors raised by the gallery coordinator's persistence operations.
nonisolated enum GalleryCoordinatorError: Error, Equatable {
    /// A mutation was requested before a SwiftData `ModelContext` was injected.
    case missingModelContext
}

/// Main coordinator for gallery state management
@Observable
final class GalleryCoordinator {
    private static let logger = Logger(subsystem: "com.pixelartgallery.ui", category: "GalleryCoordinator")

    /// The SwiftData context used for inserts and deletes.
    ///
    /// Live reads (`@Query`) belong to the SwiftUI layer; the coordinator only
    /// needs the context to persist mutations. A view injects this via
    /// ``configure(modelContext:)`` once the environment is available. It is
    /// `@ObservationIgnored` because it is an implementation detail and must not
    /// invalidate views when assigned.
    @ObservationIgnored private var modelContext: ModelContext?

    var selectedItem: GalleryItem?
    var selectedVariant: Variant?
    var isImporting = false
    var showNewVariantSheet = false
    var showImagePicker = false
    var showVariantCreation = false
    var currentError: String?

    init() {}

    /// Inject the SwiftData context the coordinator should mutate.
    ///
    /// Idempotent: re-assigning the same context is a no-op so repeated
    /// `onAppear` calls don't churn.
    func configure(modelContext: ModelContext) {
        guard self.modelContext !== modelContext else { return }
        self.modelContext = modelContext
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

        guard let modelContext else {
            Self.logger.error("createGalleryItem called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        modelContext.insert(item)
        try modelContext.save()

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

        guard let modelContext else {
            Self.logger.error("createVariant called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        modelContext.insert(variant)
        try modelContext.save()

        Self.logger.debug("Created variant for \(item.originalName): \(width)×\(height)")
    }

    /// Delete a gallery item, removing it (and its variants via cascade) from
    /// the SwiftData context.
    func deleteGalleryItem(_ item: GalleryItem) {
        guard let modelContext else {
            Self.logger.error("deleteGalleryItem called before a ModelContext was configured")
            return
        }

        let id = item.id
        if selectedItem?.id == id {
            selectedItem = nil
        }

        modelContext.delete(item)
        do {
            try modelContext.save()
            Self.logger.debug("Deleted gallery item: \(id)")
        } catch {
            currentError = error.localizedDescription
            Self.logger.error("Failed to delete gallery item \(id): \(error)")
        }
    }

    /// Delete a variant, removing it from the SwiftData context.
    func deleteVariant(_ variant: Variant) {
        guard let modelContext else {
            Self.logger.error("deleteVariant called before a ModelContext was configured")
            return
        }

        let id = variant.id
        if selectedVariant?.id == id {
            selectedVariant = nil
        }

        modelContext.delete(variant)
        do {
            try modelContext.save()
            Self.logger.debug("Deleted variant: \(id)")
        } catch {
            currentError = error.localizedDescription
            Self.logger.error("Failed to delete variant \(id): \(error)")
        }
    }
}
