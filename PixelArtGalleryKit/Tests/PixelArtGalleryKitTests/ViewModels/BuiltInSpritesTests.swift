import Testing
import Foundation
import CoreGraphics
import ImageIO
import SwiftData
import UniformTypeIdentifiers
@testable import PixelArtGalleryKit

/// Tests for the bundled built-in sprites (#0074): bundling
/// (``GalleryCoordinator/builtInSpriteData(for:)``),
/// ``GalleryCoordinator/reconcileBuiltInSpritesIfNeeded()``'s always-present,
/// never-delete reconcile, the delete/rename backstops on `GalleryItem`s
/// flagged `isBuiltIn`, and the pure ``GalleryPartition/partition(_:)`` helper.
///
/// Mirrors the setup in `GalleryCoordinatorTests`: an in-memory `ModelContext`
/// and a per-test temporary directory backing `FileStorageManager`.
@MainActor
@Suite final class BuiltInSpritesTests {

    /// Unique per-test temporary directory that backs the coordinator's
    /// ``FileStorageManager``, so imports never write into the user's real
    /// `Application Support/PixelArtGallery/Images` directory.
    private let tempDirectory: URL

    init() {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuiltInSpritesTests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeCoordinator() throws -> GalleryCoordinator {
        GalleryCoordinator(fileStorage: try FileStorageManager(imageDirectory: tempDirectory))
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: GalleryItem.self, Variant.self, FlaschenTaschenDisplay.self,
            configurations: config
        )
        return ModelContext(container)
    }

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

    // MARK: - Bundling

    @Test func allBuiltInSpriteResourcesResolve() {
        for name in GalleryCoordinator.builtInSpriteNames {
            let data = GalleryCoordinator.builtInSpriteData(for: name)
            #expect(data != nil, "Bundle.module should resolve '\(name).png' under DefaultSprites")
            #expect((data?.isEmpty ?? true) == false, "'\(name).png' should have non-empty bytes")
        }
    }

    // MARK: - Reconcile: empty store

    /// The number of bundled built-in sprites, taken from the manifest so these
    /// tests stay correct as sprites are added or removed (#0078).
    private var builtInCount: Int { GalleryCoordinator.builtInSpriteNames.count }

