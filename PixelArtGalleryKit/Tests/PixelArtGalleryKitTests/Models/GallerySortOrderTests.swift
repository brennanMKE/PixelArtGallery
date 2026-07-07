import Testing
import Foundation
@testable import PixelArtGalleryKit

/// Tests for ``GallerySortOrder/sortedForGallery(_:)``, the pure ordering rule
/// behind the gallery grid (#0035): pinned items always lead regardless of the
/// chosen sort, and the pinned and unpinned groups are each ordered by that
/// sort.
@MainActor
@Suite struct GallerySortOrderTests {

    /// A reference date so imported dates are deterministic; items are offset
    /// from it in whole days.
    private let baseDate = Date(timeIntervalSince1970: 1_750_000_000)

    /// Build a standalone (uninserted) gallery item — SwiftData models don't
    /// need a container for pure sorting tests.
    private func makeItem(name: String, daysAgo: Int, pinned: Bool = false) -> GalleryItem {
        let item = GalleryItem(
            originalImagePath: "\(name).png",
            originalName: name,
            originalWidth: 16,
            originalHeight: 16,
            importedDate: baseDate.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        )
        item.isPinned = pinned
        return item
    }

    /// The display-order names produced by a sort.
    private func names(_ order: GallerySortOrder, _ items: [GalleryItem]) -> [String] {
        order.sortedForGallery(items).map(\.originalName)
    }

    // MARK: - Pinned items lead

    @Test func pinnedItemsLeadRegardlessOfSortOrder() {
        // The pinned items ("Yak", "Zebra") would sort last by name ascending
        // and are also the oldest, so every order has to fight for them.
        let items = [
            makeItem(name: "Apple", daysAgo: 0),
            makeItem(name: "Banana", daysAgo: 1),
            makeItem(name: "Yak", daysAgo: 9, pinned: true),
            makeItem(name: "Zebra", daysAgo: 8, pinned: true)
        ]

        for order in GallerySortOrder.allCases {
            let sorted = order.sortedForGallery(items)
            let leadsWithPinned = sorted.prefix(2).allSatisfy(\.isPinned)
            #expect(leadsWithPinned, "\(order) should lead with the pinned items")
            let restUnpinned = sorted.dropFirst(2).allSatisfy { !$0.isPinned }
            #expect(restUnpinned, "\(order) should keep unpinned items after the pinned group")
        }
    }

    @Test func pinnedGroupUsesChosenSortWithinGroup() {
        let items = [
            makeItem(name: "Apple", daysAgo: 0),
            makeItem(name: "Yak", daysAgo: 9, pinned: true),
            makeItem(name: "Zebra", daysAgo: 8, pinned: true)
        ]

        // Zebra is newer than Yak, so newest-first leads with Zebra…
        #expect(names(.newestFirst, items) == ["Zebra", "Yak", "Apple"])
        // …oldest-first with Yak…
        #expect(names(.oldestFirst, items) == ["Yak", "Zebra", "Apple"])
        // …and the name sorts order the pinned pair alphabetically.
        #expect(names(.nameAscending, items) == ["Yak", "Zebra", "Apple"])
        #expect(names(.nameDescending, items) == ["Zebra", "Yak", "Apple"])
    }

    // MARK: - Each sort order (no pins involved)

    private var unpinnedItems: [GalleryItem] {
        [
            makeItem(name: "Banana", daysAgo: 2),
            makeItem(name: "apple", daysAgo: 1),
            makeItem(name: "Cherry", daysAgo: 3)
        ]
    }

    @Test func newestFirstWithNoPinnedItems() {
        #expect(names(.newestFirst, unpinnedItems) == ["apple", "Banana", "Cherry"])
    }

    @Test func oldestFirstWithNoPinnedItems() {
        #expect(names(.oldestFirst, unpinnedItems) == ["Cherry", "Banana", "apple"])
    }

    @Test func nameAscendingIsCaseInsensitive() {
        // localizedStandardCompare puts "apple" before "Banana" despite case.
        #expect(names(.nameAscending, unpinnedItems) == ["apple", "Banana", "Cherry"])
    }

    @Test func nameDescendingWithNoPinnedItems() {
        #expect(names(.nameDescending, unpinnedItems) == ["Cherry", "Banana", "apple"])
    }

    @Test func nameAscendingUsesNumericFinderStyleComparison() {
        let items = [
            makeItem(name: "Frame 10", daysAgo: 0),
            makeItem(name: "Frame 2", daysAgo: 1)
        ]
        #expect(names(.nameAscending, items) == ["Frame 2", "Frame 10"])
    }

    // MARK: - Determinism

    @Test func equalNamesTieBreakByNewestFirst() {
        let older = makeItem(name: "Same", daysAgo: 5)
        let newer = makeItem(name: "Same", daysAgo: 1)

        for order in [GallerySortOrder.nameAscending, .nameDescending] {
            let sorted = order.sortedForGallery([older, newer])
            #expect(
                sorted.map(\.importedDate) == [newer.importedDate, older.importedDate],
                "\(order) should break name ties newest-first"
            )
        }
    }

    @Test func emptyInputReturnsEmpty() {
        for order in GallerySortOrder.allCases {
            #expect(order.sortedForGallery([]).isEmpty)
        }
    }
}
