import os.log

/// Central definition of the app's structured `os.log` logging.
///
/// The PRD ("Logging") specifies a single unified-logging subsystem and a fixed
/// set of categories. Before this existed, individual types declared their own
/// `Logger(subsystem:category:)` with ad hoc subsystem strings
/// (`com.pixelartgallery.ui`, `com.pixelartgallery.networking`) and free-form
/// categories (`GalleryCoordinator`, `VariantDetailView`, `ExportPickerView`,
/// `FTSend`). `AppLog` replaces all of those so every module logs through one
/// subsystem with the PRD's canonical category names, at consistent levels:
/// `debug` for tracing, `info` for notable events, `warning`/`error` for failures.
///
/// Marked `nonisolated` (the package defaults to `@MainActor` isolation) so the
/// loggers can be used from the off-main-actor types too — `PixelationEngine`,
/// `VariantExporter`, `PhotoLibrarySaver`, and the `FTDiscoveryService` /
/// `FTDisplayClient` actors. `Logger` is `Sendable`, so the static loggers cross
/// isolation domains safely.
///
/// Usage:
/// ```swift
/// AppLog.imageProcessor.debug("Pixelating \(width)x\(height)")
/// AppLog.export.error("Export failed: \(message, privacy: .public)")
/// ```
nonisolated enum AppLog {
    /// The single unified-logging subsystem for the whole app. Matches the app's
    /// bundle identifier prefix so log entries group cleanly in Console.app.
    static let subsystem = "co.sstools.PixelArtGallery"

    /// The PRD's canonical logging categories. Each value is the `category`
    /// string passed to the corresponding `Logger`, and is also used directly in
    /// tests to assert the category set without touching a live `Logger`.
    enum Category: String, CaseIterable {
        /// Gallery item lifecycle: import, duplicate detection, deletion.
        case gallery = "Gallery"
        /// Image pixelation in `PixelationEngine`.
        case imageProcessor = "ImageProcessor"
        /// Variant lifecycle: creation, duplication, dimension edits, deletion.
        case variant = "Variant"
        /// FT display discovery (mDNS) and network sends.
        ///
        /// The PRD lists a single `FTDiscovery` category for all FT networking;
        /// the former separate `FTSend` category is folded into this one so the
        /// category set matches the PRD exactly.
        case ftDiscovery = "FTDiscovery"
        /// Variant export (PNG/HEIC/PPM/JSON), Photos saves, and Files exports.
        case export = "Export"
        /// Pixel grid rendering in the UI.
        case gridRenderer = "GridRenderer"
        /// Sparkle auto-update lifecycle on macOS (`UpdaterController`).
        case updates = "Updates"
    }

    /// Gallery item lifecycle.
    static let gallery = Logger(subsystem: subsystem, category: Category.gallery.rawValue)
    /// Image pixelation.
    static let imageProcessor = Logger(subsystem: subsystem, category: Category.imageProcessor.rawValue)
    /// Variant lifecycle.
    static let variant = Logger(subsystem: subsystem, category: Category.variant.rawValue)
    /// FT display discovery and sends.
    static let ftDiscovery = Logger(subsystem: subsystem, category: Category.ftDiscovery.rawValue)
    /// Export, Photos, and Files.
    static let export = Logger(subsystem: subsystem, category: Category.export.rawValue)
    /// Pixel grid rendering.
    static let gridRenderer = Logger(subsystem: subsystem, category: Category.gridRenderer.rawValue)
    /// Sparkle auto-update lifecycle (macOS).
    static let updates = Logger(subsystem: subsystem, category: Category.updates.rawValue)
}
