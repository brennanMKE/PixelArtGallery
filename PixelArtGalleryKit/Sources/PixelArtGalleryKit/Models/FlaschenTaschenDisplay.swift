import Foundation
import SwiftData

/// Represents a Flaschen Taschen LED display discovered on the local network or added manually.
/// Stores both connection information (host/port) and display capabilities (dimensions)
/// for creating variants at appropriate sizes and sending pixelated images directly to the display.
@Model
public final class FlaschenTaschenDisplay {
    /// Unique identifier for this display entry
    @Attribute(.unique) public var id: UUID

    /// Hostname or IP address of the display
    var host: String

    /// Service port of the display
    var port: Int

    /// User-friendly display name (e.g., "Office Wall", "Break Room")
    var displayName: String

    /// Native pixel width of the display
    var displayWidth: Int

    /// Native pixel height of the display
    var displayHeight: Int

    /// Timestamp when this display was discovered or added
    var discoveredDate: Date

    /// Source of this display entry: "mdns" (discovered via mDNS), "manual"
    /// (user-entered), or "default" (the built-in seeded default, see
    /// ``defaultSource``)
    var source: String // "mdns", "manual", or "default"

    /// Default paint layer (FT z-offset) used when sending to this display (#0047).
    ///
    /// Flaschen Taschen composites images by layer; a higher layer paints in
    /// front. Valid values are ``layerRange`` (1…15) — layer 0 is reserved and
    /// must never be used. Has an inline default so SwiftData can lightweight-
    /// migrate existing stores (records created before this property gain
    /// ``defaultLayer``).
    var layer: Int = FlaschenTaschenDisplay.defaultLayer

    /// Initialize a new FT display entry
    /// - Parameters:
    ///   - host: Hostname or IP address
    ///   - port: Display service port
    ///   - displayName: User-friendly name
    ///   - displayWidth: Display width in pixels
    ///   - displayHeight: Display height in pixels
    ///   - discoveredDate: Timestamp of discovery/creation (defaults to now)
    ///   - source: "mdns", "manual", or "default"
    init(
        host: String,
        port: Int,
        displayName: String,
        displayWidth: Int,
        displayHeight: Int,
        discoveredDate: Date = Date(),
        source: String = "manual",
        layer: Int = FlaschenTaschenDisplay.defaultLayer
    ) {
        self.id = UUID()
        self.host = host
        self.port = port
        self.displayName = displayName
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.discoveredDate = discoveredDate
        self.source = source
        self.layer = Self.clampedLayer(layer)
    }

    /// The `source` value used for the built-in seeded default display (#0021).
    static let defaultSource = "default"

    /// Valid range for a display's paint layer (FT z-offset), #0047. Layer 0 is
    /// reserved and never used; the app always paints on 1…15.
    static let layerRange = 1...15

    /// Default paint layer for a display when none is otherwise chosen (#0047).
    static let defaultLayer = 5

    /// Clamp an arbitrary integer into ``layerRange`` so a display's layer can
    /// never be 0 or out of bounds, whatever the source (older store, bad input).
    static func clampedLayer(_ value: Int) -> Int {
        min(max(value, layerRange.lowerBound), layerRange.upperBound)
    }

    /// Build the built-in default Flaschen Taschen display: the standard FT
    /// hostname and port with a 45×35 geometry. Seeded on first launch so the
    /// "Send to Display" picker is never empty out of the box, and editable in
    /// Settings afterwards.
    static func makeDefault() -> FlaschenTaschenDisplay {
        FlaschenTaschenDisplay(
            host: "flaschentaschen.local",
            port: 1337,
            displayName: "Flaschen Taschen",
            displayWidth: 45,
            displayHeight: 35,
            source: defaultSource
        )
    }

    /// Pick which display a send picker should select (#0032).
    ///
    /// Keeps `current` whenever it still identifies one of `candidates`
    /// (never stomps a user's valid explicit choice); otherwise prefers the
    /// built-in default display (`source == defaultSource`), falling back to
    /// the first candidate, or `nil` when there are none. Operates on plain
    /// `(id, source)` pairs so it is unit-testable without SwiftData.
    static func preferredSelection(
        current: UUID?,
        among candidates: [(id: UUID, source: String)]
    ) -> UUID? {
        if let current, candidates.contains(where: { $0.id == current }) {
            return current
        }
        return candidates.first(where: { $0.source == defaultSource })?.id
            ?? candidates.first?.id
    }

    /// Computed property for a user-friendly endpoint description
    var endpoint: String {
        "\(host):\(port)"
    }

    /// Computed property for display resolution description
    var resolution: String {
        "\(displayWidth)×\(displayHeight)"
    }
}
