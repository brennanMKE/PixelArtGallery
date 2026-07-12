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

/// Outcome of a ``GalleryCoordinator/reconcileBuiltInSpritesIfNeeded()`` call
/// (#0074, #0075), letting callers (and tests) distinguish freshly-inserted
/// built-ins from existing ones updated in place because the bundled art
/// changed.
struct BuiltInReconcileResult: Equatable {
    /// Number of built-in sprites inserted because they were missing.
    var inserted = 0
    /// Number of existing built-in sprites updated in place because their
    /// stored content hash no longer matched the bundled PNG's hash.
    var updated = 0
}

/// Errors raised by the gallery coordinator's persistence operations.
nonisolated enum GalleryCoordinatorError: LocalizedError, Equatable {
    /// A mutation was requested before a SwiftData `ModelContext` was injected.
    case missingModelContext
    /// The original image bytes for a gallery item could not be found on disk.
    case originalImageMissing(String)
    /// A ``FittedPreview`` referenced a `GalleryItem` id that could no longer
    /// be found (e.g. deleted between preview and save; #0066).
    case galleryItemNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .missingModelContext:
            return "No data context is available to save changes."
        case .originalImageMissing(let path):
            return "The original image could not be found on disk: \(path)"
        case .galleryItemNotFound(let id):
            return "The gallery item for this preview could not be found: \(id)"
        }
    }
}

/// Main coordinator for gallery state management
@Observable
final class GalleryCoordinator {
    /// Ordered manifest of the bundled built-in sprite resource names (#0074),
    /// each backed by a 45×35 PNG at
    /// `Resources/DefaultSprites/<name>.png`. Display name is `name.capitalized`
    /// ("coin" → "Coin"). Order here is the order sprites are reconciled and,
    /// absent any pinning, the order they appear in the Sprites section.
    static let builtInSpriteNames = [
        "barrel", "bomb", "bowser", "cherry", "coin", "frog", "ghost",
        "heart", "invader", "key", "luigi", "mario", "mushroom", "octopus",
        "pacman", "princess", "robot", "ship", "skull", "squid", "star", "ufo",
    ]