    @Test func reconcileOnEmptyStoreInsertsAllBuiltIns() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let result = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(result.inserted == builtInCount, "An empty store should get all built-in sprites")
        #expect(result.updated == 0, "A fresh empty store has nothing to update")

        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount)
        #expect(items.allSatisfy { $0.isBuiltIn }, "Every reconciled item must be flagged isBuiltIn")
        #expect(items.allSatisfy { $0.originalWidth == 45 && $0.originalHeight == 35 },
                "Built-in sprites are 45×35")
        #expect(items.allSatisfy { !$0.contentHash.isEmpty }, "Built-ins still get a content hash")

        let expectedNames = Set(GalleryCoordinator.builtInSpriteNames.map { $0.capitalized })
        #expect(Set(items.map(\.originalName)) == expectedNames)
    }

    // MARK: - Reconcile: idempotent

    @Test func secondReconcileIsANoOp() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let first = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(first == BuiltInReconcileResult(inserted: builtInCount, updated: 0))

        let second = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(second == BuiltInReconcileResult(), "A second reconcile with all sprites present must insert or update nothing")

        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount, "Repeated reconcile must never create duplicates")
        let names = items.map(\.originalName)
        #expect(Set(names).count == names.count, "No duplicate names")
    }

    // MARK: - Reconcile: some present, re-inserts only the missing

    @Test func reconcileWithSomePresentInsertsOnlyMissing() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        _ = await coordinator.reconcileBuiltInSpritesIfNeeded()
        var items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount)

        // Simulate a damaged store: remove 4 built-ins directly via the
        // context, bypassing the coordinator's delete guard entirely.
        for item in items.prefix(4) {
            context.delete(item)
        }
        try context.save()

        items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount - 4)

        let reinserted = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(reinserted == BuiltInReconcileResult(inserted: 4, updated: 0), "Reconcile should insert exactly the 4 missing sprites")

        items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount, "Total should be back to the full built-in count")
        let names = items.map(\.originalName)
        #expect(Set(names).count == names.count, "No duplicate names after re-insertion")
    }

    // MARK: - Reconcile never touches/deletes user items

    @Test func reconcileNeverTouchesUserItems() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let userPNG = try Self.makePNGData(width: 16, height: 16)
        try await coordinator.createGalleryItem(name: "My Photo", imageData: userPNG)

        let inserted = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(inserted == BuiltInReconcileResult(inserted: builtInCount, updated: 0))

        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount + 1, "The user item plus all built-ins")

        let userItem = try #require(items.first { $0.originalName == "My Photo" })
        #expect(!userItem.isBuiltIn, "The user's item must remain unflagged")

        // Reconcile again: still never deletes or duplicates anything.
        let second = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(second == BuiltInReconcileResult())
        let itemsAfter = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(itemsAfter.count == builtInCount + 1, "Reconcile must never delete the user's item")
    }

    // MARK: - Hash-collision insert: identical bytes must not suppress a built-in

    @Test func reconcileInsertsBuiltInEvenWhenUserImportedIdenticalBytes() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let coinData = try #require(GalleryCoordinator.builtInSpriteData(for: "coin"),
                                     "coin.png must resolve from the bundle for this test")

        // A user "coincidentally" imports bytes identical to a bundled sprite.
        let result = try await coordinator.createGalleryItem(name: "Weird Coin", imageData: coinData)
        #expect(result == .created)
        #expect(coordinator.importMessage == nil)

        let inserted = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(inserted == BuiltInReconcileResult(inserted: builtInCount, updated: 0), "The dup-check bypass must let all built-ins insert regardless")
        #expect(coordinator.importMessage == nil, "Reconcile must never surface the duplicate-import message")

        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount + 1, "The user's item plus all built-ins, including the built-in 'Coin'")
        #expect(items.contains { $0.originalName == "Coin" && $0.isBuiltIn })
        #expect(items.contains { $0.originalName == "Weird Coin" && !$0.isBuiltIn })
    }

    // MARK: - Reconcile: update-on-content-change (#0075)

    @Test func reconcileUpdatesBuiltInWhoseStoredContentDiffers() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        _ = await coordinator.reconcileBuiltInSpritesIfNeeded()
        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        let coinItem = try #require(items.first { $0.originalName == "Coin" })
        let originalID = coinItem.id

        // Simulate a stale install: swap in synthetic "old" bytes and hash,
        // as if this item was inserted by an earlier version of the bundle.
        let storage = try FileStorageManager(imageDirectory: tempDirectory)
        let staleBytes = try Self.makePNGData(width: 9, height: 9)
        let stalePath = try await storage.save(imageData: staleBytes)
        coinItem.originalImagePath = stalePath
        coinItem.originalWidth = 9
        coinItem.originalHeight = 9
        coinItem.contentHash = GalleryCoordinator.contentHash(for: staleBytes)
        try context.save()

        let result = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(result == BuiltInReconcileResult(inserted: 0, updated: 1))

        let itemsAfter = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(itemsAfter.count == builtInCount, "Updating must not re-insert or duplicate")
        let updatedCoin = try #require(itemsAfter.first { $0.originalName == "Coin" })
        #expect(updatedCoin.id == originalID, "The same GalleryItem instance/id must be preserved")

        let bundledData = try #require(GalleryCoordinator.builtInSpriteData(for: "coin"))
        #expect(updatedCoin.contentHash == GalleryCoordinator.contentHash(for: bundledData))
        #expect(updatedCoin.originalWidth == 45)
        #expect(updatedCoin.originalHeight == 35)
        #expect(updatedCoin.originalImagePath != stalePath, "A new file must be written, never overwritten in place")

        let staleStillExists = await storage.exists(filename: stalePath)
        #expect(staleStillExists == false, "The old (stale) file must be deleted after the update")
        let newFileExists = await storage.exists(filename: updatedCoin.originalImagePath)
        #expect(newFileExists == true, "The newly-saved file must exist on disk")
    }

    @Test func reconcileIsANoOpWhenAllContentMatches() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        _ = await coordinator.reconcileBuiltInSpritesIfNeeded()
        let itemsBefore = try context.fetch(FetchDescriptor<GalleryItem>())
        let pathsBefore = Dictionary(uniqueKeysWithValues: itemsBefore.map { ($0.originalName, $0.originalImagePath) })
        let hashesBefore = Dictionary(uniqueKeysWithValues: itemsBefore.map { ($0.originalName, $0.contentHash) })
        let fileCountBefore = try FileManager.default.contentsOfDirectory(
            at: tempDirectory, includingPropertiesForKeys: nil
        ).count

        let second = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(second == BuiltInReconcileResult(), "Matching content on every built-in must insert and update nothing")

        let itemsAfter = try context.fetch(FetchDescriptor<GalleryItem>())
        for item in itemsAfter {
            #expect(item.originalImagePath == pathsBefore[item.originalName], "No new file for '\(item.originalName)'")
            #expect(item.contentHash == hashesBefore[item.originalName])
        }

        let fileCountAfter = try FileManager.default.contentsOfDirectory(
            at: tempDirectory, includingPropertiesForKeys: nil
        ).count
        #expect(fileCountAfter == fileCountBefore, "No file churn when content already matches")
    }

    @Test func reconcileStillInsertsMissingWhileUpdatingStale() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        _ = await coordinator.reconcileBuiltInSpritesIfNeeded()
        var items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount)

        // Damaged-store simulation: remove 2 built-ins directly via the context.
        for item in items.prefix(2) {
            context.delete(item)
        }
        try context.save()

        // Stale one of the remaining built-ins, as in the update test above.
        items = try context.fetch(FetchDescriptor<GalleryItem>())
        let staleItem = try #require(items.first)
        let storage = try FileStorageManager(imageDirectory: tempDirectory)
        let staleBytes = try Self.makePNGData(width: 9, height: 9)
        let stalePath = try await storage.save(imageData: staleBytes)
        staleItem.originalImagePath = stalePath
        staleItem.originalWidth = 9
        staleItem.originalHeight = 9
        staleItem.contentHash = GalleryCoordinator.contentHash(for: staleBytes)
        try context.save()

        let result = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(result == BuiltInReconcileResult(inserted: 2, updated: 1))

        items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount, "Total should be back to full count: 2 re-inserted, 1 updated in place")
    }

    @Test func reconcileUpdateLeavesUserItemsUntouched() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let userPNG = try Self.makePNGData(width: 16, height: 16)
        try await coordinator.createGalleryItem(name: "My Photo", imageData: userPNG)

        _ = await coordinator.reconcileBuiltInSpritesIfNeeded()
        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        let userItem = try #require(items.first { $0.originalName == "My Photo" })
        let userID = userItem.id
        let userPath = userItem.originalImagePath
        let userHash = userItem.contentHash

        let coinItem = try #require(items.first { $0.originalName == "Coin" })
        let storage = try FileStorageManager(imageDirectory: tempDirectory)
        let staleBytes = try Self.makePNGData(width: 9, height: 9)
        let stalePath = try await storage.save(imageData: staleBytes)
        coinItem.originalImagePath = stalePath
        coinItem.contentHash = GalleryCoordinator.contentHash(for: staleBytes)
        try context.save()

        let result = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(result == BuiltInReconcileResult(inserted: 0, updated: 1))

        let itemsAfter = try context.fetch(FetchDescriptor<GalleryItem>())
        let userItemAfter = try #require(itemsAfter.first { $0.originalName == "My Photo" })
        #expect(userItemAfter.id == userID, "The user item's id must be untouched by a built-in update")
        #expect(userItemAfter.originalImagePath == userPath)
        #expect(userItemAfter.contentHash == userHash)
        #expect(!userItemAfter.isBuiltIn)
    }

    @Test func userVariantOnBuiltInSurvivesUpdate() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        _ = await coordinator.reconcileBuiltInSpritesIfNeeded()
        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        let coinItem = try #require(items.first { $0.originalName == "Coin" })

        let variant = try await coordinator.createVariant(for: coinItem, width: 10, height: 10)
        let variantID = variant.id
        let variantPixelData = variant.pixelGridData

        let storage = try FileStorageManager(imageDirectory: tempDirectory)
        let staleBytes = try Self.makePNGData(width: 9, height: 9)
        let stalePath = try await storage.save(imageData: staleBytes)
        coinItem.originalImagePath = stalePath
        coinItem.contentHash = GalleryCoordinator.contentHash(for: staleBytes)
        try context.save()

        let result = await coordinator.reconcileBuiltInSpritesIfNeeded()
        #expect(result == BuiltInReconcileResult(inserted: 0, updated: 1))

        let itemsAfter = try context.fetch(FetchDescriptor<GalleryItem>())
        let updatedCoin = try #require(itemsAfter.first { $0.originalName == "Coin" })
        #expect(updatedCoin.variants.count == 1, "The update must not cascade or recreate the existing variant")
        let survivingVariant = try #require(updatedCoin.variants.first)
        #expect(survivingVariant.id == variantID, "The variant's id must be unchanged")
        #expect(survivingVariant.pixelGridData == variantPixelData, "The variant's pixel data must be unchanged")
    }

    // MARK: - Delete/rename protection

    @Test func deleteGalleryItemRefusesBuiltInsButRemovesUserItems() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        let userPNG = try Self.makePNGData(width: 16, height: 16)
        try await coordinator.createGalleryItem(name: "My Photo", imageData: userPNG)
        _ = await coordinator.reconcileBuiltInSpritesIfNeeded()

        var items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount + 1)

        let builtIn = try #require(items.first { $0.isBuiltIn })
        coordinator.deleteGalleryItem(builtIn)

        items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount + 1, "Deleting a built-in must be a refused no-op")

        let userItem = try #require(items.first { !$0.isBuiltIn })
        coordinator.deleteGalleryItem(userItem)

        items = try context.fetch(FetchDescriptor<GalleryItem>())
        #expect(items.count == builtInCount, "Deleting a user item must succeed")
        #expect(items.allSatisfy { $0.isBuiltIn }, "Only built-ins should remain")
    }

    @Test func renameGalleryItemIsANoOpForBuiltIns() async throws {
        let context = try makeContext()
        let coordinator = try makeCoordinator()
        coordinator.configure(modelContext: context)

        _ = await coordinator.reconcileBuiltInSpritesIfNeeded()
        let items = try context.fetch(FetchDescriptor<GalleryItem>())
        let builtIn = try #require(items.first { $0.isBuiltIn })
        let originalName = builtIn.originalName

        coordinator.renameGalleryItem(builtIn, to: "Renamed Sprite")

        #expect(builtIn.originalName == originalName, "Renaming a built-in must be a no-op")
    }

    // MARK: - Partition helper

    @Test func partitionSplitsMixedListPreservingOrder() {
        let a = makeStandaloneItem(name: "A", isBuiltIn: false)
        let b = makeStandaloneItem(name: "B", isBuiltIn: true)
        let c = makeStandaloneItem(name: "C", isBuiltIn: false)
        let d = makeStandaloneItem(name: "D", isBuiltIn: true)
        let e = makeStandaloneItem(name: "E", isBuiltIn: false)

        let result = GalleryPartition.partition([a, b, c, d, e])
        #expect(result.user.map(\.originalName) == ["A", "C", "E"])
        #expect(result.builtIn.map(\.originalName) == ["B", "D"])
    }

    @Test func partitionAllUserYieldsEmptyBuiltInHalf() {
        let items = [
            makeStandaloneItem(name: "A", isBuiltIn: false),
            makeStandaloneItem(name: "B", isBuiltIn: false),
        ]
        let result = GalleryPartition.partition(items)
        #expect(result.user.map(\.originalName) == ["A", "B"])
        #expect(result.builtIn.isEmpty)
    }

    @Test func partitionAllBuiltInYieldsEmptyUserHalf() {
        let items = [
            makeStandaloneItem(name: "A", isBuiltIn: true),
            makeStandaloneItem(name: "B", isBuiltIn: true),
        ]
        let result = GalleryPartition.partition(items)
        #expect(result.builtIn.map(\.originalName) == ["A", "B"])
        #expect(result.user.isEmpty)
    }

    /// A standalone (uninserted) gallery item for pure partition testing — no
    /// container needed, mirroring `GallerySortOrderTests`.
    private func makeStandaloneItem(name: String, isBuiltIn: Bool) -> GalleryItem {
        GalleryItem(
            originalImagePath: "\(name).png",
            originalName: name,
            originalWidth: 45,
            originalHeight: 35,
            isBuiltIn: isBuiltIn
        )
    }
}
