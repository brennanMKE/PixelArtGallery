import CoreGraphics
import Foundation
import ImageIO
import Observation
import SwiftData
import os.log

/// Errors raised by the gallery coordinator's persistence operations.
nonisolated enum GalleryCoordinatorError: LocalizedError, Equatable {
    /// A mutation was requested before a SwiftData `ModelContext` was injected.
    case missingModelContext
    /// The original image bytes for a gallery item could not be found on disk.
    case originalImageMissing(String)

    var errorDescription: String? {
        switch self {
        case .missingModelContext:
            return "No data context is available to save changes."
        case .originalImageMissing(let path):
            return "The original image could not be found on disk: \(path)"
        }
    }
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

    /// File store for original image bytes. Created lazily on first import so a
    /// directory-access failure surfaces through ``currentError`` rather than at
    /// init. `@ObservationIgnored` because it is an implementation detail.
    @ObservationIgnored private var fileStorage: FileStorageManager?

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

    /// Create a new gallery item with image data.
    ///
    /// Writes the original bytes to disk through ``FileStorageManager``, records
    /// the returned filename and the image's real pixel dimensions on a new
    /// ``GalleryItem``, then inserts and saves it. Failures (disk, decode, or
    /// SwiftData) are surfaced through ``currentError`` and rethrown so callers
    /// can react.
    ///
    /// `async` because `FileStorageManager` is an actor.
    /// - Parameters:
    ///   - name: Display name for the image
    ///   - imageData: Raw image data (JPEG, PNG, HEIC, etc.)
    func createGalleryItem(name: String, imageData: Data) async throws {
        guard let modelContext else {
            Self.logger.error("createGalleryItem called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        do {
            // Persist the original bytes and capture the on-disk filename.
            let storage = try fileStorageManager()
            let imagePath = try await storage.save(imageData: imageData)

            // Extract real pixel dimensions from the provided data.
            var width = 0
            var height = 0
            if let cgImage = try? loadImage(from: imageData) {
                width = cgImage.width
                height = cgImage.height
            }

            let item = GalleryItem(
                originalImagePath: imagePath,
                originalName: name,
                originalWidth: width,
                originalHeight: height
            )

            modelContext.insert(item)
            try modelContext.save()

            Self.logger.debug("Created gallery item: \(item.originalName) (\(width)×\(height)) at \(imagePath)")
        } catch {
            currentError = error.localizedDescription
            Self.logger.error("Failed to create gallery item '\(name)': \(error)")
            throw error
        }
    }

    /// Lazily create and cache the file store, reusing it across imports.
    private func fileStorageManager() throws -> FileStorageManager {
        if let fileStorage {
            return fileStorage
        }
        let storage = try FileStorageManager()
        fileStorage = storage
        return storage
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
        guard let modelContext else {
            Self.logger.error("createVariant called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        do {
            // Load the original bytes the item was imported with. Without these
            // the engine would pixelate an empty buffer and every variant would
            // be black, which is exactly the bug this fixes.
            let storage = try fileStorageManager()
            guard let imageData = try await storage.load(filename: item.originalImagePath) else {
                throw GalleryCoordinatorError.originalImageMissing(item.originalImagePath)
            }

            let pixelationEngine = PixelationEngine()
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

            modelContext.insert(variant)
            try modelContext.save()

            Self.logger.debug("Created variant for \(item.originalName): \(width)×\(height)")
        } catch {
            currentError = error.localizedDescription
            Self.logger.error("Failed to create variant for '\(item.originalName)': \(error)")
            throw error
        }
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
