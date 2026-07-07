import Testing
import Foundation
@testable import PixelArtGalleryKit

/// Device-free tests for the discovery result model: TXT-record parsing and
/// conversion into a `FlaschenTaschenDisplay`. The live `NWBrowser` path in
/// `FTDiscoveryService` requires a real network with an FT display advertising
/// and cannot be exercised headlessly; these tests cover everything around it.
@Suite struct DiscoveredFTDisplayTests {

    // MARK: - TXT parsing

    @Test func makeParsesWidthAndHeightFromTXT() {
        let discovered = DiscoveredFTDisplay.make(
            host: "192.168.1.50",
            port: 1337,
            serviceName: "Office Wall",
            txtRecord: ["width": "64", "height": "32"]
        )

        #expect(discovered.host == "192.168.1.50")
        #expect(discovered.port == 1337)
        #expect(discovered.serviceName == "Office Wall")
        #expect(discovered.displayWidth == 64)
        #expect(discovered.displayHeight == 32)
    }

    @Test func makeAcceptsShortAliasKeys() {
        let discovered = DiscoveredFTDisplay.make(
            host: "ft.local",
            port: 1337,
            serviceName: "ft",
            txtRecord: ["w": "45", "h": "35"]
        )

        #expect(discovered.displayWidth == 45)
        #expect(discovered.displayHeight == 35)
    }

    @Test func makeIsCaseInsensitiveForKeys() {
        let discovered = DiscoveredFTDisplay.make(
            host: "ft.local",
            port: 1337,
            serviceName: "ft",
            txtRecord: ["Width": "100", "HEIGHT": "80"]
        )

        #expect(discovered.displayWidth == 100)
        #expect(discovered.displayHeight == 80)
    }

    @Test func makeYieldsNilDimensionsWhenTXTEmpty() {
        let discovered = DiscoveredFTDisplay.make(
            host: "ft.local",
            port: 1337,
            serviceName: "ft",
            txtRecord: [:]
        )

        #expect(discovered.displayWidth == nil)
        #expect(discovered.displayHeight == nil)
    }

    @Test func makeIgnoresNonPositiveOrUnparseableValues() {
        let discovered = DiscoveredFTDisplay.make(
            host: "ft.local",
            port: 1337,
            serviceName: "ft",
            txtRecord: ["width": "0", "height": "tall"]
        )

        #expect(discovered.displayWidth == nil)
        #expect(discovered.displayHeight == nil)
    }

    @Test func makeTrimsWhitespaceAroundValues() {
        let discovered = DiscoveredFTDisplay.make(
            host: "ft.local",
            port: 1337,
            serviceName: "ft",
            txtRecord: ["width": " 48 ", "height": " 24 "]
        )

        #expect(discovered.displayWidth == 48)
        #expect(discovered.displayHeight == 24)
    }

    // MARK: - Conversion to FlaschenTaschenDisplay

    @MainActor
    @Test func makeDisplayModelUsesAdvertisedDimensionsAndMdnsSource() {
        let discovered = DiscoveredFTDisplay(
            host: "10.0.0.7",
            port: 1337,
            serviceName: "Break Room",
            displayWidth: 64,
            displayHeight: 64
        )

        let model = discovered.makeDisplayModel()

        #expect(model.host == "10.0.0.7")
        #expect(model.port == 1337)
        #expect(model.displayName == "Break Room")
        #expect(model.displayWidth == 64)
        #expect(model.displayHeight == 64)
        #expect(model.source == "mdns")
        #expect(model.endpoint == "10.0.0.7:1337")
        #expect(model.resolution == "64×64")
    }

    @MainActor
    @Test func makeDisplayModelFallsBackToDefaultsWhenDimensionsMissing() {
        let discovered = DiscoveredFTDisplay(
            host: "ft.local",
            port: 1337,
            serviceName: "ft"
        )

        let model = discovered.makeDisplayModel(defaultWidth: 45, defaultHeight: 35)

        #expect(model.displayWidth == 45)
        #expect(model.displayHeight == 35)
        #expect(model.source == "mdns")
    }

    @MainActor
    @Test func makeDisplayModelRecordsProvidedDiscoveredDate() {
        let when = Date(timeIntervalSince1970: 1_000_000)
        let discovered = DiscoveredFTDisplay(
            host: "ft.local",
            port: 1337,
            serviceName: "ft"
        )

        let model = discovered.makeDisplayModel(discoveredDate: when)

        #expect(model.discoveredDate == when)
    }
}
