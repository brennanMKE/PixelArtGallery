import Testing
@testable import PixelArtGalleryKit

/// Pins the Bonjour service type the app browses to the type declared in
/// `Configuration/Info-iOS.plist`'s `NSBonjourServices` array. FT displays
/// advertise `_flaschen-taschen._udp` (issue 0059); if this constant and the
/// plist entry ever drift apart, iOS silently denies the browse and discovery
/// finds nothing, so this test exists to catch that drift here rather than on
/// a device.
@Suite struct FTDiscoveryServiceTests {

    @Test func defaultServiceTypeIsUDP() {
        #expect(FTDiscoveryService.defaultServiceType == "_flaschen-taschen._udp")
    }
}
