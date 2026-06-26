import XCTest
@testable import PixelArtGalleryKit

/// Device-free tests for the discovery result model: TXT-record parsing and
/// conversion into a `FlaschenTaschenDisplay`. The live `NWBrowser` path in
/// `FTDiscoveryService` requires a real network with an FT display advertising
/// and cannot be exercised headlessly; these tests cover everything around it.
final class DiscoveredFTDisplayTests: XCTestCase {

    // MARK: - TXT parsing

    func testMakeParsesWidthAndHeightFromTXT() {
        let discovered = DiscoveredFTDisplay.make(
            host: "192.168.1.50",
            port: 1337,
            serviceName: "Office Wall",
            txtRecord: ["width": "64", "height": "32"]
        )

        XCTAssertEqual(discovered.host, "192.168.1.50")
        XCTAssertEqual(discovered.port, 1337)
        XCTAssertEqual(discovered.serviceName, "Office Wall")
        XCTAssertEqual(discovered.displayWidth, 64)
        XCTAssertEqual(discovered.displayHeight, 32)
    }

    func testMakeAcceptsShortAliasKeys() {
        let discovered = DiscoveredFTDisplay.make(
            host: "ft.local",
            port: 1337,
            serviceName: "ft",
            txtRecord: ["w": "45", "h": "35"]
        )

        XCTAssertEqual(discovered.displayWidth, 45)
        XCTAssertEqual(discovered.displayHeight, 35)
    }

    func testMakeIsCaseInsensitiveForKeys() {
        let discovered = DiscoveredFTDisplay.make(
            host: "ft.local",
            port: 1337,
            serviceName: "ft",
            txtRecord: ["Width": "100", "HEIGHT": "80"]
        )

        XCTAssertEqual(discovered.displayWidth, 100)
        XCTAssertEqual(discovered.displayHeight, 80)
    }

    func testMakeYieldsNilDimensionsWhenTXTEmpty() {
        let discovered = DiscoveredFTDisplay.make(
            host: "ft.local",
            port: 1337,
            serviceName: "ft",
            txtRecord: [:]
        )

        XCTAssertNil(discovered.displayWidth)
        XCTAssertNil(discovered.displayHeight)
    }

    func testMakeIgnoresNonPositiveOrUnparseableValues() {
        let discovered = DiscoveredFTDisplay.make(
            host: "ft.local",
            port: 1337,
            serviceName: "ft",
            txtRecord: ["width": "0", "height": "tall"]
        )

        XCTAssertNil(discovered.displayWidth)
        XCTAssertNil(discovered.displayHeight)
    }

    func testMakeTrimsWhitespaceAroundValues() {
        let discovered = DiscoveredFTDisplay.make(
            host: "ft.local",
            port: 1337,
            serviceName: "ft",
            txtRecord: ["width": " 48 ", "height": " 24 "]
        )

        XCTAssertEqual(discovered.displayWidth, 48)
        XCTAssertEqual(discovered.displayHeight, 24)
    }

    // MARK: - Conversion to FlaschenTaschenDisplay

    @MainActor
    func testMakeDisplayModelUsesAdvertisedDimensionsAndMdnsSource() {
        let discovered = DiscoveredFTDisplay(
            host: "10.0.0.7",
            port: 1337,
            serviceName: "Break Room",
            displayWidth: 64,
            displayHeight: 64
        )

        let model = discovered.makeDisplayModel()

        XCTAssertEqual(model.host, "10.0.0.7")
        XCTAssertEqual(model.port, 1337)
        XCTAssertEqual(model.displayName, "Break Room")
        XCTAssertEqual(model.displayWidth, 64)
        XCTAssertEqual(model.displayHeight, 64)
        XCTAssertEqual(model.source, "mdns")
        XCTAssertEqual(model.endpoint, "10.0.0.7:1337")
        XCTAssertEqual(model.resolution, "64×64")
    }

    @MainActor
    func testMakeDisplayModelFallsBackToDefaultsWhenDimensionsMissing() {
        let discovered = DiscoveredFTDisplay(
            host: "ft.local",
            port: 1337,
            serviceName: "ft"
        )

        let model = discovered.makeDisplayModel(defaultWidth: 45, defaultHeight: 35)

        XCTAssertEqual(model.displayWidth, 45)
        XCTAssertEqual(model.displayHeight, 35)
        XCTAssertEqual(model.source, "mdns")
    }

    @MainActor
    func testMakeDisplayModelRecordsProvidedDiscoveredDate() {
        let when = Date(timeIntervalSince1970: 1_000_000)
        let discovered = DiscoveredFTDisplay(
            host: "ft.local",
            port: 1337,
            serviceName: "ft"
        )

        let model = discovered.makeDisplayModel(discoveredDate: when)

        XCTAssertEqual(model.discoveredDate, when)
    }
}
