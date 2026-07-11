import Testing
import Network
@testable import PixelArtGalleryKit

/// Pins the Bonjour service type the app browses to the type declared in
/// `Configuration/Info-iOS.plist`'s `NSBonjourServices` array. FT displays
/// advertise `_flaschen-taschen._udp` (issue 0059); if this constant and the
/// plist entry ever drift apart, iOS silently denies the browse and discovery
/// finds nothing, so this test exists to catch that drift here rather than on
/// a device.
///
/// The live `NWBrowser` → resolve → yield pipeline in `scan(duration:)` needs a
/// real network with an FT display advertising and can't be exercised
/// headlessly. `display(fromResolvedEndpoint:serviceName:txtRecord:)` is the
/// pure extraction step both the live `.ready` handler and these tests use
/// (issue 0060), so it pins the endpoint/TXT-folding logic without a network.
@Suite struct FTDiscoveryServiceTests {

    @Test func defaultServiceTypeIsUDP() {
        #expect(FTDiscoveryService.defaultServiceType == "_flaschen-taschen._udp")
    }

    // MARK: - display(fromResolvedEndpoint:serviceName:txtRecord:)

    @Test func resolvedHostPortEndpointBuildsDisplay() {
        let endpoint = NWEndpoint.hostPort(host: .ipv4(IPv4Address("192.168.4.26")!), port: 1337)

        let discovered = FTDiscoveryService.display(
            fromResolvedEndpoint: endpoint,
            serviceName: "Brennan's Mac FT",
            txtRecord: ["width": "45", "height": "35"]
        )

        #expect(discovered?.host == "192.168.4.26")
        #expect(discovered?.port == 1337)
        #expect(discovered?.serviceName == "Brennan's Mac FT")
        #expect(discovered?.displayWidth == 45)
        #expect(discovered?.displayHeight == 35)
    }

    @Test func hostnameEndpointBuildsDisplay() {
        let endpoint = NWEndpoint.hostPort(host: .name("ft-esp32.local", nil), port: 1337)

        let discovered = FTDiscoveryService.display(
            fromResolvedEndpoint: endpoint,
            serviceName: "ft-esp32",
            txtRecord: [:]
        )

        #expect(discovered?.host == "ft-esp32.local")
        #expect(discovered?.port == 1337)
        #expect(discovered?.displayWidth == nil)
        #expect(discovered?.displayHeight == nil)
    }

    @Test func unresolvedServiceEndpointYieldsNoDisplay() {
        let endpoint = NWEndpoint.service(
            name: "ft-esp32",
            type: "_flaschen-taschen._udp",
            domain: "local.",
            interface: nil
        )

        let discovered = FTDiscoveryService.display(
            fromResolvedEndpoint: endpoint,
            serviceName: "ft-esp32",
            txtRecord: [:]
        )

        #expect(discovered == nil)
    }
}
