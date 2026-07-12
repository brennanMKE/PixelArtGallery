import Foundation

/// Transient fitted preview of a gallery item for one FT display (#0066).
///
/// Built on demand by ``GalleryCoordinator/fittedPreview(for:display:)`` and
/// never persisted — it exists so the popover flow ([#0067](0067.md)) can show
/// (and re-show) the aspect-fit pixelation for a display selection without
/// accumulating a saved ``Variant`` for every glance. An explicit call to
/// ``GalleryCoordinator/saveVariant(from:)`` is what turns one of these into a
/// persisted `Variant`.
///
/// `nonisolated` because `Package.swift` default-isolates the main target to
/// `@MainActor` — a pure value type consumed from nonisolated tests and
/// off-main-actor callers must opt out explicitly rather than rely on that
/// default propagating (this bit #0057/#0060, and is why ``AspectFit`` and
/// ``PixelGrid`` are marked the same way).
nonisolated struct FittedPreview: Equatable, Sendable {
    /// Identifies the source ``GalleryItem`` — used by ``GalleryCoordinator/saveVariant(from:)``
    /// to re-locate the item, and is half of ``FittedPreviewCacheKey``.
    let itemID: UUID
    /// Becomes `Variant.associatedDisplayId` on save; routes the FT send.
    let displayID: UUID
    /// Fit width in pixels (aspect-preserving) — equal to the pixel grid's
    /// width. NOT the display's width.
    let width: Int
    /// Fit height in pixels — equal to the pixel grid's height.
    let height: Int
    /// RGBA8888 flattened pixel data, `width * height * 4` bytes — the exact
    /// encoding ``Variant/pixelGridData`` persists, so saving is a byte copy.
    let pixelGridData: Data
    /// Horizontal centering offset (``AspectFit``) for placing the fit result
    /// on the display's canvas.
    let offsetX: Int
    /// Vertical centering offset (``AspectFit``) for placing the fit result on
    /// the display's canvas.
    let offsetY: Int
}

/// Cache key for a computed ``FittedPreview``.
///
/// Display dimensions are part of the key (not just the display's id) because
/// a display's geometry can change in place (mDNS re-scan, `updateDisplay`) —
/// a stale-geometry preview must miss the cache, not hit it.
nonisolated struct FittedPreviewCacheKey: Hashable, Sendable {
    let itemID: UUID
    let displayID: UUID
    let displayWidth: Int
    let displayHeight: Int
}
