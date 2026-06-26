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
