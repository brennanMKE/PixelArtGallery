import XCTest
@testable import PixelArtGalleryKit

final class AppLogTests: XCTestCase {
    /// The category set must match the PRD's fixed list exactly (PRD "Logging").
    func testCategoriesMatchPRD() {
        let categories = Set(AppLog.Category.allCases.map(\.rawValue))
        XCTAssertEqual(
            categories,
            ["Gallery", "ImageProcessor", "Variant", "FTDiscovery", "Export", "GridRenderer", "Updates"]
        )
    }

    /// All loggers share the single app subsystem.
    func testSubsystemMatchesBundlePrefix() {
        XCTAssertEqual(AppLog.subsystem, "co.sstools.PixelArtGallery")
    }
}
