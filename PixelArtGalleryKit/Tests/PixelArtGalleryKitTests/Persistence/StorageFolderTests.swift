import XCTest
@testable import PixelArtGalleryKit

/// Verifies the per-identity Application Support folder derivation (#0045):
/// the beta bundle ID gets its own folder so dev builds never touch the
/// released app's data, and everything else stays on the original folder.
final class StorageFolderTests: XCTestCase {
    func testProductionBundleIdentifierUsesOriginalFolder() {
        XCTAssertEqual(
            StorageFolder.name(forBundleIdentifier: "co.sstools.PixelArtGallery"),
            "PixelArtGallery"
        )
    }

    func testBetaBundleIdentifierUsesSeparateFolder() {
        XCTAssertEqual(
            StorageFolder.name(forBundleIdentifier: "co.sstools.PixelArtGallery.beta"),
            "PixelArtGallery-Beta"
        )
    }

    func testNilBundleIdentifierFallsBackToOriginalFolder() {
        XCTAssertEqual(StorageFolder.name(forBundleIdentifier: nil), "PixelArtGallery")
    }

    func testUnrelatedBundleIdentifierUsesOriginalFolder() {
        XCTAssertEqual(
            StorageFolder.name(forBundleIdentifier: "co.sstools.SomethingElse"),
            "PixelArtGallery"
        )
    }
}
