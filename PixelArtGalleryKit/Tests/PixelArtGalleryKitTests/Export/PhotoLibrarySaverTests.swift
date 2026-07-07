import Testing
import Foundation
@testable import PixelArtGalleryKit

/// Device-free tests for the platform-agnostic logic in `PhotoLibrarySaver`.
///
/// The actual Photos-library write requires a Photos runtime and user authorization, which
/// cannot be exercised headlessly. These tests cover the pure format-eligibility logic and the
/// guard that rejects non-raster formats before any authorization request is made. Regression
/// for #0008, where iOS had no export destination at all.
@Suite struct PhotoLibrarySaverTests {

    @Test func rasterFormatsAreEligibleForPhotos() {
        #expect(PhotoLibrarySaver.canSaveToPhotos(.png))
        #expect(PhotoLibrarySaver.canSaveToPhotos(.heic))
    }

    @Test func nonRasterFormatsAreNotEligibleForPhotos() {
        #expect(!PhotoLibrarySaver.canSaveToPhotos(.ppm))
        #expect(!PhotoLibrarySaver.canSaveToPhotos(.json))
    }

    /// A non-raster format must be rejected before any authorization / change request, on every
    /// platform, with `.unsupportedFormat`.
    @Test func saveToPhotosRejectsNonRasterFormat() async {
        let saver = PhotoLibrarySaver()
        let dummyURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("matrix.json")

        await #expect(throws: PhotoLibrarySaveError.unsupportedFormat(format: "JSON")) {
            try await saver.saveToPhotos(fileURL: dummyURL, format: .json)
        }
    }
}
