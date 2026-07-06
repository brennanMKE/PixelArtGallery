import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Observation
import SwiftData

/// Outcome of an import attempt, letting the call site distinguish a freshly
/// created item from one skipped because an identical image was already present.
public enum ImportResult: Equatable {
    /// A new gallery item was created and saved.
    case created
    /// An item with identical original bytes already existed; nothing was
    /// inserted and no duplicate file was written. The display name is the name
    /// of the existing item so the UI can tell the user what it matched.
    case duplicate(existingName: String)
}

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

    /// Transient, non-error message surfaced to the user after an import — e.g.
    /// when an import was skipped because the image was already in the gallery.
    /// The UI shows it and clears it; unlike ``currentError`` it is informational.
    var importMessage: String?

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

    /// Create a new gallery item with image data, skipping exact duplicates.
    ///
    /// Hashes the incoming bytes (SHA-256) and, if a gallery item with the same
    /// `contentHash` already exists, skips the import entirely — no file is
    /// written and no item is inserted — returning ``ImportResult/duplicate(existingName:)``
    /// and setting ``importMessage`` so the UI can tell the user. Otherwise it
    /// writes the original bytes to disk through ``FileStorageManager``, records
    /// the returned filename, the image's real pixel dimensions, and the hash on
    /// a new ``GalleryItem``, then inserts and saves it, returning
    /// ``ImportResult/created``. Failures (disk, decode, or SwiftData) are
    /// surfaced through ``currentError`` and rethrown so callers can react.
    ///
    /// `async` because `FileStorageManager` is an actor.
    /// - Parameters:
    ///   - name: Display name for the image
    ///   - imageData: Raw image data (JPEG, PNG, HEIC, etc.)
    /// - Returns: Whether a new item was created or an existing duplicate matched.
    @discardableResult
    func createGalleryItem(name: String, imageData: Data) async throws -> ImportResult {
        guard let modelContext else {
            AppLog.gallery.error("createGalleryItem called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        AppLog.gallery.info("Importing gallery item '\(name, privacy: .public)' (\(imageData.count) bytes)")

        do {
            // Compute the content hash first so duplicate detection happens
            // before any file is written.
            let hash = Self.contentHash(for: imageData)

            // Skip the import if an identical image is already in the gallery.
            var descriptor = FetchDescriptor<GalleryItem>(
                predicate: #Predicate { $0.contentHash == hash }
            )
            descriptor.fetchLimit = 1
            if let existing = try modelContext.fetch(descriptor).first {
                let message = "“\(existing.originalName)” is already in your gallery — skipped the duplicate."
                importMessage = message
                AppLog.gallery.info("Skipped duplicate import; matches existing item: \(existing.originalName, privacy: .public)")
                return .duplicate(existingName: existing.originalName)
            }

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
                originalHeight: height,
                contentHash: hash
            )

            modelContext.insert(item)
            try modelContext.save()

            AppLog.gallery.info("Created gallery item: \(item.originalName, privacy: .public) (\(width)×\(height)) at \(imagePath, privacy: .public)")
            return .created
        } catch {
            currentError = error.localizedDescription
            AppLog.gallery.error("Failed to create gallery item '\(name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Compute the lowercase hex SHA-256 digest of raw image bytes.
    ///
    /// Exact and cheap to compare, so duplicate detection on import is a simple
    /// string equality check against the stored ``GalleryItem/contentHash``.
    static func contentHash(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

    /// Load the bytes of a stored original image by its `originalImagePath`.
    ///
    /// Returns `nil` (rather than throwing) if the file is missing or unreadable,
    /// so image views can fall back to a placeholder without error handling.
    func loadOriginalImageData(path: String) async -> Data? {
        do {
            let storage = try fileStorageManager()
            return try await storage.load(filename: path)
        } catch {
            AppLog.gallery.error("Failed to load original image '\(path, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            return nil
        }
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
    ///   - associatedDisplayId: Optional FT display this variant was sized for.
    ///     When the user picks a discovered display to prefill the dimensions
    ///     (PRD Option A), its `id` is recorded so the variant remembers which
    ///     display it was made for.
    func createVariant(
        for item: GalleryItem,
        width: Int,
        height: Int,
        associatedDisplayId: UUID? = nil
    ) async throws {
        guard let modelContext else {
            AppLog.variant.error("createVariant called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        AppLog.variant.info("Creating variant for '\(item.originalName, privacy: .public)' at \(width)×\(height)")

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
                pixelGridData: pixelGrid.toRGBA8888(),
                associatedDisplayId: associatedDisplayId
            )

            variant.galleryItem = item
            item.variants.append(variant)

            modelContext.insert(variant)
            try modelContext.save()

            AppLog.variant.info("Created variant for \(item.originalName, privacy: .public): \(width)×\(height)")
        } catch {
            currentError = error.localizedDescription
            AppLog.variant.error("Failed to create variant for '\(item.originalName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Duplicate an existing variant within the same gallery item.
    ///
    /// Copies the source variant's dimensions, pixel data, scale factor, and
    /// associated display id onto a brand-new ``Variant`` attached to the same
    /// parent item, then inserts and saves. The existing `pixelGridData` is
    /// copied verbatim — a pure duplicate doesn't need to re-run the engine —
    /// so the copy is byte-identical to the source. `exportFormat` is left `nil`
    /// because the copy hasn't been exported yet.
    /// - Parameter variant: The variant to duplicate.
    /// - Returns: The newly created copy.
    @discardableResult
    func duplicateVariant(_ variant: Variant) throws -> Variant {
        guard let modelContext else {
            AppLog.variant.error("duplicateVariant called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        let copy = Variant(
            targetWidth: variant.targetWidth,
            targetHeight: variant.targetHeight,
            pixelGridData: variant.pixelGridData,
            associatedDisplayId: variant.associatedDisplayId,
            scaleFactor: variant.scaleFactor
        )

        if let item = variant.galleryItem {
            copy.galleryItem = item
            item.variants.append(copy)
        }

        do {
            modelContext.insert(copy)
            try modelContext.save()
            AppLog.variant.info("Duplicated variant \(variant.id) -> \(copy.id)")
            return copy
        } catch {
            currentError = error.localizedDescription
            AppLog.variant.error("Failed to duplicate variant \(variant.id): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Edit a variant's target dimensions, regenerating its pixel data.
    ///
    /// Reloads the parent gallery item's original image bytes through
    /// ``FileStorageManager`` and re-runs the ``PixelationEngine`` at the new
    /// dimensions, replacing `pixelGridData` and updating `targetWidth`/
    /// `targetHeight`, then saves. This mirrors ``createVariant(for:width:height:associatedDisplayId:)``
    /// because changing dimensions means the existing downsample is no longer
    /// valid and must be recomputed from the source.
    /// - Parameters:
    ///   - variant: The variant whose dimensions should change.
    ///   - width: New target pixel grid width.
    ///   - height: New target pixel grid height.
    func updateVariantDimensions(_ variant: Variant, width: Int, height: Int) async throws {
        guard let modelContext else {
            AppLog.variant.error("updateVariantDimensions called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        guard let item = variant.galleryItem else {
            AppLog.variant.error("updateVariantDimensions called on a variant with no parent item")
            throw GalleryCoordinatorError.originalImageMissing("<no parent item>")
        }

        do {
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

            variant.targetWidth = width
            variant.targetHeight = height
            variant.pixelGridData = pixelGrid.toRGBA8888()

            try modelContext.save()
            AppLog.variant.info("Updated variant \(variant.id) dimensions to \(width)×\(height)")
        } catch {
            currentError = error.localizedDescription
            AppLog.variant.error("Failed to update variant \(variant.id) dimensions: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Persist a manually entered Flaschen Taschen display.
    ///
    /// Used when mDNS discovery fails or is unavailable and the user types in a
    /// host/port directly. Creates a ``FlaschenTaschenDisplay`` with
    /// `source = "manual"`, inserts it, and saves — following the same
    /// insert+save pattern as the other mutations here. Validation of the raw
    /// user input happens in the UI layer via ``ManualDisplayInput`` before this
    /// is called.
    /// - Parameters:
    ///   - host: Hostname or IP address (already trimmed/validated)
    ///   - port: Service port (1–65535)
    ///   - displayName: User-friendly name
    ///   - displayWidth: Native pixel width
    ///   - displayHeight: Native pixel height
    /// - Returns: The persisted display.
    @discardableResult
    func addManualDisplay(
        host: String,
        port: Int,
        displayName: String,
        displayWidth: Int,
        displayHeight: Int
    ) throws -> FlaschenTaschenDisplay {
        guard let modelContext else {
            AppLog.ftDiscovery.error("addManualDisplay called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        let display = FlaschenTaschenDisplay(
            host: host,
            port: port,
            displayName: displayName,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            source: "manual"
        )

        do {
            modelContext.insert(display)
            try modelContext.save()
            AppLog.ftDiscovery.info("Added manual display: \(displayName, privacy: .public) at \(host, privacy: .public):\(port) (\(displayWidth)×\(displayHeight))")
            return display
        } catch {
            currentError = error.localizedDescription
            AppLog.ftDiscovery.error("Failed to add manual display '\(displayName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Seed the built-in default Flaschen Taschen display when the registry is
    /// completely empty (#0021).
    ///
    /// Rule: seed only when there are **no** ``FlaschenTaschenDisplay`` records
    /// at all at the time of the call. This keeps the call idempotent (once the
    /// default exists the registry is non-empty, so repeated `onAppear` calls
    /// are no-ops) and respects a user who deleted the default while keeping
    /// other displays — the default is only ever re-created when the registry
    /// has gone back to empty. Failures are logged but not surfaced through
    /// ``currentError``; a missing default is a cosmetic gap, not an error the
    /// user needs to act on.
    /// - Returns: `true` if the default display was inserted.
    @discardableResult
    func seedDefaultDisplayIfNeeded() -> Bool {
        guard let modelContext else {
            AppLog.ftDiscovery.error("seedDefaultDisplayIfNeeded called before a ModelContext was configured")
            return false
        }

        do {
            let count = try modelContext.fetchCount(FetchDescriptor<FlaschenTaschenDisplay>())
            guard count == 0 else { return false }

            let display = FlaschenTaschenDisplay.makeDefault()
            modelContext.insert(display)
            try modelContext.save()
            AppLog.ftDiscovery.info("Seeded default display: \(display.displayName, privacy: .public) at \(display.host, privacy: .public):\(display.port) (\(display.displayWidth)×\(display.displayHeight))")
            return true
        } catch {
            AppLog.ftDiscovery.error("Failed to seed default display: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Rename a persisted Flaschen Taschen display.
    ///
    /// Trims the supplied name; an all-whitespace name is rejected (no-op) so a
    /// display always keeps a usable label.
    /// - Parameters:
    ///   - display: The display to rename.
    ///   - newName: The new user-friendly name.
    func renameDisplay(_ display: FlaschenTaschenDisplay, to newName: String) {
        guard let modelContext else {
            AppLog.ftDiscovery.error("renameDisplay called before a ModelContext was configured")
            return
        }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        display.displayName = trimmed
        do {
            try modelContext.save()
            AppLog.ftDiscovery.info("Renamed display \(display.id) to \(trimmed, privacy: .public)")
        } catch {
            currentError = error.localizedDescription
            AppLog.ftDiscovery.error("Failed to rename display \(display.id): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Delete a persisted Flaschen Taschen display from the registry.
    func deleteDisplay(_ display: FlaschenTaschenDisplay) {
        guard let modelContext else {
            AppLog.ftDiscovery.error("deleteDisplay called before a ModelContext was configured")
            return
        }

        let id = display.id
        modelContext.delete(display)
        do {
            try modelContext.save()
            AppLog.ftDiscovery.info("Deleted display: \(id)")
        } catch {
            currentError = error.localizedDescription
            AppLog.ftDiscovery.error("Failed to delete display \(id): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Run an mDNS scan and merge any discovered displays into the registry.
    ///
    /// Streams results from ``FTDiscoveryService`` for `duration`, collects them,
    /// then merges into SwiftData via ``mergeDiscoveredDisplays(_:)`` (de-duping by
    /// host+port). Returns the number of displays inserted or updated. Discovery
    /// failures degrade to "no displays found" — the stream simply finishes — so
    /// this never throws on a discovery error; only a SwiftData save failure
    /// surfaces through ``currentError``.
    /// - Parameter duration: How long to browse before stopping the scan.
    /// - Returns: A tuple of (inserted, updated) counts.
    @discardableResult
    func scanForDisplays(
        duration: Duration = .seconds(5)
    ) async -> (inserted: Int, updated: Int) {
        AppLog.ftDiscovery.info("Starting display scan for \(duration.components.seconds)s")
        let service = FTDiscoveryService()
        var discovered: [DiscoveredFTDisplay] = []
        for await display in await service.scan(duration: duration) {
            discovered.append(display)
        }
        AppLog.ftDiscovery.info("Display scan finished: \(discovered.count) discovered")
        return mergeDiscoveredDisplays(discovered)
    }

    /// Merge discovered displays into the SwiftData registry, de-duplicating by
    /// host+port.
    ///
    /// Fetches the current ``FlaschenTaschenDisplay`` records, applies the pure
    /// ``DisplayMergePlan`` logic, then performs the inserts/updates and saves.
    /// Existing records that match a discovered host+port are updated in place
    /// (resolution refreshed, source set to `mdns`); unmatched discoveries are
    /// inserted as new `mdns` records. Returns the (inserted, updated) counts.
    @discardableResult
    func mergeDiscoveredDisplays(
        _ discovered: [DiscoveredFTDisplay]
    ) -> (inserted: Int, updated: Int) {
        guard let modelContext else {
            AppLog.ftDiscovery.error("mergeDiscoveredDisplays called before a ModelContext was configured")
            return (0, 0)
        }

        let existing: [FlaschenTaschenDisplay]
        do {
            existing = try modelContext.fetch(FetchDescriptor<FlaschenTaschenDisplay>())
        } catch {
            currentError = error.localizedDescription
            AppLog.ftDiscovery.error("Failed to fetch displays for merge: \(error.localizedDescription, privacy: .public)")
            return (0, 0)
        }

        let plan = DisplayMergePlan.build(existing: existing, discovered: discovered)

        // Update matched existing records in place.
        for update in plan.updates {
            let model = update.target
            model.displayName = update.discovered.serviceName.isEmpty
                ? model.displayName
                : update.discovered.serviceName
            if let width = update.discovered.displayWidth { model.displayWidth = width }
            if let height = update.discovered.displayHeight { model.displayHeight = height }
            model.source = "mdns"
        }

        // Insert brand-new discoveries.
        for value in plan.insertions {
            modelContext.insert(value.makeDisplayModel())
        }

        do {
            try modelContext.save()
            AppLog.ftDiscovery.info("Merged discovered displays: \(plan.insertions.count) inserted, \(plan.updates.count) updated")
        } catch {
            currentError = error.localizedDescription
            AppLog.ftDiscovery.error("Failed to save merged displays: \(error.localizedDescription, privacy: .public)")
            return (0, 0)
        }

        return (plan.insertions.count, plan.updates.count)
    }

    /// Rename a gallery item.
    ///
    /// Trims the supplied name; an all-whitespace (or empty) name is rejected
    /// (no-op) so an item always keeps a usable label. Mirrors
    /// ``renameDisplay(_:to:)``.
    /// - Parameters:
    ///   - item: The gallery item to rename.
    ///   - newName: The new user-friendly name.
    func renameGalleryItem(_ item: GalleryItem, to newName: String) {
        guard let modelContext else {
            AppLog.gallery.error("renameGalleryItem called before a ModelContext was configured")
            return
        }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        item.originalName = trimmed
        do {
            try modelContext.save()
            AppLog.gallery.info("Renamed gallery item \(item.id) to \(trimmed, privacy: .public)")
        } catch {
            currentError = error.localizedDescription
            AppLog.gallery.error("Failed to rename gallery item \(item.id): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Delete a gallery item, removing it (and its variants via cascade) from
    /// the SwiftData context.
    func deleteGalleryItem(_ item: GalleryItem) {
        guard let modelContext else {
            AppLog.gallery.error("deleteGalleryItem called before a ModelContext was configured")
            return
        }

        let id = item.id
        if selectedItem?.id == id {
            selectedItem = nil
        }

        modelContext.delete(item)
        do {
            try modelContext.save()
            AppLog.gallery.info("Deleted gallery item: \(id)")
        } catch {
            currentError = error.localizedDescription
            AppLog.gallery.error("Failed to delete gallery item \(id): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Delete a variant, removing it from the SwiftData context.
    func deleteVariant(_ variant: Variant) {
        guard let modelContext else {
            AppLog.variant.error("deleteVariant called before a ModelContext was configured")
            return
        }

        let id = variant.id
        if selectedVariant?.id == id {
            selectedVariant = nil
        }

        modelContext.delete(variant)
        do {
            try modelContext.save()
            AppLog.variant.info("Deleted variant: \(id)")
        } catch {
            currentError = error.localizedDescription
            AppLog.variant.error("Failed to delete variant \(id): \(error.localizedDescription, privacy: .public)")
        }
    }
}
