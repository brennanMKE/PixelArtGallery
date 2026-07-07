import Testing
@testable import PixelArtGalleryKit

/// Verifies the per-identity Application Support folder derivation (#0045):
/// the beta bundle ID gets its own folder so dev builds never touch the
/// released app's data, and everything else stays on the original folder.
@Suite struct StorageFolderTests {
    @Test func productionBundleIdentifierUsesOriginalFolder() {
        #expect(
            StorageFolder.name(forBundleIdentifier: "co.sstools.PixelArtGallery") == "PixelArtGallery"
        )
    }

    @Test func betaBundleIdentifierUsesSeparateFolder() {
        #expect(
            StorageFolder.name(forBundleIdentifier: "co.sstools.PixelArtGallery.beta") == "PixelArtGallery-Beta"
        )
    }

    @Test func nilBundleIdentifierFallsBackToOriginalFolder() {
        #expect(StorageFolder.name(forBundleIdentifier: nil) == "PixelArtGallery")
    }

    @Test func unrelatedBundleIdentifierUsesOriginalFolder() {
        #expect(
            StorageFolder.name(forBundleIdentifier: "co.sstools.SomethingElse") == "PixelArtGallery"
        )
    }
}
