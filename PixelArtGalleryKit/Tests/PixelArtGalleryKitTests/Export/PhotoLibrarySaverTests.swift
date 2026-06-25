import XCTest
@testable import PixelArtGalleryKit

/// Device-free tests for the platform-agnostic logic in `PhotoLibrarySaver`.
///
/// The actual Photos-library write requires a Photos runtime and user authorization, which
/// cannot be exercised headlessly. These tests cover the pure format-eligibility logic and the
/// guard that rejects non-raster formats before any authorization request is made. Regression
/// for #0008, where iOS had no export destination at all.
final class PhotoLibrarySaverTests: XCTestCase {

    func testRasterFormatsAreEligibleForPhotos() {
        XCTAssertTrue(PhotoLibrarySaver.canSaveToPhotos(.png))
        XCTAssertTrue(PhotoLibrarySaver.canSaveToPhotos(.heic))
    }

    func testNonRasterFormatsAreNotEligibleForPhotos() {
        XCTAssertFalse(PhotoLibrarySaver.canSaveToPhotos(.ppm))
        XCTAssertFalse(PhotoLibrarySaver.canSaveToPhotos(.json))
    }

    /// A non-raster format must be rejected before any authorization / change request, on every
    /// platform, with `.unsupportedFormat`.
    func testSaveToPhotosRejectsNonRasterFormat() async {
        let saver = PhotoLibrarySaver()
        let dummyURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("matrix.json")

        do {
            try await saver.saveToPhotos(fileURL: dummyURL, format: .json)
            XCTFail("Expected saveToPhotos to throw for a non-raster format")
        } catch let error as PhotoLibrarySaveError {
            XCTAssertEqual(error, .unsupportedFormat(format: "JSON"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
