import XCTest
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
final class GalleryCoordinatorTests: XCTestCase {

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
        return try XCTUnwrap(items.first)
    }

    func testCreateVariantRecordsAssociatedDisplayId() async throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
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
        XCTAssertEqual(variants.count, 1)
        let variant = try XCTUnwrap(variants.first)
        XCTAssertEqual(variant.associatedDisplayId, display.id,
                       "Variant should remember the display it was sized for")
        XCTAssertEqual(variant.targetWidth, 64)
        XCTAssertEqual(variant.targetHeight, 32)
    }

    func testCreateVariantWithoutDisplayLeavesAssociationNil() async throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)

        try await coordinator.createVariant(for: item, width: 32, height: 32)

        let variants = try context.fetch(FetchDescriptor<Variant>())
        let variant = try XCTUnwrap(variants.first)
        XCTAssertNil(variant.associatedDisplayId,
                     "Custom dimensions should record no display association")
    }

    // MARK: - Deletion (#0029)

    func testDeleteGalleryItemRemovesItemAndCascadesVariants() async throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)
        try await coordinator.createVariant(for: item, width: 8, height: 8)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Variant>()).count, 1)

        coordinator.deleteGalleryItem(item)

        XCTAssertTrue(try context.fetch(FetchDescriptor<GalleryItem>()).isEmpty,
                      "Deleting a gallery item should remove it from the store")
        XCTAssertTrue(try context.fetch(FetchDescriptor<Variant>()).isEmpty,
                      "Deleting a gallery item should cascade-delete its variants")
    }

    // MARK: - Duplicate prevention (#0014)

    func testImportingSameBytesTwiceYieldsOneItem() async throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let pngData = try Self.makePNGData(width: 16, height: 16)

        let first = try await coordinator.createGalleryItem(name: "Original", imageData: pngData)
        XCTAssertEqual(first, .created, "First import of fresh bytes should create an item")

        let second = try await coordinator.createGalleryItem(name: "Copy", imageData: pngData)
        XCTAssertEqual(second, .duplicate(existingName: "Original"),
                       "Re-importing identical bytes should be reported as a duplicate")

        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        XCTAssertEqual(items.count, 1, "Duplicate import must not create a second gallery item")
        XCTAssertNotNil(coordinator.importMessage,
                        "A user-facing message should be set when a duplicate is skipped")
    }

    func testImportingDifferentBytesYieldsTwoItems() async throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let pngA = try Self.makePNGData(width: 16, height: 16)
        let pngB = try Self.makePNGData(width: 24, height: 24)
        XCTAssertNotEqual(pngA, pngB, "Test fixtures must differ for this to be meaningful")

        let first = try await coordinator.createGalleryItem(name: "A", imageData: pngA)
        let second = try await coordinator.createGalleryItem(name: "B", imageData: pngB)
        XCTAssertEqual(first, .created)
        XCTAssertEqual(second, .created)

        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        XCTAssertEqual(items.count, 2, "Distinct images should each create a gallery item")
    }

    // MARK: - Variant management (#0015)

    func testDuplicateVariantCopiesDataAndIncreasesCount() async throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)
        try await coordinator.createVariant(for: item, width: 8, height: 8)

        let original = try XCTUnwrap(try context.fetch(FetchDescriptor<Variant>()).first)
        let copy = try coordinator.duplicateVariant(original)

        let variants = try context.fetch(FetchDescriptor<Variant>())
        XCTAssertEqual(variants.count, 2, "Duplicating should add a second variant")
        XCTAssertNotEqual(copy.id, original.id, "The copy must be a distinct record")
        XCTAssertEqual(copy.targetWidth, original.targetWidth)
        XCTAssertEqual(copy.targetHeight, original.targetHeight)
        XCTAssertEqual(copy.pixelGridData, original.pixelGridData,
                       "Pixel data should be copied verbatim")
        XCTAssertEqual(copy.galleryItem?.id, item.id,
                       "The copy should belong to the same parent item")
    }

    func testUpdateVariantDimensionsRegeneratesPixelData() async throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)
        try await coordinator.createVariant(for: item, width: 8, height: 8)

        let variant = try XCTUnwrap(try context.fetch(FetchDescriptor<Variant>()).first)
        XCTAssertEqual(variant.pixelGridData.count, 8 * 8 * 4)

        try await coordinator.updateVariantDimensions(variant, width: 12, height: 6)

        XCTAssertEqual(variant.targetWidth, 12)
        XCTAssertEqual(variant.targetHeight, 6)
        XCTAssertEqual(variant.pixelGridData.count, 12 * 6 * 4,
                       "Regenerated pixel data length must match new width*height*4")

        // No extra variant was created — the same record was edited in place.
        let variants = try context.fetch(FetchDescriptor<Variant>())
        XCTAssertEqual(variants.count, 1)
    }

    // MARK: - Naming at import / rename (#0018)

    func testRenameGalleryItemUpdatesAndPersistsName() async throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)

        coordinator.renameGalleryItem(item, to: "  Sunset Over Water  ")

        XCTAssertEqual(item.originalName, "Sunset Over Water",
                       "Rename should trim whitespace and update the name")

        // Re-fetch from the context to confirm the change was saved, not just
        // mutated on the in-memory object.
        let refetched = try XCTUnwrap(try context.fetch(FetchDescriptor<GalleryItem>()).first)
        XCTAssertEqual(refetched.originalName, "Sunset Over Water",
                       "Rename must persist through the ModelContext")
    }

    func testRenameGalleryItemIgnoresEmptyOrWhitespaceName() async throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let item = try await makeItem(in: context, coordinator: coordinator)
        let original = item.originalName

        coordinator.renameGalleryItem(item, to: "")
        XCTAssertEqual(item.originalName, original, "Empty name should be ignored")

        coordinator.renameGalleryItem(item, to: "   \n  ")
        XCTAssertEqual(item.originalName, original, "Whitespace-only name should be ignored")
    }

    func testEffectiveImportedImageNameDefaulting() {
        // Filename with extension → base name.
        XCTAssertEqual(effectiveImportedImageName(from: "sunset.png"), "sunset")
        XCTAssertEqual(effectiveImportedImageName(from: "my.photo.heic"), "my.photo")
        // Whitespace around a name is trimmed.
        XCTAssertEqual(effectiveImportedImageName(from: "  beach  "), "beach")
        // nil or empty → the default fallback.
        XCTAssertEqual(effectiveImportedImageName(from: nil), "Imported Image")
        XCTAssertEqual(effectiveImportedImageName(from: ""), "Imported Image")
        XCTAssertEqual(effectiveImportedImageName(from: "   "), "Imported Image")
    }

    // MARK: - Original image display (#0017)

    /// The exact path the gallery views use to render an imported original:
    /// import → load bytes back from storage → decode/downsample to an image.
    /// This is the regression guard for "imported image never displays".
    func testImportedImageCanBeLoadedBackAndDecoded() async throws {
        let context = try makeContext()
        let coordinator = GalleryCoordinator()
        coordinator.configure(modelContext: context)

        let pngData = try Self.makePNGData(width: 400, height: 300)
        try await coordinator.createGalleryItem(name: "Photo", imageData: pngData)
        let item = try XCTUnwrap(try context.fetch(FetchDescriptor<GalleryItem>()).first)
        XCTAssertFalse(item.originalImagePath.isEmpty)

        // The views load the stored original through this coordinator method.
        let loaded = await coordinator.loadOriginalImageData(path: item.originalImagePath)
        let bytes = try XCTUnwrap(loaded, "Stored original must be loadable for display")
        XCTAssertEqual(bytes, pngData, "Loaded bytes must match what was imported")

        // And StoredImageView decodes those bytes into a renderable image.
        let cg = try XCTUnwrap(StoredImageDecoder.downsample(bytes, maxPixelSize: 180),
                               "Imported original must decode to a CGImage")
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 180,
                                 "Thumbnail must be downsampled to the requested max edge")
        XCTAssertGreaterThan(cg.width, 0)
        XCTAssertGreaterThan(cg.height, 0)
    }

    func testStoredImageDecoderPreservesAspectRatioWhenDownsampling() throws {
        let data = try Self.makePNGData(width: 400, height: 200)
        let cg = try XCTUnwrap(StoredImageDecoder.downsample(data, maxPixelSize: 100))
        XCTAssertEqual(max(cg.width, cg.height), 100, "Longest edge should hit the max")
        // 2:1 source → 2:1 thumbnail (100×50), allowing 1px rounding.
        XCTAssertEqual(Double(cg.width) / Double(cg.height), 2.0, accuracy: 0.05)
    }

    func testStoredImageDecoderReturnsNilForInvalidData() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        XCTAssertNil(StoredImageDecoder.downsample(garbage, maxPixelSize: 64),
                     "Undecodable data should yield nil, not crash")
    }

    // MARK: - Helpers

    private static func makePNGData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
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
        let image = try XCTUnwrap(context.makeImage())

        let mutableData = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "Failed to encode PNG")
        return mutableData as Data
    }
}
