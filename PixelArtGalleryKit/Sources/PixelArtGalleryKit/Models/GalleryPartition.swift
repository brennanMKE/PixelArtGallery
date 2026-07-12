import Foundation

/// Splits gallery items into the user's imports and the bundled built-in
/// sprites (#0074) for the gallery grid's two sections.
nonisolated enum GalleryPartition {
    /// Partition `items` into user imports (`isBuiltIn == false`) and
    /// built-in sprites (`isBuiltIn == true`), preserving each group's
    /// relative order from the input (typically already
    /// ``GallerySortOrder/sortedForGallery(_:)``-ordered, so pinning and the
    /// user's chosen sort apply within each section for free).
    /// - Parameter items: The gallery items to split, in display order.
    /// - Returns: The `user` and `builtIn` partitions, each order-preserving.
    static func partition(_ items: [GalleryItem]) -> (user: [GalleryItem], builtIn: [GalleryItem]) {
        var user: [GalleryItem] = []
        var builtIn: [GalleryItem] = []
        for item in items {
            if item.isBuiltIn {
                builtIn.append(item)
            } else {
                user.append(item)
            }
        }
        return (user, builtIn)
    }
}
