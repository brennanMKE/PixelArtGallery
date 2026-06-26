import Foundation

/// A plain, `Sendable` value describing a Flaschen Taschen display found on the
/// local network via mDNS.
///
/// This type is intentionally decoupled from SwiftData so the discovery service
/// stays testable and can run in a `nonisolated` context. Persisting/merging a
/// discovered display into the registry (issue 0011) is done by converting this
/// value into a ``FlaschenTaschenDisplay`` via ``makeDisplayModel()``.
nonisolated struct DiscoveredFTDisplay: Sendable, Hashable {
    /// Resolved hostname or IP address of the display.
    let host: String

    /// Resolved service port of the display.
    let port: Int

    /// The Bonjour service instance name as advertised (e.g. "Office Wall").
    /// Used as the default user-friendly display name.
    let serviceName: String

    /// Native pixel width parsed from the service TXT record, if advertised.
    let displayWidth: Int?

    /// Native pixel height parsed from the service TXT record, if advertised.
    let displayHeight: Int?

    init(
        host: String,
        port: Int,
        serviceName: String,
        displayWidth: Int? = nil,
        displayHeight: Int? = nil
    ) {
        self.host = host
        self.port = port
        self.serviceName = serviceName
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
    }

    /// Parse the width/height advertised in a Bonjour TXT record into a
    /// ``DiscoveredFTDisplay``.
    ///
    /// Flaschen Taschen displays may advertise their native resolution in TXT
    /// metadata. This helper looks for the common keys (`width`/`height`, with
    /// `w`/`h` accepted as aliases) and folds them into the value. Missing or
    /// unparseable keys yield `nil` dimensions rather than failing, so a display
    /// that advertises no metadata is still discoverable.
    ///
    /// - Parameters:
    ///   - host: Resolved host.
    ///   - port: Resolved port.
    ///   - serviceName: Advertised Bonjour instance name.
    ///   - txtRecord: Key/value pairs from the service's TXT record.
    static func make(
        host: String,
        port: Int,
        serviceName: String,
        txtRecord: [String: String]
    ) -> DiscoveredFTDisplay {
        DiscoveredFTDisplay(
            host: host,
            port: port,
            serviceName: serviceName,
            displayWidth: parseDimension(txtRecord, keys: ["width", "w"]),
            displayHeight: parseDimension(txtRecord, keys: ["height", "h"])
        )
    }

    /// Look up the first matching key (case-insensitively) in a TXT record and
    /// parse it as a positive pixel dimension. Returns `nil` if no key matches or
    /// the value is not a positive integer.
    private static func parseDimension(_ txt: [String: String], keys: [String]) -> Int? {
        for key in keys {
            // TXT keys are conventionally lowercase, but match defensively.
            if let raw = txt.first(where: { $0.key.lowercased() == key })?.value,
               let value = Int(raw.trimmingCharacters(in: .whitespaces)),
               value > 0 {
                return value
            }
        }
        return nil
    }

    /// Convert this discovered value into a persistable ``FlaschenTaschenDisplay``
    /// model with `source = "mdns"`.
    ///
    /// Width/height that the display did not advertise fall back to the supplied
    /// defaults (the FT software default panel size is 45×35, but callers may
    /// override). Merging this model into SwiftData — deduplicating against
    /// existing records by endpoint — is the responsibility of issue 0011.
    ///
    /// - Parameters:
    ///   - defaultWidth: Width to use when none was advertised.
    ///   - defaultHeight: Height to use when none was advertised.
    ///   - discoveredDate: Timestamp to record (defaults to now).
    ///
    /// `@MainActor` because ``FlaschenTaschenDisplay`` is a SwiftData `@Model`;
    /// the rest of this value type stays `nonisolated` so discovery can run off
    /// the main actor.
    @MainActor
    func makeDisplayModel(
        defaultWidth: Int = 45,
        defaultHeight: Int = 35,
        discoveredDate: Date = Date()
    ) -> FlaschenTaschenDisplay {
        FlaschenTaschenDisplay(
            host: host,
            port: port,
            displayName: serviceName,
            displayWidth: displayWidth ?? defaultWidth,
            displayHeight: displayHeight ?? defaultHeight,
            discoveredDate: discoveredDate,
            source: "mdns"
        )
    }
}