    /// Load a bundled built-in sprite's raw PNG bytes by its manifest `name`
    /// (e.g. `"coin"`), or `nil` if the resource is missing/unreadable.
    ///
    /// Only `PixelArtGalleryKit` (not its test target) declares
    /// `Resources/DefaultSprites` in `Package.swift`, so `Bundle.module` only
    /// resolves here — this is the sole call site, which also gives tests a
    /// way to assert bundling works without needing their own `Bundle.module`.
    static func builtInSpriteData(for name: String) -> Data? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "DefaultSprites") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
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

    /// `UserDefaults` store backing last-used-display persistence (#0066).
    /// Injected (default `.standard`) so tests can point it at an isolated
    /// suite rather than polluting the real user defaults. `@ObservationIgnored`
    /// because it is an implementation detail.
    @ObservationIgnored private let defaults: UserDefaults

    /// The `UserDefaults` key storing the last-used FT display's `id`
    /// (as a `String` UUID). See ``rememberLastUsedDisplay(_:)`` /
    /// ``resolveLastUsedDisplay(among:)``.
    static let lastUsedDisplayIDKey = "lastUsedFTDisplayID"

    /// In-memory cache of computed ``FittedPreview`` values, keyed by
    /// ``FittedPreviewCacheKey`` so re-selecting a display for an item is
    /// instant and never re-pixelates. Never persisted; `@ObservationIgnored`
    /// because it is an implementation detail that must not invalidate views
    /// (same as ``modelContext``/``fileStorage``). Memory cost is negligible
    /// (a 45×35 preview is ~6 KB), so no size cap is needed.
    @ObservationIgnored private var previewCache: [FittedPreviewCacheKey: FittedPreview] = [:]

    /// Re-entrancy guard for ``reconcileBuiltInSpritesIfNeeded()`` (#0074): set
    /// synchronously before the method's first `await` and reset in `defer`,
    /// so a second concurrent `onAppear` (macOS window re-open, iOS nav churn)
    /// can't run a second reconcile and double-insert. `@ObservationIgnored`
    /// because it is an implementation detail that must not invalidate views.
    @ObservationIgnored private var isReconcilingBuiltIns = false

    var isImporting = false
    var showImagePicker = false
    var currentError: String?

    /// Transient, non-error message surfaced to the user after an import — e.g.
    /// when an import was skipped because the image was already in the gallery.
    /// The UI shows it and clears it; unlike ``currentError`` it is informational.
    var importMessage: String?

    /// - Parameters:
    ///   - fileStorage: Optional pre-built file store. Production code passes
    ///     nothing and the store is created lazily against the default
    ///     Application Support location; tests inject one pointed at a temporary
    ///     directory so they never write into the user's real gallery storage.
    ///   - defaults: `UserDefaults` store for last-used-display persistence
    ///     (#0066). Production code passes nothing (`.standard`); tests inject
    ///     an isolated suite so `.standard` is never polluted.
    init(fileStorage: FileStorageManager? = nil, defaults: UserDefaults = .standard) {
        self.fileStorage = fileStorage
        self.defaults = defaults
    }

    /// Inject the SwiftData context the coordinator should mutate.
    ///
    /// Idempotent: re-assigning the same context is a no-op so repeated
    /// `onAppear` calls don't churn.
    func configure(modelContext: ModelContext) {
        guard self.modelContext !== modelContext else { return }
        self.modelContext = modelContext
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
    ///   - isBuiltIn: Whether this creates a bundled built-in sprite (#0074).
    ///     When `true`, the content-hash duplicate short-circuit below is
    ///     skipped — a built-in's presence is decided by the reconcile's
    ///     name+flag match, not by hash, so a user who happens to import
    ///     identical bytes can't permanently suppress a sprite. The hash is
    ///     still computed and stored on the item either way.
    /// - Returns: Whether a new item was created or an existing duplicate matched.
    @discardableResult
    func createGalleryItem(name: String, imageData: Data, isBuiltIn: Bool = false) async throws -> ImportResult {
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
            // Built-ins bypass this check entirely (see the `isBuiltIn` doc above).
            if !isBuiltIn {
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
                contentHash: hash,
                isBuiltIn: isBuiltIn
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

    /// Reconcile the bundled built-in sprites (#0074, #0075) so they're always
    /// present and always up to date, re-inserting any missing from the
    /// bundle on every launch, and updating any built-in in place whose
    /// stored content hash no longer matches the bundled PNG's hash.
    ///
    /// Unlike ``seedDefaultDisplayIfNeeded()``, there is **no seed-once flag**
    /// — presence IS the state, which is exactly what makes built-ins
    /// always-restore: deleting one (which the UI disallows, but a damaged
    /// store could) simply means it's missing next time this runs, and it
    /// comes back. The update path exists because built-ins are non-deletable
    /// and matched by name (#0074), so shipping new/bigger art (#0075) could
    /// otherwise never reach an install that already has the old sprites.
    /// This method never deletes items and never touches user items.
    ///
    /// Guarded against re-entrancy (a second concurrent `onAppear`) and
    /// tolerant of per-sprite failures — a missing/unreadable resource or a
    /// failed insert/update is logged and skipped, never blocking launch or
    /// aborting the remaining sprites.
    /// - Returns: The number of built-in items inserted and updated.
    @discardableResult
    func reconcileBuiltInSpritesIfNeeded() async -> BuiltInReconcileResult {
        guard let modelContext else {
            AppLog.gallery.error("reconcileBuiltInSpritesIfNeeded called before a ModelContext was configured")
            return BuiltInReconcileResult()
        }

        guard !isReconcilingBuiltIns else {
            AppLog.gallery.info("Skipped concurrent reconcileBuiltInSpritesIfNeeded call")
            return BuiltInReconcileResult()
        }
        isReconcilingBuiltIns = true
        defer { isReconcilingBuiltIns = false }

        let existingByName: [String: GalleryItem]
        do {
            let existing = try modelContext.fetch(FetchDescriptor<GalleryItem>(
                predicate: #Predicate { $0.isBuiltIn == true }
            ))
            existingByName = Dictionary(
                existing.map { ($0.originalName, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            AppLog.gallery.error("Failed to fetch existing built-in sprites: \(error.localizedDescription, privacy: .public)")
            return BuiltInReconcileResult()
        }

        var result = BuiltInReconcileResult()
        for name in Self.builtInSpriteNames {
            let displayName = name.capitalized

            guard let data = Self.builtInSpriteData(for: name) else {
                AppLog.gallery.error("Missing or unreadable built-in sprite resource: \(name, privacy: .public)")
                continue
            }
            let bundledHash = Self.contentHash(for: data)

            guard let item = existingByName[displayName] else {
                do {
                    try await createGalleryItem(name: displayName, imageData: data, isBuiltIn: true)
                    result.inserted += 1
                } catch {
                    // A background reconcile must not pop the launch-time error
                    // alert — createGalleryItem already set currentError above,
                    // so clear it and just log.
                    currentError = nil
                    AppLog.gallery.error("Failed to insert built-in sprite '\(displayName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                }
                continue
            }

            guard item.contentHash != bundledHash else { continue }

            do {
                try await updateBuiltIn(item, with: data, hash: bundledHash)
                result.updated += 1
            } catch {
                AppLog.gallery.error("Failed to update built-in sprite '\(displayName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }

        if result.inserted > 0 || result.updated > 0 {
            AppLog.gallery.info("Reconciled built-in sprites: \(result.inserted) inserted, \(result.updated) updated")
        }
        return result
    }

    /// Update a built-in ``GalleryItem`` in place when the bundled sprite's
    /// content hash no longer matches the stored one (#0075).
    ///
    /// Saves the new bytes under a fresh filename first (never overwriting in
    /// place), mutates the **same** `GalleryItem` instance so its `id` and
    /// `variants` relationship are preserved, then deletes the old file only
    /// after the model save succeeds. If the model save fails, the
    /// newly-saved file is rolled back so nothing is orphaned; if the old
    /// file's delete fails after a successful save, that's a best-effort
    /// no-op that only orphans a few hundred bytes.
    /// - Parameters:
    ///   - item: The existing built-in item to update.
    ///   - data: The bundled PNG bytes to replace it with.
    ///   - hash: The precomputed content hash of `data`.
    private func updateBuiltIn(_ item: GalleryItem, with data: Data, hash: String) async throws {
        guard let modelContext else {
            AppLog.gallery.error("updateBuiltIn called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        let storage = try fileStorageManager()
        let oldPath = item.originalImagePath
        let newPath = try await storage.save(imageData: data)

        var width = 0
        var height = 0
        if let cgImage = try? loadImage(from: data) {
            width = cgImage.width
            height = cgImage.height
        }

        item.originalImagePath = newPath
        item.originalWidth = width
        item.originalHeight = height
        item.contentHash = hash

        do {
            try modelContext.save()
        } catch {
            try? await storage.delete(filename: newPath)
            throw error
        }

        try? await storage.delete(filename: oldPath)
        AppLog.gallery.info("Updated built-in sprite '\(item.originalName, privacy: .public)' to new bundled content (\(width)×\(height))")
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
    /// - Returns: The newly created and persisted ``Variant``.
    @discardableResult
    func createVariant(
        for item: GalleryItem,
        width: Int,
        height: Int,
        associatedDisplayId: UUID? = nil
    ) async throws -> Variant {
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
            return variant
        } catch {
            currentError = error.localizedDescription
            AppLog.variant.error("Failed to create variant for '\(item.originalName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Compute (or reuse from cache) a transient, aspect-fit preview of an
    /// item for a display, without persisting anything (#0066).
    ///
    /// This never inserts or saves a ``Variant`` — it exists so the popover
    /// flow ([#0067](0067.md))
    /// can show the fitted pixelation the moment a display is selected, and
    /// only an explicit ``saveVariant(from:)`` call turns it into a persisted
    /// record.
    ///
    /// Cache lookup happens first, keyed by ``FittedPreviewCacheKey`` (item id
    /// + display id + display dimensions) — a hit needs no fit math and no
    /// I/O, so it returns instantly. On a miss, the original bytes are loaded
    /// and pixelated via ``PixelationEngine/processFitting(imageData:displayWidth:displayHeight:)``,
    /// which computes the fit from the *decoded, EXIF-upright* image
    /// dimensions rather than the item's stored `originalWidth`/`originalHeight`
    /// (those come from a raw, non-EXIF-transformed decode at import time and
    /// can disagree with the pixels for a rotated photo — see #0066's plan).
    /// This also gives `processFitting` its first production caller,
    /// retiring the dead-code concern raised in #0062.
    /// - Parameters:
    ///   - item: The gallery item to fit and pixelate.
    ///   - display: The Flaschen Taschen display whose geometry the source
    ///     should be fit into.
    /// - Returns: The transient ``FittedPreview``, from cache or freshly computed.
    func fittedPreview(
        for item: GalleryItem,
        display: FlaschenTaschenDisplay
    ) async throws -> FittedPreview {
        let key = FittedPreviewCacheKey(
            itemID: item.id, displayID: display.id,
            displayWidth: display.displayWidth, displayHeight: display.displayHeight
        )
        if let cached = previewCache[key] {
            return cached
        }

        do {
            let storage = try fileStorageManager()
            guard let imageData = try await storage.load(filename: item.originalImagePath) else {
                throw GalleryCoordinatorError.originalImageMissing(item.originalImagePath)
            }

            let pixelationEngine = PixelationEngine()
            let (grid, placement) = try await pixelationEngine.processFitting(
                imageData: imageData,
                displayWidth: display.displayWidth,
                displayHeight: display.displayHeight
            )

            let preview = FittedPreview(
                itemID: item.id,
                displayID: display.id,
                width: placement.width,
                height: placement.height,
                pixelGridData: grid.toRGBA8888(),
                offsetX: placement.offsetX,
                offsetY: placement.offsetY
            )
            previewCache[key] = preview

            AppLog.variant.info(
                "Computed fitted preview for '\(item.originalName, privacy: .public)' at \(placement.width)×\(placement.height) for display \(display.id)"
            )
            return preview
        } catch {
            currentError = error.localizedDescription
            AppLog.variant.error("Failed to compute fitted preview for '\(item.originalName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Persist a transient ``FittedPreview`` as a saved ``Variant`` (#0066).
    ///
    /// Re-locates the `GalleryItem` the preview was computed for (it may have
    /// been evicted from any in-memory reference the caller held), dedups
    /// against the item's existing variants, and otherwise creates and
    /// attaches a new `Variant` built directly from the preview's already-
    /// computed pixel data — no re-pixelation.
    ///
    /// **Dedup key** (moved verbatim from #0063's `createFittedVariant`,
    /// retired in #0068): `associatedDisplayId == preview.displayID && targetWidth == preview.width
    /// && targetHeight == preview.height`. When several matches exist
    /// (shouldn't normally happen), the most recently created one is returned,
    /// for determinism. Re-saving the same preview is intentionally a no-op —
    /// it never touches existing pixel data, since that would silently
    /// discard any edits the user made to the grid. Explicit regeneration
    /// already exists via ``updateVariantDimensions(_:width:height:)``.
    /// - Parameter preview: A ``FittedPreview`` previously returned by
    ///   ``fittedPreview(for:display:)``.
    /// - Returns: The persisted ``Variant``, either newly created or an
    ///   existing match reused as-is.
    @discardableResult
    func saveVariant(from preview: FittedPreview) throws -> Variant {
        guard let modelContext else {
            AppLog.variant.error("saveVariant called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        do {
            let itemID = preview.itemID
            var descriptor = FetchDescriptor<GalleryItem>(
                predicate: #Predicate { $0.id == itemID }
            )
            descriptor.fetchLimit = 1
            guard let item = try modelContext.fetch(descriptor).first else {
                throw GalleryCoordinatorError.galleryItemNotFound(itemID)
            }

            let existingMatches = item.variants.filter {
                $0.associatedDisplayId == preview.displayID
                    && $0.targetWidth == preview.width
                    && $0.targetHeight == preview.height
            }
            if let reuse = existingMatches.max(by: { $0.createdDate < $1.createdDate }) {
                AppLog.variant.info(
                    "Reusing saved variant \(reuse.id) for '\(item.originalName, privacy: .public)' at \(preview.width)×\(preview.height) for display \(preview.displayID)"
                )
                return reuse
            }

            let variant = Variant(
                targetWidth: preview.width,
                targetHeight: preview.height,
                pixelGridData: preview.pixelGridData,
                associatedDisplayId: preview.displayID
            )
            variant.galleryItem = item
            item.variants.append(variant)

            modelContext.insert(variant)
            try modelContext.save()

            AppLog.variant.info(
                "Saved variant for '\(item.originalName, privacy: .public)' at \(preview.width)×\(preview.height) for display \(preview.displayID)"
            )
            return variant
        } catch {
            currentError = error.localizedDescription
            AppLog.variant.error("Failed to save variant from preview: \(error.localizedDescription, privacy: .public)")
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

    /// Persist an edited pixel grid onto an existing variant (#0076).
    ///
    /// Mirrors ``updateVariantDimensions(_:width:height:)`` minus the engine
    /// work — painting a pixel needs no re-pixelation, so this is a
    /// synchronous byte-count-validated write followed by a save. The byte
    /// count is validated defensively (the caller — `PixelGridViewModel`
    /// — always encodes at the variant's own dimensions, but a stale view
    /// model outliving a dimension change elsewhere must not corrupt the
    /// stored grid).
    /// - Parameters:
    ///   - variant: The variant to update.
    ///   - pixelGridData: RGBA8888 bytes, expected to be exactly
    ///     `variant.targetWidth * variant.targetHeight * 4` bytes.
    func updateVariantPixels(_ variant: Variant, pixelGridData: Data) throws {
        guard let modelContext else {
            AppLog.variant.error("updateVariantPixels called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        let expected = variant.targetWidth * variant.targetHeight * 4
        guard pixelGridData.count == expected else {
            AppLog.variant.error("updateVariantPixels received \(pixelGridData.count) bytes, expected \(expected) for variant \(variant.id)")
            throw PixelGridError.invalidDataSize(expected: expected, actual: pixelGridData.count)
        }

        variant.pixelGridData = pixelGridData

        do {
            try modelContext.save()
            AppLog.variant.info("Updated variant \(variant.id) pixel data (\(pixelGridData.count) bytes)")
        } catch {
            currentError = error.localizedDescription
            AppLog.variant.error("Failed to update variant \(variant.id) pixel data: \(error.localizedDescription, privacy: .public)")
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
    ///   - layer: Default paint layer (#0047); clamped to ``FlaschenTaschenDisplay/layerRange``.
    ///   - offsetX: Default horizontal paint offset (#0056); clamped to non-negative.
    ///   - offsetY: Default vertical paint offset (#0056); clamped to non-negative.
    /// - Returns: The persisted display.
    @discardableResult
    func addManualDisplay(
        host: String,
        port: Int,
        displayName: String,
        displayWidth: Int,
        displayHeight: Int,
        layer: Int = FlaschenTaschenDisplay.defaultLayer,
        offsetX: Int = 0,
        offsetY: Int = 0
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
            source: "manual",
            layer: layer,
            offsetX: offsetX,
            offsetY: offsetY
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

    /// Apply a fully validated edit to a persisted Flaschen Taschen display
    /// (#0054).
    ///
    /// Used by the display editor form in both add and edit mode; in edit mode
    /// this is the only way to change a display's host/port/dimensions/name
    /// after creation — previously only the display name could be changed, via
    /// ``renameDisplay(_:to:)``, and everything else required delete + re-add.
    /// - Parameters:
    ///   - display: The display to update.
    ///   - validated: Already-validated field values from ``ManualDisplayInput``.
    ///   - layer: New default paint layer; clamped to ``FlaschenTaschenDisplay/layerRange``.
    func updateDisplay(
        _ display: FlaschenTaschenDisplay,
        with validated: ManualDisplayInput.Validated,
        layer: Int
    ) throws {
        guard let modelContext else {
            AppLog.ftDiscovery.error("updateDisplay called before a ModelContext was configured")
            throw GalleryCoordinatorError.missingModelContext
        }

        display.host = validated.host
        display.port = validated.port
        display.displayName = validated.displayName
        display.displayWidth = validated.width
        display.displayHeight = validated.height
        display.layer = FlaschenTaschenDisplay.clampedLayer(layer)
        display.offsetX = FlaschenTaschenDisplay.clampedOffset(validated.offsetX)
        display.offsetY = FlaschenTaschenDisplay.clampedOffset(validated.offsetY)

        do {
            try modelContext.save()
            AppLog.ftDiscovery.info("Updated display \(display.id): \(validated.displayName, privacy: .public) at \(validated.host, privacy: .public):\(validated.port) (\(validated.width)×\(validated.height))")
        } catch {
            currentError = error.localizedDescription
            AppLog.ftDiscovery.error("Failed to update display \(display.id): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Re-create the built-in default Flaschen Taschen display on demand
    /// (#0054), regardless of whether other displays already exist.
    ///
    /// Unlike ``seedDefaultDisplayIfNeeded()``, which only seeds when the
    /// registry is completely empty, this always inserts a fresh default. It
    /// backs the "Restore Default Display" affordance shown once the seeded
    /// default has been deleted while other displays remain.
    /// - Returns: The newly inserted display, or `nil` if it could not be saved.
    @discardableResult
    func restoreDefaultDisplay() -> FlaschenTaschenDisplay? {
        guard let modelContext else {
            AppLog.ftDiscovery.error("restoreDefaultDisplay called before a ModelContext was configured")
            return nil
        }

        let display = FlaschenTaschenDisplay.makeDefault()
        modelContext.insert(display)
        do {
            try modelContext.save()
            AppLog.ftDiscovery.info("Restored default display: \(display.displayName, privacy: .public)")
            return display
        } catch {
            currentError = error.localizedDescription
            AppLog.ftDiscovery.error("Failed to restore default display: \(error.localizedDescription, privacy: .public)")
            return nil
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

        // Built-in sprites are non-renamable: the UI already omits the
        // Rename action for them (#0074), and `originalName` is the
        // reconcile match key — renaming "Coin" would cause a duplicate
        // re-insert next launch. This is the backstop for any future caller.
        guard !item.isBuiltIn else { return }

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

    /// Toggle a gallery item's pinned state so it leads (or rejoins) the
    /// gallery grid (#0035). Mirrors ``renameGalleryItem(_:to:)``.
    /// - Parameter item: The gallery item whose pin to flip.
    func togglePin(_ item: GalleryItem) {
        guard let modelContext else {
            AppLog.gallery.error("togglePin called before a ModelContext was configured")
            return
        }

        item.isPinned.toggle()
        do {
            try modelContext.save()
            AppLog.gallery.info("Set isPinned=\(item.isPinned) for gallery item \(item.id)")
        } catch {
            currentError = error.localizedDescription
            AppLog.gallery.error("Failed to toggle pin for gallery item \(item.id): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Delete a gallery item, removing it (and its variants via cascade) from
    /// the SwiftData context.
    func deleteGalleryItem(_ item: GalleryItem) {
        guard let modelContext else {
            AppLog.gallery.error("deleteGalleryItem called before a ModelContext was configured")
            return
        }

        // Built-in sprites are non-deletable (#0074): the UI already omits
        // the Delete action for them, and this is the backstop so no present
        // or future call site can remove one.
        guard !item.isBuiltIn else {
            AppLog.gallery.error("Refused to delete built-in gallery item \(item.id)")
            return
        }

        let id = item.id
        modelContext.delete(item)
        do {
            try modelContext.save()
            invalidatePreviews(forItemID: id)
            AppLog.gallery.info("Deleted gallery item: \(id)")
        } catch {
            currentError = error.localizedDescription
            AppLog.gallery.error("Failed to delete gallery item \(id): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Strip any cached ``FittedPreview`` entries for a deleted item (#0066).
    ///
    /// Display-geometry changes need no equivalent hook because display
    /// dimensions are already part of ``FittedPreviewCacheKey`` — stale
    /// entries there simply become unreachable, not wrong.
    private func invalidatePreviews(forItemID itemID: UUID) {
        previewCache = previewCache.filter { $0.key.itemID != itemID }
    }

    /// Delete a variant, removing it from the SwiftData context.
    func deleteVariant(_ variant: Variant) {
        guard let modelContext else {
            AppLog.variant.error("deleteVariant called before a ModelContext was configured")
            return
        }

        let id = variant.id
        modelContext.delete(variant)
        do {
            try modelContext.save()
            AppLog.variant.info("Deleted variant: \(id)")
        } catch {
            currentError = error.localizedDescription
            AppLog.variant.error("Failed to delete variant \(id): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Last-used display (#0066)

    /// Remember `display` as the last one the user selected or sent to, so the
    /// popover flow ([#0067](0067.md)) can default its dropdown to it next time.
    ///
    /// Plain `UserDefaults`, not `@AppStorage` — `@AppStorage` is a SwiftUI
    /// dynamic property that only functions inside `View`s; hosted on this
    /// `@Observable` class it would neither observe nor publish correctly.
    /// Putting the logic here (rather than in the popover view) makes the
    /// default-selection rule unit-testable without SwiftUI and shared across
    /// the iOS/macOS popovers.
    func rememberLastUsedDisplay(_ display: FlaschenTaschenDisplay) {
        defaults.set(display.id.uuidString, forKey: Self.lastUsedDisplayIDKey)
    }

    /// Resolve the last-used display among `candidates`, with a fallback
    /// ladder mirroring ``FlaschenTaschenDisplay/preferredSelection(current:variantWidth:variantHeight:among:)``.
    ///
    /// Reads the stored id and returns the matching candidate; when the
    /// stored value is absent, unparseable, or no longer among `candidates`,
    /// falls back to the candidate with `source == FlaschenTaschenDisplay.defaultSource`,
    /// else `candidates.first`, else `nil`. Candidates are expected to come
    /// from the view's `@Query`, so this method does no fetching itself.
    /// - Parameter candidates: The currently available displays to choose among.
    /// - Returns: The resolved display, or `nil` if `candidates` is empty.
    func resolveLastUsedDisplay(among candidates: [FlaschenTaschenDisplay]) -> FlaschenTaschenDisplay? {
        if let stored = defaults.string(forKey: Self.lastUsedDisplayIDKey),
           let storedID = UUID(uuidString: stored),
           let match = candidates.first(where: { $0.id == storedID }) {
            return match
        }
        return candidates.first(where: { $0.source == FlaschenTaschenDisplay.defaultSource })
            ?? candidates.first
    }
}
