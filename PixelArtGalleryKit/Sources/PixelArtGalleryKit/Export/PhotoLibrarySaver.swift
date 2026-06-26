import Foundation

#if os(iOS)
import Photos
#endif

/// Errors thrown while saving an exported image into the Photos library on iOS.
nonisolated public enum PhotoLibrarySaveError: Error, Equatable {
    /// The format is not a raster image and cannot be added to the Photos library.
    case unsupportedFormat(format: String)
    /// The user denied (or restricted) add-only access to the Photos library.
    case notAuthorized
    /// The underlying `PHPhotoLibrary` change request failed.
    case saveFailed(underlying: String)
    /// Photos saving is not available on this platform (e.g. macOS).
    case unavailable
}

/// Saves an exported image into the iOS Photos library using add-only authorization.
///
/// Only raster formats (`PNG` / `HEIC`) can be added to Photos; vector/data formats
/// (`PPM` / `JSON`) are not image assets the Photos library understands, so they must be
/// saved via the Files document picker / share sheet instead. The format-eligibility logic
/// (``canSaveToPhotos(_:)``) is pure and platform-agnostic so it can be unit-tested without a
/// Photos runtime.
nonisolated public struct PhotoLibrarySaver: Sendable {
    public init() {}

    /// Whether `format` produces a raster image that can be added to the Photos library.
    ///
    /// `true` for `.png` / `.heic`; `false` for `.ppm` / `.json`, which are not Photos assets.
    public static func canSaveToPhotos(_ format: ExportFormat) -> Bool {
        switch format {
        case .png, .heic:
            return true
        case .ppm, .json:
            return false
        }
    }

    /// Add the encoded image at `fileURL` (already written by `VariantExporter`) to the Photos
    /// library, requesting add-only authorization first.
    ///
    /// - Throws: `PhotoLibrarySaveError.unsupportedFormat` for non-raster formats,
    ///   `.notAuthorized` if the user denies access, `.saveFailed` if the change request fails,
    ///   or `.unavailable` on platforms without a Photos library.
    public func saveToPhotos(fileURL: URL, format: ExportFormat) async throws {
        guard Self.canSaveToPhotos(format) else {
            AppLog.export.warning("Cannot save \(format.rawValue, privacy: .public) to Photos: not a raster image")
            throw PhotoLibrarySaveError.unsupportedFormat(format: format.rawValue)
        }

        #if os(iOS)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            AppLog.export.warning("Photos add-only authorization denied")
            throw PhotoLibrarySaveError.notAuthorized
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: fileURL, options: nil)
            }
            AppLog.export.info("Saved \(format.rawValue, privacy: .public) to Photos library")
        } catch {
            AppLog.export.error("Failed to save to Photos: \(error.localizedDescription, privacy: .public)")
            throw PhotoLibrarySaveError.saveFailed(underlying: error.localizedDescription)
        }
        #else
        throw PhotoLibrarySaveError.unavailable
        #endif
    }
}
