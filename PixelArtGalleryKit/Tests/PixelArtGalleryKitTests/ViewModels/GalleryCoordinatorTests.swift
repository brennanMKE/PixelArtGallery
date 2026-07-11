import Testing
import Foundation
import CoreGraphics
import ImageIO
import SwiftData
import UniformTypeIdentifiers
@testable import PixelArtGalleryKit

/// Device-free tests for ``GalleryCoordinator`` mutations exercised over an
/// in-memory `ModelContext`, matching the setup in `DisplayMergeTests`.
///
/// Focus here is variant creation tagging the resulting ``Variant`` with the
/// associated FT display id when the user picks a display to match (#0013).
@MainActor
@Suite final class GalleryCoordinatorTests {

    /// Unique per-test temporary directory that backs the coordinator's
    /// ``FileStorageManager``, so imports never write into the user's real
    /// `Application Support/PixelArtGallery/Images` directory (#0034).
    private let tempDirectory: URL

    init() {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GalleryCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// Build a coordinator whose file storage is isolated to ``tempDirectory``.
    private func makeCoordinator() throws -> GalleryCoordinator {
        GalleryCoordinator(fileStorage: try FileStorageManager(imageDirectory: tempDirectory))
    }

    /// A fresh in-memory SwiftData context covering the gallery + display models.
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: GalleryItem.self, Variant.self, FlaschenTaschenDisplay.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// Build a coordinator with a real gallery item whose original image bytes
    /// are written to disk via the coordinator's own import path, so
    /// `createVariant` can load and pixelate them.
    private func makeItem(in context: ModelContext, coordinator: GalleryCoordinator) async throws -> GalleryItem {
        let pngData = try Self.makePNGData(width: 16, height: 16)
        try await coordinator.createGalleryItem(name: "Test", imageData: pngData)
        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        return try #require(items.first)
    }

    @Test func createVariantRecordsAssociatedDisplayId() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let display = FlaschenTaschenDisplay(
            host: "10.0.0.1", port: 1337, displayName: "Office",
            displayWidth: 64, displayHeight: 32
        )
        context.insert(display)
        try context.save()

        let item = try await makeItem(in: context, coordinator: coordinator)

        try await coordinator.createVariant(
            for: item,
            width: 64,
            height: 32,
            associatedDisplayId: display.id
        )

        let variants = try context.fetch(FetchDescriptor<Variant>())
        #expect(variants.count == 1)
        let variant = try #require(variants.first)
        #expect(variant.associatedDisplayId == display.id,
                "Variant should remember the display it was sized for")
        #expect(variant.targetWidth == 64)
        #expect(variant.targetHeight == 32)
    }

    @Test func createVariantWithoutDisplayLeavesAssociationNil() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)

        try await coordinator.createVariant(for: item, width: 32, height: 32)

        let variants = try context.fetch(FetchDescriptor<Variant>())
        let variant = try #require(variants.first)
        #expect(variant.associatedDisplayId == nil,
                "Custom dimensions should record no display association")
    }

    // MARK: - Deletion (#0029)

    @Test func deleteGalleryItemRemovesItemAndCascadesVariants() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)
        try await coordinator.createVariant(for: item, width: 8, height: 8)
        let variantCount = try context.fetch(FetchDescriptor<Variant>()).count
        #expect(variantCount == 1)

        coordinator.deleteGalleryItem(item)

        let remainingItems = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(remainingItems.isEmpty,
                "Deleting a gallery item should remove it from the store")
        let remainingVariants = try context.fetch(FetchDescriptor<Variant>())
        #expect(remainingVariants.isEmpty,
                "Deleting a gallery item should cascade-delete its variants")
    }

    // MARK: - Duplicate prevention (#0014)

    @Test func importingSameBytesTwiceYieldsOneItem() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let pngData = try Self.makePNGData(width: 16, height: 16)

        let first = try await coordinator.createGalleryItem(name: "Original", imageData: pngData)
        #expect(first == .created, "First import of fresh bytes should create an item")

        let second = try await coordinator.createGalleryItem(name: "Copy", imageData: pngData)
        #expect(second == .duplicate(existingName: "Original"),
                "Re-importing identical bytes should be reported as a duplicate")

        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == 1, "Duplicate import must not create a second gallery item")
        #expect(coordinator.importMessage != nil,
                "A user-facing message should be set when a duplicate is skipped")
    }

    @Test func importingDifferentBytesYieldsTwoItems() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let pngA = try Self.makePNGData(width: 16, height: 16)
        let pngB = try Self.makePNGData(width: 24, height: 24)
        #expect(pngA != pngB, "Test fixtures must differ for this to be meaningful")

        let first = try await coordinator.createGalleryItem(name: "A", imageData: pngA)
        let second = try await coordinator.createGalleryItem(name: "B", imageData: pngB)
        #expect(first == .created)
        #expect(second == .created)

        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == 2, "Distinct images should each create a gallery item")
    }

    // MARK: - Variant management (#0015)

    @Test func duplicateVariantCopiesDataAndIncreasesCount() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)
        try await coordinator.createVariant(for: item, width: 8, height: 8)

        let original = try #require(try context.fetch(FetchDescriptor<Variant>()).first)
        let copy = try coordinator.duplicateVariant(original)

        let variants = try context.fetch(FetchDescriptor<Variant>())
        #expect(variants.count == 2, "Duplicating should add a second variant")
        #expect(copy.id != original.id, "The copy must be a distinct record")
        #expect(copy.targetWidth == original.targetWidth)
        #expect(copy.targetHeight == original.targetHeight)
        #expect(copy.pixelGridData == original.pixelGridData,
                "Pixel data should be copied verbatim")
        #expect(copy.galleryItem?.id == item.id,
                "The copy should belong to the same parent item")
    }

    @Test func updateVariantDimensionsRegeneratesPixelData() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)
        try await coordinator.createVariant(for: item, width: 8, height: 8)

        let variant = try #require(try context.fetch(FetchDescriptor<Variant>()).first)
        #expect(variant.pixelGridData.count == 8 * 8 * 4)

        try await coordinator.updateVariantDimensions(variant, width: 12, height: 6)

        #expect(variant.targetWidth == 12)
        #expect(variant.targetHeight == 6)
        #expect(variant.pixelGridData.count == 12 * 6 * 4,
                "Regenerated pixel data length must match new width*height*4")

        // No extra variant was created — the same record was edited in place.
        let variants = try context.fetch(FetchDescriptor<Variant>())
        #expect(variants.count == 1)
    }

    // MARK: - Naming at import / rename (#0018)

    @Test func renameGalleryItemUpdatesAndPersistsName() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)

        coordinator.renameGalleryItem(item, to: "  Sunset Over Water  ")

        #expect(item.originalName == "Sunset Over Water",
                "Rename should trim whitespace and update the name")

        // Re-fetch from the context to confirm the change was saved, not just
        // mutated on the in-memory object.
        let refetched = try #require(try context.fetch(FetchDescriptor<GalleryItem>()).first)
        #expect(refetched.originalName == "Sunset Over Water",
                "Rename must persist through the ModelContext")
    }

    @Test func renameGalleryItemIgnoresEmptyOrWhitespaceName() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)
        let original = item.originalName

        coordinator.renameGalleryItem(item, to: "")
        #expect(item.originalName == original, "Empty name should be ignored")

        coordinator.renameGalleryItem(item, to: "   \n  ")
        #expect(item.originalName == original, "Whitespace-only name should be ignored")
    }

    // MARK: - Pinning (#0035)

    @Test func togglePinFlipsAndPersistsPinnedState() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)
        #expect(!item.isPinned, "A freshly imported item should be unpinned")

        coordinator.togglePin(item)
        #expect(item.isPinned, "First toggle should pin the item")

        // Re-fetch from the context to confirm the change was saved, not just
        // mutated on the in-memory object.
        let refetched = try #require(try context.fetch(FetchDescriptor<GalleryItem>()).first)
        #expect(refetched.isPinned, "Pinned state must persist through the ModelContext")

        coordinator.togglePin(item)
        #expect(!item.isPinned, "Second toggle should unpin the item")
    }

    @Test func effectiveImportedImageNameDefaulting() {
        // Filename with extension → base name.
        #expect(effectiveImportedImageName(from: "sunset.png") == "sunset")
        #expect(effectiveImportedImageName(from: "my.photo.heic") == "my.photo")
        // Whitespace around a name is trimmed.
        #expect(effectiveImportedImageName(from: "  beach  ") == "beach")
        // nil or empty → the default fallback.
        #expect(effectiveImportedImageName(from: nil) == "Imported Image")
        #expect(effectiveImportedImageName(from: "") == "Imported Image")
        #expect(effectiveImportedImageName(from: "   ") == "Imported Image")
    }

    // MARK: - Original image display (#0017)

    /// The exact path the gallery views use to render an imported original:
    /// import → load bytes back from storage → decode/downsample to an image.
    /// This is the regression guard for "imported image never displays".
    @Test func importedImageCanBeLoadedBackAndDecoded() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let pngData = try Self.makePNGData(width: 400, height: 300)
        try await coordinator.createGalleryItem(name: "Photo", imageData: pngData)
        let item = try #require(try context.fetch(FetchDescriptor<GalleryItem>()).first)
        #expect(!item.originalImagePath.isEmpty)

        // The views load the stored original through this coordinator method.
        let loaded = await coordinator.loadOriginalImageData(path: item.originalImagePath)
        let bytes = try #require(loaded, "Stored original must be loadable for display")
        #expect(bytes == pngData, "Loaded bytes must match what was imported")

        // And StoredImageView decodes those bytes into a renderable image.
        let cg = try #require(StoredImageDecoder.downsample(bytes, maxPixelSize: 180),
                              "Imported original must decode to a CGImage")
        #expect(max(cg.width, cg.height) <= 180,
                "Thumbnail must be downsampled to the requested max edge")
        #expect(cg.width > 0)
        #expect(cg.height > 0)
    }

    @Test func storedImageDecoderPreservesAspectRatioWhenDownsampling() throws {
        let data = try Self.makePNGData(width: 400, height: 200)
        let cg = try #require(StoredImageDecoder.downsample(data, maxPixelSize: 100))
        #expect(max(cg.width, cg.height) == 100, "Longest edge should hit the max")
        // 2:1 source → 2:1 thumbnail (100×50), allowing 1px rounding.
        #expect(abs(Double(cg.width) / Double(cg.height) - 2.0) <= 0.05)
    }

    @Test func storedImageDecoderReturnsNilForInvalidData() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        #expect(StoredImageDecoder.downsample(garbage, maxPixelSize: 64) == nil,
                "Undecodable data should yield nil, not crash")
    }

    // MARK: - Default display seeding (#0021)

    @Test func seedDefaultDisplayWhenRegistryIsEmpty() throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let seeded = coordinator.seedDefaultDisplayIfNeeded()
        #expect(seeded, "An empty registry should be seeded with the default display")

        let displays = try context.fetch(FetchDescriptor<FlaschenTaschenDisplay>())
        #expect(displays.count == 1)
        let display = try #require(displays.first)
        #expect(display.host == "flaschentaschen.local")
        #expect(display.port == 1337)
        #expect(display.displayWidth == 45)
        #expect(display.displayHeight == 35)
        #expect(display.displayName == "Flaschen Taschen")
        #expect(display.source == FlaschenTaschenDisplay.defaultSource,
                "The seeded display must be marked as the built-in default")
    }

    @Test func seedDefaultDisplayIsIdempotent() throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        #expect(coordinator.seedDefaultDisplayIfNeeded())
        #expect(!coordinator.seedDefaultDisplayIfNeeded(),
                "A second call must not seed again")

        let displays = try context.fetch(FetchDescriptor<FlaschenTaschenDisplay>())
        #expect(displays.count == 1, "Repeated seeding must never create duplicates")
    }

    @Test func seedDefaultDisplaySkipsWhenAnyDisplayExists() throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        try coordinator.addManualDisplay(
            host: "10.0.0.9", port: 1337, displayName: "Office",
            displayWidth: 64, displayHeight: 32
        )

        let seeded = coordinator.seedDefaultDisplayIfNeeded()
        #expect(!seeded, "A non-empty registry must not be seeded")

        let displays = try context.fetch(FetchDescriptor<FlaschenTaschenDisplay>())
        #expect(displays.count == 1, "Only the pre-existing manual display should remain")
        #expect(displays.first?.source == "manual")
    }

    // MARK: - Display-fitted variants (#0063)

    /// A square 16×16 source into a non-square 64×32 display must produce a
    /// variant sized to the *fit* dimensions (32×32), not the raw display
    /// dimensions — the regression guard for treating `createFittedVariant`
    /// as a plain display-dims passthrough.
    @Test func createFittedVariantUsesFitDimensionsNotDisplayDimensions() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let display = FlaschenTaschenDisplay(
            host: "10.0.0.2", port: 1337, displayName: "Wide Wall",
            displayWidth: 64, displayHeight: 32
        )
        context.insert(display)
        try context.save()

        let item = try await makeItem(in: context, coordinator: coordinator)

        let variant = try await coordinator.createFittedVariant(for: item, display: display)

        #expect(variant.targetWidth == 32, "16x16 source into 64x32 display should fit to 32x32, not 64x32")
        #expect(variant.targetHeight == 32)
        #expect(variant.pixelGridData.count == 32 * 32 * 4)
        #expect(variant.associatedDisplayId == display.id)

        let variants = try context.fetch(FetchDescriptor<Variant>())
        #expect(variants.count == 1)
        #expect(variants.first?.id == variant.id, "The returned variant must be the one persisted in the context")
    }

    /// Re-invoking `createFittedVariant` for the same item + display must
    /// reuse the existing fitted variant rather than spawning a duplicate.
    @Test func createFittedVariantDedupsForSameItemAndDisplay() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let display = FlaschenTaschenDisplay(
            host: "10.0.0.3", port: 1337, displayName: "Office",
            displayWidth: 64, displayHeight: 32
        )
        context.insert(display)
        try context.save()

        let item = try await makeItem(in: context, coordinator: coordinator)

        let first = try await coordinator.createFittedVariant(for: item, display: display)
        let second = try await coordinator.createFittedVariant(for: item, display: display)

        #expect(first.id == second.id, "Re-selecting the same display must reuse the existing fitted variant")
        #expect(item.variants.count == 1, "Dedup must not add a second variant")

        let variants = try context.fetch(FetchDescriptor<Variant>())
        #expect(variants.count == 1, "The store must not contain a duplicate fitted variant")
    }

    /// A different display for the same item is a genuinely new fit and must
    /// create a second, independent variant.
    @Test func createFittedVariantCreatesSeparateVariantPerDisplay() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let displayA = FlaschenTaschenDisplay(
            host: "10.0.0.4", port: 1337, displayName: "Wall A",
            displayWidth: 64, displayHeight: 32
        )
        let displayB = FlaschenTaschenDisplay(
            host: "10.0.0.5", port: 1337, displayName: "Wall B",
            displayWidth: 45, displayHeight: 35
        )
        context.insert(displayA)
        context.insert(displayB)
        try context.save()

        let item = try await makeItem(in: context, coordinator: coordinator)

        let variantA = try await coordinator.createFittedVariant(for: item, display: displayA)
        let variantB = try await coordinator.createFittedVariant(for: item, display: displayB)

        #expect(variantA.id != variantB.id)
        #expect(item.variants.count == 2)
    }

    // MARK: - Helpers

    private static func makePNGData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let mutableData = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), "Failed to encode PNG")
        return mutableData as Data
    }
}
