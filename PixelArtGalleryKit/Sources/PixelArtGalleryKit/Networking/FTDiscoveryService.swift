import Foundation
import Network

/// Errors raised while browsing for Flaschen Taschen displays.
///
/// Discovery is designed to fail gracefully: callers should treat any error as
/// "no displays found" and fall back to manual entry (issue 0010).
enum FTDiscoveryError: LocalizedError, Equatable {
    /// The `NWBrowser` reported a failed state (e.g. the service type is
    /// malformed or the network is unavailable).
    case browserFailed(String)

    var errorDescription: String? {
        switch self {
        case .browserFailed(let reason):
            return "Display discovery failed: \(reason)"
        }
    }
}

/// On-demand mDNS/Bonjour discovery for Flaschen Taschen displays.
///
/// Browses the local network for the `_flaschen-taschen._tcp` service type using
/// `Network.framework`'s `NWBrowser`, resolves each found endpoint to host/port,
/// reads any advertised TXT metadata (display width/height), and yields plain
/// ``DiscoveredFTDisplay`` values via an `AsyncStream`.
///
/// The service is an `actor`, so it runs off the main actor (the package defaults
/// to `@MainActor` isolation, but `actor` declarations form their own isolation
/// domain) — satisfying the PRD rule that mDNS operations live in an
/// `actor`/`nonisolated` context. It is decoupled from SwiftData: persisting and
/// merging results into the registry is issue 0011.
///
/// Typical use:
/// ```swift
/// let service = FTDiscoveryService()
/// for await display in await service.scan(duration: .seconds(5)) {
///     // handle each discovered display
/// }
/// ```
actor FTDiscoveryService {
    /// The default Bonjour service type advertised by Flaschen Taschen displays.
    static let defaultServiceType = "_flaschen-taschen._tcp"

    private let serviceType: String
    private var browser: NWBrowser?

    /// - Parameter serviceType: Bonjour service type to browse. Defaults to
    ///   ``defaultServiceType``; injectable for testing.
    init(serviceType: String = FTDiscoveryService.defaultServiceType) {
        self.serviceType = serviceType
    }

    /// Start an on-demand scan and stream discovered displays as they resolve.
    ///
    /// Returns an `AsyncStream` that yields a ``DiscoveredFTDisplay`` for each
    /// resolved endpoint, then finishes automatically after `duration` elapses
    /// (or when ``stop()`` is called). A failed browser also finishes the stream
    /// rather than throwing, so callers degrade gracefully to manual entry.
    ///
    /// - Parameter duration: How long to browse before stopping the scan.
    /// - Returns: A stream of discovered displays.
    func scan(duration: Duration = .seconds(5)) -> AsyncStream<DiscoveredFTDisplay> {
        stop()

        AppLog.ftDiscovery.info("Browsing \(self.serviceType, privacy: .public) for \(duration.components.seconds)s")

        return AsyncStream { continuation in
            let parameters = NWParameters()
            parameters.includePeerToPeer = true

            let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
                type: serviceType,
                domain: nil
            )
            let newBrowser = NWBrowser(for: descriptor, using: parameters)
            self.browser = newBrowser

            newBrowser.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    AppLog.ftDiscovery.debug("Browser ready for \(self.serviceType, privacy: .public)")
                case .failed(let error):
                    AppLog.ftDiscovery.error("Browser failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish()
                case .cancelled:
                    continuation.finish()
                default:
                    break
                }
            }

            newBrowser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    if let discovered = Self.discovered(from: result) {
                        AppLog.ftDiscovery.debug("Found \(discovered.serviceName, privacy: .public) at \(discovered.host, privacy: .public):\(discovered.port)")
                        continuation.yield(discovered)
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                Task { await self.stop() }
            }

            newBrowser.start(queue: .global(qos: .userInitiated))

            // Bound the scan so the stream finishes on its own.
            Task {
                try? await Task.sleep(for: duration)
                continuation.finish()
            }
        }
    }

    /// Stop any in-flight scan and release the browser.
    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Translate an `NWBrowser` result into a ``DiscoveredFTDisplay``.
    ///
    /// Resolves the host/port from the result's endpoint and folds in TXT-record
    /// metadata (width/height). Returns `nil` for endpoints whose host/port can't
    /// be extracted (e.g. a not-yet-resolved service reference).
    private static func discovered(from result: NWBrowser.Result) -> DiscoveredFTDisplay? {
        let serviceName = serviceName(for: result.endpoint)
        let txt = txtRecord(from: result.metadata)

        switch result.endpoint {
        case .hostPort(let host, let port):
            return DiscoveredFTDisplay.make(
                host: hostString(host),
                port: Int(port.rawValue),
                serviceName: serviceName,
                txtRecord: txt
            )
        default:
            // A bare Bonjour service reference has no resolved host/port yet;
            // skip it. The browser will deliver a resolved result on a later
            // change, or the FT client can resolve it lazily by name.
            return nil
        }
    }

    /// Best-effort friendly name from an endpoint.
    private static func serviceName(for endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .service(let name, _, _, _):
            return name
        case .hostPort(let host, _):
            return hostString(host)
        default:
            return endpoint.debugDescription
        }
    }

    /// Render an `NWEndpoint.Host` as a plain string without interface suffixes.
    private static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .name(let name, _):
            return name
        case .ipv4(let address):
            return "\(address)"
        case .ipv6(let address):
            return "\(address)"
        @unknown default:
            return "\(host)"
        }
    }

    /// Extract TXT-record key/value pairs from browse metadata, if present.
    private static func txtRecord(from metadata: NWBrowser.Result.Metadata) -> [String: String] {
        guard case .bonjour(let record) = metadata else { return [:] }
        var values: [String: String] = [:]
        for (key, entry) in record.dictionary {
            values[key] = entry
        }
        return values
    }
}
