import Testing
@testable import PixelArtGalleryKit

@Suite struct AppLogTests {
    /// The category set must match the PRD's fixed list exactly (PRD "Logging").
    @Test func categoriesMatchPRD() {
        let categories = Set(AppLog.Category.allCases.map(\.rawValue))
        #expect(
            categories ==
            ["Gallery", "ImageProcessor", "Variant", "FTDiscovery", "Export", "GridRenderer", "Updates"]
        )
    }

    /// All loggers share the single app subsystem.
    @Test func subsystemMatchesBundlePrefix() {
        #expect(AppLog.subsystem == "co.sstools.PixelArtGallery")
    }
}
