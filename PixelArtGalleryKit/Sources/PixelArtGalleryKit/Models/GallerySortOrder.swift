import Foundation

/// User-selectable ordering for the gallery grid (#0035).
///
/// The raw value is persisted in `@AppStorage("gallerySortOrder")`, so cases
/// must keep their names stable across releases.
nonisolated public enum GallerySortOrder: String, CaseIterable, Sendable {
    /// Most recently imported first — the gallery's historical default.
    case newestFirst
    /// Oldest import first.
    case oldestFirst
    /// Name A→Z (localized, Finder-style comparison).
    case nameAscending
    /// Name Z→A (localized, Finder-style comparison).
    case nameDescending

    /// Human-readable label for the sort menu.
    public var displayName: String {
        switch self {
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        case .nameAscending: "Name (A–Z)"
        case .nameDescending: "Name (Z–A)"
        }
    }
}

extension GallerySortOrder {
    /// Order items for the gallery grid: pinned items always lead, and the
    /// pinned and unpinned groups are each ordered by this sort.
    ///
    /// Rule: partition into pinned/unpinned, sort each group by the chosen
    /// order, and concatenate pinned + unpinned. Ties are broken
    /// deterministically (equal dates fall back to name A→Z; equal names fall
    /// back to newest first) so the grid is stable even though `sort` isn't
    /// guaranteed to be.
    public func sortedForGallery(_ items: [GalleryItem]) -> [GalleryItem] {
        let pinned = items.filter(\.isPinned).sorted(by: isOrderedBefore)
        let unpinned = items.filter { !$0.isPinned }.sorted(by: isOrderedBefore)
        return pinned + unpinned
    }

    /// The within-group comparison for this sort order.
    private func isOrderedBefore(_ lhs: GalleryItem, _ rhs: GalleryItem) -> Bool {
        switch self {
        case .newestFirst:
            if lhs.importedDate != rhs.importedDate {
                return lhs.importedDate > rhs.importedDate
            }
            return Self.nameAscending(lhs, before: rhs)
        case .oldestFirst:
            if lhs.importedDate != rhs.importedDate {
                return lhs.importedDate < rhs.importedDate
            }
            return Self.nameAscending(lhs, before: rhs)
        case .nameAscending:
            switch lhs.originalName.localizedStandardCompare(rhs.originalName) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.importedDate > rhs.importedDate
            }
        case .nameDescending:
            switch lhs.originalName.localizedStandardCompare(rhs.originalName) {
            case .orderedAscending: return false
            case .orderedDescending: return true
            case .orderedSame: return lhs.importedDate > rhs.importedDate
            }
        }
    }

    /// Shared name A→Z tie-break used by the date-based sorts.
    private static func nameAscending(_ lhs: GalleryItem, before rhs: GalleryItem) -> Bool {
        lhs.originalName.localizedStandardCompare(rhs.originalName) == .orderedAscending
    }
}
